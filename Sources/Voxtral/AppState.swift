import SwiftUI
import SwiftData
import VoxtralCore

@MainActor
@Observable
final class AppState {
    var selection: Transcription?

    func importFiles(_ urls: [URL], context: ModelContext) {
        let service = TranscriptionService(context: context)
        for url in urls {
            Task {
                let t = await service.importFile(url)
                if selection == nil { selection = t }
            }
        }
    }
}
