import Foundation

public let fixedJPEGDirectory = "jpeg"
public let fixedRAWDirectory = "raw"

public func rawJpegCleanupPreset(
    jpegFolderName: String = fixedJPEGDirectory,
    rawFolderName: String = fixedRAWDirectory,
    rawExtensions: [String] = ["raw", "arw"],
    mergeJpgAndJpeg: Bool = true,
    destinationMode: DestinationMode = .subfolder,
    aggregateRoot: String = "_sorted"
) throws -> RuleSet {
    let normalizedRawExtensions = Array(
        Set(
            rawExtensions.compactMap { normalizeExtensionToken($0) }
        )
    ).sorted()

    guard !normalizedRawExtensions.isEmpty else {
        throw TypeNestError.emptyRawExtensions
    }

    var groups: [String: GroupRule] = [
        "raw": GroupRule(
            name: "raw",
            action: .move,
            destinationMode: destinationMode,
            destinationName: jpegSafeName(rawFolderName, fallback: fixedRAWDirectory)
        ),
        "sidecar": GroupRule(
            name: "sidecar",
            action: .ignore,
            destinationMode: destinationMode,
            destinationName: "sidecar"
        ),
    ]

    var extensionToGroup = Dictionary(uniqueKeysWithValues: normalizedRawExtensions.map { ($0, "raw") })
    var extensionAliases: [String: String] = [:]

    if mergeJpgAndJpeg {
        groups["jpeg"] = GroupRule(
            name: "jpeg",
            action: .move,
            destinationMode: destinationMode,
            destinationName: jpegSafeName(jpegFolderName, fallback: fixedJPEGDirectory)
        )
        extensionToGroup["jpeg"] = "jpeg"
        extensionAliases["jpg"] = "jpeg"
        extensionAliases["jpeg"] = "jpeg"
    } else {
        groups["jpg"] = GroupRule(
            name: "jpg",
            action: .move,
            destinationMode: destinationMode,
            destinationName: "jpg"
        )
        groups["jpeg"] = GroupRule(
            name: "jpeg",
            action: .move,
            destinationMode: destinationMode,
            destinationName: jpegSafeName(jpegFolderName, fallback: fixedJPEGDirectory)
        )
        extensionToGroup["jpg"] = "jpg"
        extensionToGroup["jpeg"] = "jpeg"
        extensionAliases["jpg"] = "jpg"
        extensionAliases["jpeg"] = "jpeg"
    }

    return RuleSet(
        name: PresetKind.rawJpegCleanup.rawValue,
        extensionToGroup: extensionToGroup,
        groups: groups,
        extensionAliases: extensionAliases,
        unknownGroup: nil,
        aggregateRoot: aggregateRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "_sorted" : aggregateRoot,
        sidecarExtension: "xmp",
        sidecarRawExtensions: normalizedRawExtensions,
        sidecarGroup: "sidecar"
    )
}

public func customExtensionsPreset(
    extensions: [String],
    mergeJpgAndJpeg: Bool = true,
    destinationMode: DestinationMode = .subfolder,
    aggregateRoot: String = "_sorted"
) throws -> RuleSet {
    let normalizedExtensions = Array(
        Set(
            extensions.compactMap { normalizeExtensionToken($0) }
        )
    ).sorted()

    guard !normalizedExtensions.isEmpty else {
        throw TypeNestError.emptyCustomExtensions
    }

    var groups: [String: GroupRule] = [:]
    var extensionToGroup: [String: String] = [:]

    for normalized in normalizedExtensions {
        let groupName: String
        let destinationName: String

        if mergeJpgAndJpeg && (normalized == "jpg" || normalized == "jpeg") {
            groupName = "jpeg"
            destinationName = fixedJPEGDirectory
        } else {
            groupName = normalized
            destinationName = normalized
        }

        if groups[groupName] == nil {
            groups[groupName] = GroupRule(
                name: groupName,
                action: .move,
                destinationMode: destinationMode,
                destinationName: destinationName
            )
        }
        extensionToGroup[normalized] = groupName
    }

    return RuleSet(
        name: PresetKind.customExtensions.rawValue,
        extensionToGroup: extensionToGroup,
        groups: groups,
        extensionAliases: [:],
        unknownGroup: nil,
        aggregateRoot: aggregateRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "_sorted" : aggregateRoot
    )
}

private func jpegSafeName(_ raw: String, fallback: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}
