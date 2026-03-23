import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Sorting") {
                Toggle("Recursive", isOn: $model.recursive)
                Picker("Destination Mode", selection: $model.destinationMode) {
                    Text("Subfolder").tag(DestinationMode.subfolder)
                    Text("Aggregate").tag(DestinationMode.aggregate)
                }
                TextField("Aggregate Folder", text: $model.aggregateDirectory)
                Picker("Collision", selection: $model.collisionPolicy) {
                    Text("Skip").tag(CollisionPolicy.skip)
                    Text("Rename").tag(CollisionPolicy.rename)
                    Text("Overwrite").tag(CollisionPolicy.overwrite)
                }
            }

            Section("Preset Defaults") {
                Toggle("Merge jpg/jpeg", isOn: $model.mergeJpgAndJpeg)
                TextField("RAW Extensions", text: $model.rawExtensionsText)
                TextField("Custom Extensions", text: $model.customExtensionsText)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
