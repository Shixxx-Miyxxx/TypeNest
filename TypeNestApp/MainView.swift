import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var showOverwriteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerCard
            settingsCard
            summaryRow
            contentSplit
            footer
        }
        .padding(20)
        .frame(minWidth: 1120, minHeight: 760)
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Overwrite existing files?",
            isPresented: $showOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                model.runNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This may replace existing files in the destination folders.")
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TypeNest")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Native macOS file sorting preview and execution.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose Folder…") {
                        model.chooseFolder()
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                    Button("Clear") {
                        model.clearRootFolder()
                    }
                    .disabled(model.rootFolderURL == nil || model.isRunning)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target Folder")
                        .font(.headline)
                    Text(model.rootFolderPath.isEmpty ? "No folder selected." : model.rootFolderPath)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(model.rootFolderPath.isEmpty ? .secondary : .primary)
                }
            }
        }
    }

    private var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preset")
                            .font(.headline)
                        Picker("Preset", selection: $model.preset) {
                            Text("RAW + JPEG").tag(PresetKind.rawJpegCleanup)
                            Text("Custom Extensions").tag(PresetKind.customExtensions)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Execution")
                            .font(.headline)
                        Picker("Execution", selection: $model.executionMode) {
                            Text("Move").tag(RunMode.move)
                            Text("Copy").tag(RunMode.copy)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collision")
                            .font(.headline)
                        Picker("Collision", selection: $model.collisionPolicy) {
                            Text("Skip").tag(CollisionPolicy.skip)
                            Text("Rename").tag(CollisionPolicy.rename)
                            Text("Overwrite").tag(CollisionPolicy.overwrite)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Toggle("Recursive", isOn: $model.recursive)
                        EmptyView()
                    }
                    GridRow {
                        Text("Destination Mode")
                            .foregroundStyle(.secondary)
                        Picker("Destination Mode", selection: $model.destinationMode) {
                            Text("Subfolder").tag(DestinationMode.subfolder)
                            Text("Aggregate").tag(DestinationMode.aggregate)
                        }
                        .pickerStyle(.menu)
                    }
                    GridRow {
                        Text("Aggregate Folder")
                            .foregroundStyle(.secondary)
                        TextField("_sorted", text: $model.aggregateDirectory)
                    }
                    GridRow {
                        Text("Merge jpg/jpeg")
                            .foregroundStyle(.secondary)
                        Toggle("Enabled", isOn: $model.mergeJpgAndJpeg)
                            .labelsHidden()
                    }
                    if model.preset == .rawJpegCleanup {
                        GridRow {
                            Text("RAW Extensions")
                                .foregroundStyle(.secondary)
                            TextField("raw, arw", text: $model.rawExtensionsText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    if model.preset == .customExtensions {
                        GridRow {
                            Text("Custom Extensions")
                                .foregroundStyle(.secondary)
                            TextField("json, text, png", text: $model.customExtensionsText)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if let validationMessage = model.validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            summaryTile(title: "Scanned", value: model.summary.scannedFiles, tint: .blue)
            summaryTile(title: "Planned", value: model.summary.plannedOperations, tint: .indigo)
            summaryTile(title: "Executed", value: model.summary.executed, tint: .green)
            summaryTile(title: "Skipped", value: model.summary.skipped, tint: .orange)
            summaryTile(title: "Errors", value: model.summary.errors, tint: .red)
        }
    }

    private func summaryTile(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private var contentSplit: some View {
        HSplitView {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Filter", selection: $model.resultFilter) {
                            Text("All").tag(AppModel.ResultFilter.all)
                            Text("Planned").tag(AppModel.ResultFilter.planned)
                            Text("Skipped").tag(AppModel.ResultFilter.skipped)
                            Text("Errors").tag(AppModel.ResultFilter.errors)
                        }
                        .pickerStyle(.segmented)
                        TextField("Search paths or reasons", text: $model.searchText)
                            .textFieldStyle(.roundedBorder)
                    }

                    Table(model.filteredOperations, selection: $model.selectedOperationID) {
                        TableColumn("Status") { operation in
                            Text(operation.statusText)
                        }
                        TableColumn("Action") { operation in
                            Text(operation.actionText)
                        }
                        TableColumn("Source") { operation in
                            Text(operation.sourcePathValue)
                        }
                        TableColumn("Destination") { operation in
                            Text(operation.destinationPathValue)
                        }
                    }
                }
            }
            .frame(minWidth: 760)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Details")
                        .font(.headline)
                    if let operation = model.selectedOperation {
                        detailRow(title: "Status", value: operation.status.rawValue)
                        detailRow(title: "Action", value: operation.action.rawValue)
                        detailRow(title: "Source", value: operation.sourceURL.path)
                        detailRow(title: "Destination", value: operation.destinationURL?.path ?? "-")
                        detailRow(title: "Reason", value: operation.reason)
                        if let error = operation.error, !error.isEmpty {
                            detailRow(title: "Error", value: error)
                        }
                    } else {
                        Text("Select a row to inspect the planned destination and reason.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 280)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isRunning {
                Button("Stop") {
                    model.stopCurrentTask()
                }
            }
            Button("Preview Plan") {
                model.previewPlan()
            }
            .disabled(!model.canPreview)
            Button("Run") {
                if model.requiresOverwriteConfirmation {
                    showOverwriteConfirmation = true
                } else {
                    model.runNow()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)
        }
    }
}

private extension Operation {
    var statusText: String {
        status.rawValue
    }

    var actionText: String {
        action.rawValue
    }

    var sourcePathValue: String {
        sourceURL.path
    }

    var destinationPathValue: String {
        destinationURL?.path ?? ""
    }
}
