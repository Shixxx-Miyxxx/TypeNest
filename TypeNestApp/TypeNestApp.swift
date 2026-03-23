import SwiftUI

@main
struct TypeNestApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("TypeNest") {
            MainView(model: model)
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
