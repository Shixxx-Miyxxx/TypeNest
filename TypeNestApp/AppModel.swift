import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum ResultFilter: String, CaseIterable, Identifiable {
        case all
        case planned
        case skipped
        case errors

        var id: String { rawValue }
    }

    @Published var rootFolderPath: String = "" { didSet { persistPreferences() } }
    @Published var preset: PresetKind = .rawJpegCleanup { didSet { persistPreferences() } }
    @Published var executionMode: RunMode = .move { didSet { persistPreferences() } }
    @Published var collisionPolicy: CollisionPolicy = .skip { didSet { persistPreferences() } }
    @Published var recursive: Bool = true { didSet { persistPreferences() } }
    @Published var destinationMode: DestinationMode = .subfolder { didSet { persistPreferences() } }
    @Published var aggregateDirectory: String = "_sorted" { didSet { persistPreferences() } }
    @Published var rawExtensionsText: String = "raw,arw" { didSet { persistPreferences() } }
    @Published var mergeJpgAndJpeg: Bool = true { didSet { persistPreferences() } }
    @Published var customExtensionsText: String = "json,text" { didSet { persistPreferences() } }
    @Published var searchText: String = ""
    @Published var resultFilter: ResultFilter = .all
    @Published var operations: [Operation] = []
    @Published var summary = RunSummary()
    @Published var selectedOperationID: UUID?
    @Published var isRunning = false
    @Published var statusMessage = "Ready."
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?
    private var currentPlanTask: Task<PlanResult, Error>?
    private var currentApplyTask: Task<ApplyResult, Never>?
    private var activeRunID: UUID?
    private var isRestoring = false

    init() {
        restorePreferences()
    }

    var rootFolderURL: URL? {
        let trimmed = rootFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    var selectedOperation: Operation? {
        guard let selectedOperationID else {
            return nil
        }
        return operations.first { $0.id == selectedOperationID }
    }

    var filteredOperations: [Operation] {
        operations.filter { operation in
            if !matchesFilter(operation) {
                return false
            }

            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmedSearch.isEmpty else {
                return true
            }

            let haystack = [
                operation.sourceURL.path.lowercased(),
                operation.destinationURL?.path.lowercased() ?? "",
                operation.reason.lowercased(),
                operation.error?.lowercased() ?? "",
            ]
            return haystack.contains { $0.contains(trimmedSearch) }
        }
    }

    var validationMessage: String? {
        guard let rootFolderURL else {
            return "Choose a target folder first."
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootFolderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "Target folder does not exist."
        }

        if preset == .rawJpegCleanup, splitExtensionList(rawExtensionsText).isEmpty {
            return "RAW extensions are empty."
        }

        if preset == .customExtensions, splitExtensionList(customExtensionsText).isEmpty {
            return "At least one custom extension is required."
        }

        return nil
    }

    var canPreview: Bool {
        !isRunning && validationMessage == nil
    }

    var canRun: Bool {
        !isRunning && validationMessage == nil
    }

    var requiresOverwriteConfirmation: Bool {
        collisionPolicy == .overwrite
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder you want TypeNest to sort."

        if panel.runModal() == .OK, let url = panel.url {
            setRootFolder(url)
        }
    }

    func setRootFolder(_ url: URL) {
        rootFolderPath = url.standardizedFileURL.path
    }

    func clearRootFolder() {
        rootFolderPath = ""
        operations = []
        summary = RunSummary()
        selectedOperationID = nil
    }

    func previewPlan() {
        run(with: .dryRun)
    }

    func runNow() {
        run(with: executionMode == .copy ? .copy : .move)
    }

    func stopCurrentTask() {
        if currentApplyTask != nil {
            currentApplyTask?.cancel()
        } else {
            currentPlanTask?.cancel()
            currentTask?.cancel()
        }
        statusMessage = "Stopping..."
    }

    private func run(with runMode: RunMode) {
        guard let configuration = try? makeConfiguration(runMode: runMode) else {
            errorMessage = validationMessage ?? "Unable to build the current configuration."
            return
        }

        cancelActiveTasks()
        let runID = UUID()
        activeRunID = runID
        isRunning = true
        errorMessage = nil
        statusMessage = runMode == .dryRun ? "Generating plan..." : "Sorting files..."
        selectedOperationID = nil
        operations = []
        summary = RunSummary()

        currentTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                if self.isCurrentRun(runID) {
                    self.currentTask = nil
                    self.currentPlanTask = nil
                    self.currentApplyTask = nil
                }
            }

            do {
                let planTask = Task.detached(priority: .userInitiated) {
                    try Self.buildPlan(configuration: configuration, shouldStop: { Task.isCancelled })
                }
                self.currentPlanTask = planTask
                let planResult = try await planTask.value
                guard self.isCurrentRun(runID) else {
                    return
                }
                self.currentPlanTask = nil

                self.operations = planResult.operations
                self.summary = planResult.summary
                self.statusMessage = "Plan generated."

                if runMode == .dryRun {
                    self.isRunning = false
                    return
                }

                let applyTask = Task.detached(priority: .userInitiated) {
                    Self.executePlan(
                        planResult.operations,
                        collisionPolicy: configuration.collisionPolicy,
                        shouldStop: { Task.isCancelled }
                    )
                }
                self.currentApplyTask = applyTask
                let applyResult = await applyTask.value
                guard self.isCurrentRun(runID) else {
                    return
                }
                self.currentApplyTask = nil

                self.operations = applyResult.operations
                self.summary = applyResult.summary
                self.isRunning = false
                self.statusMessage = applyResult.summary.cancelled ? "Stopped." : "Completed."
            } catch TypeNestError.cancelled {
                guard self.isCurrentRun(runID) else {
                    return
                }
                self.isRunning = false
                self.statusMessage = "Stopped."
            } catch {
                guard self.isCurrentRun(runID) else {
                    return
                }
                self.isRunning = false
                self.statusMessage = "Error."
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func matchesFilter(_ operation: Operation) -> Bool {
        switch resultFilter {
        case .all:
            return true
        case .planned:
            return operation.action != .ignore && operation.status == .planned
        case .skipped:
            return operation.status == .skipped || operation.action == .ignore
        case .errors:
            return operation.status == .error || operation.error != nil
        }
    }

    private func makeConfiguration(runMode: RunMode) throws -> SortConfiguration {
        if let validationMessage {
            throw NSError(domain: "TypeNest", code: 1, userInfo: [NSLocalizedDescriptionKey: validationMessage])
        }

        guard let rootFolderURL else {
            throw TypeNestError.invalidRoot("")
        }

        return SortConfiguration(
            rootURL: rootFolderURL,
            preset: preset,
            runMode: runMode,
            collisionPolicy: collisionPolicy,
            recursive: recursive,
            destinationMode: destinationMode,
            aggregateDirectory: aggregateDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "_sorted" : aggregateDirectory,
            rawExtensions: splitExtensionList(rawExtensionsText),
            mergeJpgAndJpeg: mergeJpgAndJpeg,
            customExtensions: splitExtensionList(customExtensionsText)
        )
    }

    private func restorePreferences() {
        isRestoring = true
        let defaults = UserDefaults.standard

        rootFolderPath = defaults.string(forKey: Keys.rootFolderPath) ?? ""
        preset = PresetKind(rawValue: defaults.string(forKey: Keys.preset) ?? "") ?? .rawJpegCleanup
        executionMode = RunMode(rawValue: defaults.string(forKey: Keys.executionMode) ?? "") == .copy ? .copy : .move
        collisionPolicy = CollisionPolicy(rawValue: defaults.string(forKey: Keys.collisionPolicy) ?? "") ?? .skip
        recursive = defaults.object(forKey: Keys.recursive) as? Bool ?? true
        destinationMode = DestinationMode(rawValue: defaults.string(forKey: Keys.destinationMode) ?? "") ?? .subfolder
        aggregateDirectory = defaults.string(forKey: Keys.aggregateDirectory) ?? "_sorted"
        rawExtensionsText = defaults.string(forKey: Keys.rawExtensionsText) ?? "raw,arw"
        mergeJpgAndJpeg = defaults.object(forKey: Keys.mergeJpgAndJpeg) as? Bool ?? true
        customExtensionsText = defaults.string(forKey: Keys.customExtensionsText) ?? "json,text"

        isRestoring = false
    }

    private func persistPreferences() {
        guard !isRestoring else {
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(rootFolderPath, forKey: Keys.rootFolderPath)
        defaults.set(preset.rawValue, forKey: Keys.preset)
        defaults.set(executionMode.rawValue, forKey: Keys.executionMode)
        defaults.set(collisionPolicy.rawValue, forKey: Keys.collisionPolicy)
        defaults.set(recursive, forKey: Keys.recursive)
        defaults.set(destinationMode.rawValue, forKey: Keys.destinationMode)
        defaults.set(aggregateDirectory, forKey: Keys.aggregateDirectory)
        defaults.set(rawExtensionsText, forKey: Keys.rawExtensionsText)
        defaults.set(mergeJpgAndJpeg, forKey: Keys.mergeJpgAndJpeg)
        defaults.set(customExtensionsText, forKey: Keys.customExtensionsText)
    }

    private func cancelActiveTasks() {
        currentTask?.cancel()
        currentPlanTask?.cancel()
        currentApplyTask?.cancel()
        currentTask = nil
        currentPlanTask = nil
        currentApplyTask = nil
    }

    private func isCurrentRun(_ runID: UUID) -> Bool {
        activeRunID == runID
    }

    nonisolated private static func buildPlan(
        configuration: SortConfiguration,
        shouldStop: @escaping @Sendable () -> Bool
    ) throws -> PlanResult {
        let ruleSet = try ruleSet(for: configuration)
        let options = PlannerOptions(
            rootURL: configuration.rootURL,
            recursive: configuration.recursive,
            excludeDirectories: configuration.excludeDirectories,
            runMode: configuration.runMode,
            collisionPolicy: configuration.collisionPolicy
        )
        return try createPlan(options: options, ruleSet: ruleSet, shouldStop: shouldStop)
    }

    nonisolated private static func executePlan(
        _ operations: [Operation],
        collisionPolicy: CollisionPolicy,
        shouldStop: @escaping @Sendable () -> Bool
    ) -> ApplyResult {
        apply(
            operations: operations,
            collisionPolicy: collisionPolicy,
            shouldStop: shouldStop
        )
    }

    nonisolated private static func ruleSet(for configuration: SortConfiguration) throws -> RuleSet {
        switch configuration.preset {
        case .rawJpegCleanup:
            return try rawJpegCleanupPreset(
                rawExtensions: configuration.rawExtensions,
                mergeJpgAndJpeg: configuration.mergeJpgAndJpeg,
                destinationMode: configuration.destinationMode,
                aggregateRoot: configuration.aggregateDirectory
            )
        case .customExtensions:
            return try customExtensionsPreset(
                extensions: configuration.customExtensions,
                mergeJpgAndJpeg: configuration.mergeJpgAndJpeg,
                destinationMode: configuration.destinationMode,
                aggregateRoot: configuration.aggregateDirectory
            )
        }
    }

    private struct SortConfiguration: Sendable {
        var rootURL: URL
        var preset: PresetKind
        var runMode: RunMode
        var collisionPolicy: CollisionPolicy
        var recursive: Bool
        var destinationMode: DestinationMode
        var aggregateDirectory: String
        var rawExtensions: [String]
        var mergeJpgAndJpeg: Bool
        var customExtensions: [String]

        var excludeDirectories: Set<String> {
            []
        }
    }

    private enum Keys {
        static let rootFolderPath = "rootFolderPath"
        static let preset = "preset"
        static let executionMode = "executionMode"
        static let collisionPolicy = "collisionPolicy"
        static let recursive = "recursive"
        static let destinationMode = "destinationMode"
        static let aggregateDirectory = "aggregateDirectory"
        static let rawExtensionsText = "rawExtensionsText"
        static let mergeJpgAndJpeg = "mergeJpgAndJpeg"
        static let customExtensionsText = "customExtensionsText"
    }
}
