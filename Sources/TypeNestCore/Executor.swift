import Foundation

public struct ApplyResult: Sendable {
    public var operations: [Operation]
    public var summary: RunSummary

    public init(operations: [Operation], summary: RunSummary) {
        self.operations = operations
        self.summary = summary
    }
}

public func apply(
    operations: [Operation],
    collisionPolicy: CollisionPolicy,
    logger: ((String) -> Void)? = nil,
    shouldStop: (@Sendable () -> Bool)? = nil
) -> ApplyResult {
    var operations = operations
    var summary = RunSummary(
        scannedFiles: operations.count,
        plannedOperations: operations.filter { $0.action != .ignore }.count,
        executed: 0,
        skipped: 0,
        errors: 0,
        cancelled: false
    )
    var reservedDestinations: Set<URL> = []

    for index in operations.indices {
        if shouldStop?() == true {
            summary.cancelled = true
            markRemainingAsSkipped(operations: &operations, from: index, summary: &summary)
            break
        }

        if operations[index].action == .ignore {
            operations[index].status = .skipped
            summary.skipped += 1
            logOperation(operations[index], logger: logger)
            continue
        }

        guard var destinationURL = operations[index].destinationURL else {
            operations[index].status = .error
            operations[index].error = TypeNestError.missingDestination.localizedDescription
            summary.errors += 1
            logOperation(operations[index], logger: logger)
            continue
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                switch collisionPolicy {
                case .skip:
                    operations[index].status = .skipped
                    operations[index].reason += ", collision=skip"
                    summary.skipped += 1
                    logOperation(operations[index], logger: logger)
                    continue
                case .rename:
                    destinationURL = resolveRenameDestination(destinationURL, reservedDestinations: reservedDestinations)
                    operations[index].destinationURL = destinationURL
                    operations[index].reason += ", collision=rename"
                case .overwrite:
                    try removeExistingItem(at: destinationURL)
                }
            }

            switch operations[index].action {
            case .move:
                try moveFile(sourceURL: operations[index].sourceURL, destinationURL: destinationURL, overwrite: collisionPolicy == .overwrite)
            case .copy:
                try copyFile(sourceURL: operations[index].sourceURL, destinationURL: destinationURL, overwrite: collisionPolicy == .overwrite)
            case .ignore:
                break
            }

            operations[index].status = .executed
            reservedDestinations.insert(destinationURL.standardizedFileURL)
            summary.executed += 1
            logOperation(operations[index], logger: logger)
        } catch {
            operations[index].status = .error
            operations[index].error = error.localizedDescription
            summary.errors += 1
            logOperation(operations[index], logger: logger)
        }
    }

    return ApplyResult(operations: operations, summary: summary)
}

private func copyFile(sourceURL: URL, destinationURL: URL, overwrite: Bool) throws {
    if overwrite, FileManager.default.fileExists(atPath: destinationURL.path) {
        try removeExistingItem(at: destinationURL)
    }
    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
}

private func moveFile(sourceURL: URL, destinationURL: URL, overwrite: Bool) throws {
    if overwrite, FileManager.default.fileExists(atPath: destinationURL.path) {
        try removeExistingItem(at: destinationURL)
    }
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
}

private func removeExistingItem(at url: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return
    }
    if isDirectory.boolValue {
        throw CocoaError(.fileWriteUnsupportedScheme)
    }
    try FileManager.default.removeItem(at: url)
}

private func markRemainingAsSkipped(operations: inout [Operation], from index: Int, summary: inout RunSummary) {
    guard index < operations.count else {
        return
    }

    for nextIndex in index..<operations.count where operations[nextIndex].status == .planned {
        operations[nextIndex].status = .skipped
        summary.skipped += 1
    }
}

private func logOperation(_ operation: Operation, logger: ((String) -> Void)?) {
    guard let logger else {
        return
    }
    logger(format(operation: operation))
}
