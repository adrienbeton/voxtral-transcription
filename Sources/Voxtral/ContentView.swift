import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import VoxtralCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var showImporter = false

    static let audioTypes: [UTType] = [.mp3, .wav, .aiff, .mpeg4Audio, UTType("org.xiph.flac") ?? .audio, .audio]

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selection, searchText: searchText)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Rechercher")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let t = appState.selection {
                TranscriptionDetailView(transcription: t)
            } else {
                ContentUnavailableView("Aucune transcription",
                                       systemImage: "waveform",
                                       description: Text("Glisse un fichier audio ici ou clique sur Ouvrir."))
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ouvrir", systemImage: "plus") { showImporter = true }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.audioTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                appState.importFiles(urls, context: context)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter { url in
                UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
            }
            guard !audio.isEmpty else { return false }
            appState.importFiles(audio, context: context)
            return true
        }
    }
}
