import SwiftUI
import SwiftData
import VoxtralCore

@main
struct VoxtralApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Voxtral") {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: Transcription.self)

        Settings {
            SettingsView()
        }
    }
}
