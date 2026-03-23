import Foundation

public func scanFiles(
    rootURL: URL,
    recursive: Bool = true,
    excludeDirectories: Set<String> = [],
    shouldStop: (@Sendable () -> Bool)? = nil
) throws -> [URL] {
    let root = rootURL.standardizedDirectoryURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw TypeNestError.invalidRoot(root.path)
    }

    let exclusions = buildExclusionSets(root: root, excludeDirectories: excludeDirectories)
    var results: [URL] = []

    if !recursive {
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        )
        for candidate in contents {
            if shouldStop?() == true {
                throw TypeNestError.cancelled
            }
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                results.append(candidate.standardizedFileURL)
            }
        }
        return results.sorted(by: sortByPath)
    }

    let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
        options: [],
        errorHandler: nil
    )

    while let item = enumerator?.nextObject() as? URL {
        if shouldStop?() == true {
            throw TypeNestError.cancelled
        }

        let candidate = item.standardizedFileURL
        let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            if shouldExcludeDirectory(candidate, root: root, exclusions: exclusions) {
                enumerator?.skipDescendants()
            }
            continue
        }

        if values.isRegularFile == true {
            results.append(candidate)
        }
    }

    return results.sorted(by: sortByPath)
}

public func createPlan(
    options: PlannerOptions,
    ruleSet: RuleSet,
    shouldStop: (@Sendable () -> Bool)? = nil
) throws -> PlanResult {
    let files = try scanFiles(
        rootURL: options.rootURL,
        recursive: options.recursive,
        excludeDirectories: options.excludeDirectories.union(
            managedExclusionDirectories(for: ruleSet, rootURL: options.rootURL)
        ),
        shouldStop: shouldStop
    )
    return plan(files: files, ruleSet: ruleSet, options: options)
}

public func plan(files: [URL], ruleSet: RuleSet, options: PlannerOptions) -> PlanResult {
    let sortedFiles = files.map(\.standardizedFileURL).sorted(by: sortByPath)
    let rawIndex = buildRawIndex(files: sortedFiles, rawExtensions: ruleSet.sidecarRawExtensions)
    var plannedDestinations: Set<URL> = []
    var operations: [Operation] = []

    for sourceURL in sortedFiles {
        let (groupName, baseReason) = classifyFile(sourceURL: sourceURL, ruleSet: ruleSet, rawIndex: rawIndex)
        let reason = "\(baseReason), preset=\(ruleSet.name)"

        guard let groupName else {
            operations.append(
                Operation(
                    sourceURL: sourceURL,
                    destinationURL: nil,
                    action: .ignore,
                    reason: reason
                )
            )
            continue
        }

        guard let groupRule = ruleSet.groups[groupName] else {
            operations.append(
                Operation(
                    sourceURL: sourceURL,
                    destinationURL: nil,
                    action: .ignore,
                    reason: "\(reason), missing_group_rule=\(groupName)"
                )
            )
            continue
        }

        let action = effectiveAction(groupAction: groupRule.action, runMode: options.runMode)
        if action == .ignore {
            operations.append(
                Operation(
                    sourceURL: sourceURL,
                    destinationURL: nil,
                    action: .ignore,
                    reason: reason
                )
            )
            continue
        }

        var destinationURL = buildDestinationPath(
            sourceURL: sourceURL,
            groupName: groupName,
            destinationMode: groupRule.destinationMode,
            destinationName: groupRule.destinationName,
            rootURL: options.rootURL.standardizedDirectoryURL,
            aggregateRoot: ruleSet.aggregateRoot
        )

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            operations.append(
                Operation(
                    sourceURL: sourceURL,
                    destinationURL: nil,
                    action: .ignore,
                    reason: "\(reason), already_in_destination"
                )
            )
            continue
        }

        if options.collisionPolicy == .rename {
            destinationURL = resolveRenameDestination(destinationURL, reservedDestinations: plannedDestinations)
        }

        plannedDestinations.insert(destinationURL.standardizedFileURL)
        operations.append(
            Operation(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                action: action,
                reason: reason
            )
        )
    }

    let plannedCount = operations.filter { $0.action != .ignore }.count
    let skippedCount = operations.count - plannedCount
    let summary = RunSummary(
        scannedFiles: sortedFiles.count,
        plannedOperations: plannedCount,
        executed: 0,
        skipped: skippedCount,
        errors: 0,
        cancelled: false
    )
    return PlanResult(operations: operations, summary: summary)
}

public func resolveRenameDestination(_ destinationURL: URL, reservedDestinations: Set<URL> = []) -> URL {
    let destination = destinationURL.standardizedFileURL
    if !reservedDestinations.contains(destination), !FileManager.default.fileExists(atPath: destination.path) {
        return destination
    }

    let directory = destination.deletingLastPathComponent()
    let stem = destination.deletingPathExtension().lastPathComponent
    let pathExtension = destination.pathExtension
    var counter = 1

    while true {
        let filename = pathExtension.isEmpty ? "\(stem)_\(counter)" : "\(stem)_\(counter).\(pathExtension)"
        let candidate = directory.appendingPathComponent(filename)
        if !reservedDestinations.contains(candidate.standardizedFileURL), !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.standardizedFileURL
        }
        counter += 1
    }
}

public func format(operation: Operation) -> String {
    let source = operation.sourceURL.path
    let destination = operation.destinationURL?.path ?? "-"
    let suffix = operation.error.map { ", error=\($0)" } ?? ""
    return "\(operation.status.rawValue.uppercased()) action=\(operation.action.rawValue) source=\(source) dest=\(destination) reason=\(operation.reason)\(suffix)"
}

public func format(summary: RunSummary) -> String {
    let cancelled = summary.cancelled ? ", cancelled=1" : ""
    return "Summary: scanned=\(summary.scannedFiles), planned=\(summary.plannedOperations), executed=\(summary.executed), skipped=\(summary.skipped), errors=\(summary.errors)\(cancelled)"
}

private struct ExclusionSets {
    var names: Set<String>
    var relativePaths: Set<String>
    var absolutePaths: Set<URL>
}

private func buildExclusionSets(root: URL, excludeDirectories: Set<String>) -> ExclusionSets {
    var names: Set<String> = []
    var relativePaths: Set<String> = []
    var absolutePaths: Set<URL> = []

    for raw in excludeDirectories {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            continue
        }

        if value.hasPrefix("/") || value.hasPrefix("~") {
            let expanded = NSString(string: value).expandingTildeInPath
            absolutePaths.insert(URL(fileURLWithPath: expanded).standardizedFileURL)
            continue
        }

        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "/\\")).lowercased()
        guard !cleaned.isEmpty else {
            continue
        }

        let relativeCandidate = root.appendingPathComponent(cleaned).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: relativeCandidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let relative = makeRelativePath(candidate: relativeCandidate, root: root)
            if !relative.isEmpty {
                relativePaths.insert(relative)
            }
            continue
        }

        if cleaned.contains("/") {
            relativePaths.insert(cleaned.replacingOccurrences(of: "\\", with: "/"))
        } else {
            names.insert(cleaned)
        }
    }

    return ExclusionSets(names: names, relativePaths: relativePaths, absolutePaths: absolutePaths)
}

private func managedExclusionDirectories(for ruleSet: RuleSet, rootURL: URL) -> Set<String> {
    let usesAggregateDestination = ruleSet.groups.values.contains {
        $0.action != .ignore && $0.destinationMode == .aggregate
    }
    guard usesAggregateDestination else {
        return []
    }

    let aggregateRoot = ruleSet.aggregateRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    let aggregateDirectory = aggregateRoot.isEmpty ? "_sorted" : aggregateRoot
    return [rootURL.standardizedDirectoryURL.appendingPathComponent(aggregateDirectory).path]
}

private func buildRawIndex(files: [URL], rawExtensions: [String]) -> Set<String> {
    let normalizedRawSet = Set(rawExtensions.compactMap { normalizeExtensionToken($0) }).isEmpty
        ? ["raw"]
        : Set(rawExtensions.compactMap { normalizeExtensionToken($0) })
    var index: Set<String> = []

    for fileURL in files {
        let fileExtension = normalizeExtensionToken(fileURL.pathExtension)
        if let fileExtension, normalizedRawSet.contains(fileExtension) {
            index.insert(rawIndexKey(parentURL: fileURL.deletingLastPathComponent(), stem: fileURL.deletingPathExtension().lastPathComponent))
        }
    }

    return index
}

private func classifyFile(sourceURL: URL, ruleSet: RuleSet, rawIndex: Set<String>) -> (String?, String) {
    let fileExtension = normalizeExtensionToken(sourceURL.pathExtension) ?? ""
    let normalizedExtension = ruleSet.extensionAliases[fileExtension] ?? fileExtension

    if let sidecarExtension = ruleSet.sidecarExtension,
       normalizedExtension == normalizeExtensionToken(sidecarExtension),
       rawIndex.contains(rawIndexKey(parentURL: sourceURL.deletingLastPathComponent(), stem: sourceURL.deletingPathExtension().lastPathComponent)),
       let sidecarGroup = ruleSet.sidecarGroup {
        let rawList = ruleSet.sidecarRawExtensions.joined(separator: "|")
        return (sidecarGroup, "extension=\(normalizedExtension), sidecar_for=\(rawList.isEmpty ? "raw" : rawList)")
    }

    if let groupName = ruleSet.extensionToGroup[normalizedExtension] {
        return (groupName, "extension=\(normalizedExtension.isEmpty ? "(none)" : normalizedExtension), group=\(groupName)")
    }

    if let unknownGroup = ruleSet.unknownGroup {
        return (unknownGroup, "extension=\(normalizedExtension.isEmpty ? "(none)" : normalizedExtension), group=unknown->\(unknownGroup)")
    }

    return (nil, "extension=\(normalizedExtension.isEmpty ? "(none)" : normalizedExtension), group=ignore")
}

private func effectiveAction(groupAction: Action, runMode: RunMode) -> Action {
    if groupAction == .ignore {
        return .ignore
    }
    if runMode == .copy {
        return .copy
    }
    return .move
}

private func buildDestinationPath(
    sourceURL: URL,
    groupName: String,
    destinationMode: DestinationMode,
    destinationName: String?,
    rootURL: URL,
    aggregateRoot: String
) -> URL {
    let targetName = (destinationName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? groupName
    if destinationMode == .subfolder {
        if sourceURL.deletingLastPathComponent().lastPathComponent.lowercased() == targetName.lowercased() {
            return sourceURL.standardizedFileURL
        }
        return sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(targetName)
            .appendingPathComponent(sourceURL.lastPathComponent)
            .standardizedFileURL
    }

    let relativeParent = makeRelativePath(candidate: sourceURL.deletingLastPathComponent(), root: rootURL)
    var destination = rootURL.appendingPathComponent(aggregateRoot).appendingPathComponent(targetName)
    if !relativeParent.isEmpty {
        destination = destination.appendingPathComponent(relativeParent)
    }
    return destination.appendingPathComponent(sourceURL.lastPathComponent).standardizedFileURL
}

private func shouldExcludeDirectory(_ candidate: URL, root: URL, exclusions: ExclusionSets) -> Bool {
    let name = candidate.lastPathComponent.lowercased()
    if exclusions.names.contains(name) {
        return true
    }

    let relative = makeRelativePath(candidate: candidate, root: root)
    if exclusions.relativePaths.contains(relative) {
        return true
    }

    return exclusions.absolutePaths.contains(candidate.standardizedFileURL)
}

private func rawIndexKey(parentURL: URL, stem: String) -> String {
    "\(parentURL.standardizedFileURL.path.lowercased())#\(stem)"
}

private func makeRelativePath(candidate: URL, root: URL) -> String {
    let candidateComponents = candidate.standardizedFileURL.pathComponents
    let rootComponents = root.standardizedFileURL.pathComponents
    guard candidateComponents.starts(with: rootComponents) else {
        return ""
    }
    return candidateComponents.dropFirst(rootComponents.count).joined(separator: "/").lowercased()
}

private func sortByPath(lhs: URL, rhs: URL) -> Bool {
    let normalizedLeft = lhs.path.lowercased()
    let normalizedRight = rhs.path.lowercased()
    if normalizedLeft == normalizedRight {
        return lhs.path < rhs.path
    }
    return normalizedLeft < normalizedRight
}
