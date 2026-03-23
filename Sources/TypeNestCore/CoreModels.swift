import Foundation

public enum TypeNestError: LocalizedError, Equatable, Sendable {
    case invalidRoot(String)
    case emptyRawExtensions
    case emptyCustomExtensions
    case unsupportedPreset(String)
    case missingDestination
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .invalidRoot(path):
            return "Target root does not exist or is not a directory: \(path)"
        case .emptyRawExtensions:
            return "RAW extensions are empty."
        case .emptyCustomExtensions:
            return "At least one custom extension is required."
        case let .unsupportedPreset(preset):
            return "Unsupported preset: \(preset)"
        case .missingDestination:
            return "Missing destination path for a non-ignore action."
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}

public enum Action: String, Codable, CaseIterable, Sendable {
    case move
    case copy
    case ignore
}

public enum DestinationMode: String, Codable, CaseIterable, Sendable {
    case subfolder
    case aggregate
}

public enum CollisionPolicy: String, Codable, CaseIterable, Sendable {
    case skip
    case overwrite
    case rename
}

public enum RunMode: String, Codable, CaseIterable, Sendable {
    case dryRun = "dry-run"
    case move
    case copy
}

public enum OperationStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case executed
    case skipped
    case error
}

public enum PresetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rawJpegCleanup = "raw_jpeg_cleanup"
    case customExtensions = "custom_extensions"

    public var id: String { rawValue }
}

public struct GroupRule: Codable, Hashable, Sendable {
    public var name: String
    public var action: Action
    public var destinationMode: DestinationMode
    public var destinationName: String?

    public init(
        name: String,
        action: Action = .ignore,
        destinationMode: DestinationMode = .subfolder,
        destinationName: String? = nil
    ) {
        self.name = name
        self.action = action
        self.destinationMode = destinationMode
        self.destinationName = destinationName
    }
}

public struct RuleSet: Codable, Hashable, Sendable {
    public var name: String
    public var extensionToGroup: [String: String]
    public var groups: [String: GroupRule]
    public var extensionAliases: [String: String]
    public var unknownGroup: String?
    public var aggregateRoot: String
    public var sidecarExtension: String?
    public var sidecarRawExtensions: [String]
    public var sidecarGroup: String?

    public init(
        name: String,
        extensionToGroup: [String: String],
        groups: [String: GroupRule],
        extensionAliases: [String: String] = [:],
        unknownGroup: String? = nil,
        aggregateRoot: String = "_sorted",
        sidecarExtension: String? = nil,
        sidecarRawExtensions: [String] = ["raw"],
        sidecarGroup: String? = nil
    ) {
        self.name = name
        self.extensionToGroup = extensionToGroup
        self.groups = groups
        self.extensionAliases = extensionAliases
        self.unknownGroup = unknownGroup
        self.aggregateRoot = aggregateRoot
        self.sidecarExtension = sidecarExtension
        self.sidecarRawExtensions = sidecarRawExtensions
        self.sidecarGroup = sidecarGroup
    }
}

public struct PlannerOptions: Codable, Hashable, Sendable {
    public var rootURL: URL
    public var recursive: Bool
    public var excludeDirectories: Set<String>
    public var runMode: RunMode
    public var collisionPolicy: CollisionPolicy

    public init(
        rootURL: URL,
        recursive: Bool = true,
        excludeDirectories: Set<String> = [],
        runMode: RunMode = .dryRun,
        collisionPolicy: CollisionPolicy = .skip
    ) {
        self.rootURL = rootURL
        self.recursive = recursive
        self.excludeDirectories = excludeDirectories
        self.runMode = runMode
        self.collisionPolicy = collisionPolicy
    }
}

public struct Operation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var sourceURL: URL
    public var destinationURL: URL?
    public var action: Action
    public var reason: String
    public var status: OperationStatus
    public var error: String?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL?,
        action: Action,
        reason: String,
        status: OperationStatus = .planned,
        error: String? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.action = action
        self.reason = reason
        self.status = status
        self.error = error
    }
}

public struct RunSummary: Codable, Hashable, Sendable {
    public var scannedFiles: Int
    public var plannedOperations: Int
    public var executed: Int
    public var skipped: Int
    public var errors: Int
    public var cancelled: Bool

    public init(
        scannedFiles: Int = 0,
        plannedOperations: Int = 0,
        executed: Int = 0,
        skipped: Int = 0,
        errors: Int = 0,
        cancelled: Bool = false
    ) {
        self.scannedFiles = scannedFiles
        self.plannedOperations = plannedOperations
        self.executed = executed
        self.skipped = skipped
        self.errors = errors
        self.cancelled = cancelled
    }
}

public struct PlanResult: Codable, Hashable, Sendable {
    public var operations: [Operation]
    public var summary: RunSummary

    public init(operations: [Operation], summary: RunSummary) {
        self.operations = operations
        self.summary = summary
    }
}
