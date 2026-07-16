import SwiftUI
import VoxtralCore

struct SettingsView: View {
    @State private var apiKey: String = KeychainStore.apiKey() ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            SecureField("Clé API Mistral", text: $apiKey)
                .onChange(of: apiKey) { saved = false }
            HStack {
                Button("Enregistrer") {
                    try? KeychainStore.setAPIKey(apiKey)
                    saved = true
                }
                if saved {
                    Label("Enregistrée dans le trousseau", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Link("Obtenir une clé sur console.mistral.ai",
                 destination: URL(string: "https://console.mistral.ai")!)
        }
        .padding(20)
        .frame(width: 420)
    }
}
