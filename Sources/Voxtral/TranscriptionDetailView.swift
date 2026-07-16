import SwiftUI
import SwiftData
import VoxtralCore

struct TranscriptionDetailView: View {
    let transcription: Transcription
    @State private var player = PlayerController()
    @State private var audioAvailable = true

    static let speakerColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]

    var speakers: [String] {
        Array(Set(transcription.orderedSegments.map(\.speaker))).sorted()
    }

    func color(for speaker: String) -> Color {
        let i = speakers.firstIndex(of: speaker) ?? 0
        return Self.speakerColors[i % Self.speakerColors.count]
    }

    var currentSegmentIndex: Int? {
        let ranges = transcription.orderedSegments.map { (start: $0.start, end: $0.end) }
        return SegmentLocator.index(at: player.currentTime, in: ranges)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch transcription.status {
            case .pending:
                Spacer()
                ProgressView("Transcription en cours…")
                Spacer()
            case .failed:
                FailedView(transcription: transcription)
            case .done:
                transcriptBody
            }
        }
        .navigationTitle(transcription.fileName)
        .onAppear { loadAudio() }
        .onChange(of: transcription.persistentModelID) { loadAudio() }
        .onDisappear { player.unload() }
    }

    var transcriptBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(transcription.orderedSegments.enumerated()), id: \.offset) { i, segment in
                            SegmentRow(
                                segment: segment,
                                name: transcription.displayName(for: segment.speaker),
                                color: color(for: segment.speaker),
                                isCurrent: i == currentSegmentIndex
                            )
                            .id(i)
                            .onTapGesture {
                                if audioAvailable { player.seek(to: segment.start) }
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: currentSegmentIndex) { _, newIndex in
                    if let newIndex, player.isPlaying {
                        withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                }
            }
            Divider()
            if audioAvailable {
                PlayerBarView(player: player)
            } else {
                Label("Fichier audio introuvable — lecture désactivée", systemImage: "speaker.slash")
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }

    func loadAudio() {
        player.unload()
        if let url = transcription.resolvedFileURL() {
            audioAvailable = true
            player.load(url: url)
        } else {
            audioAvailable = false
        }
    }
}

struct SegmentRow: View {
    let segment: Segment
    let name: String
    let color: Color
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.caption.bold()).foregroundStyle(color)
                    Text(ExportFormatter.timestamp(segment.start))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(segment.text)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

struct FailedView: View {
    let transcription: Transcription
    @Environment(\.modelContext) private var context

    var body: some View {
        Spacer()
        ContentUnavailableView {
            Label("Échec de la transcription", systemImage: "exclamationmark.triangle")
        } description: {
            Text(transcription.errorMessage ?? "Erreur inconnue")
        } actions: {
            Button("Réessayer") {
                let service = TranscriptionService(context: context)
                Task { await service.retry(transcription) }
            }
            SettingsLink { Text("Réglages…") }
        }
        Spacer()
    }
}
