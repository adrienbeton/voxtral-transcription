import SwiftUI
import SwiftData
import AppKit
import VoxtralCore

struct TranscriptionDetailView: View {
    let transcription: Transcription
    @Environment(\.modelContext) private var context
    @State private var player = PlayerController()
    @State private var audioAvailable = true

    @State private var findQuery = ""
    @State private var showFind = false
    @State private var findCursor = 0
    @State private var scrollTarget: Int?
    @FocusState private var findFocused: Bool

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

    var matchIndices: [Int] {
        guard !findQuery.isEmpty else { return [] }
        let q = findQuery.localizedLowercase
        return transcription.orderedSegments.enumerated()
            .filter { $0.element.text.localizedLowercase.contains(q) }
            .map(\.offset)
    }

    func advanceFind(_ delta: Int) {
        guard !matchIndices.isEmpty else { return }
        findCursor = ((findCursor + delta) % matchIndices.count + matchIndices.count) % matchIndices.count
        let idx = matchIndices[findCursor]
        scrollTarget = idx
        if audioAvailable { player.seek(to: transcription.orderedSegments[idx].start) }
    }

    func export(ext: String, content: String) {
        let panel = NSSavePanel()
        let base = (transcription.fileName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Copier", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ExportFormatter.plainText(transcription), forType: .string)
                }
                .disabled(transcription.status != .done)
                Menu {
                    Button("Texte brut (.txt)") { export(ext: "txt", content: ExportFormatter.plainText(transcription)) }
                    Button("Markdown (.md)") { export(ext: "md", content: ExportFormatter.markdown(transcription)) }
                } label: {
                    Label("Exporter…", systemImage: "square.and.arrow.up")
                }
                .disabled(transcription.status != .done)
            }
        }
    }

    var transcriptBody: some View {
        VStack(spacing: 0) {
            if showFind {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Rechercher dans le transcript", text: $findQuery)
                        .textFieldStyle(.plain)
                        .focused($findFocused)
                        .onSubmit { advanceFind(1) }
                    if !matchIndices.isEmpty {
                        Text("\(findCursor + 1)/\(matchIndices.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(action: { advanceFind(-1) }) { Image(systemName: "chevron.up") }
                        .disabled(matchIndices.isEmpty)
                    Button(action: { advanceFind(1) }) { Image(systemName: "chevron.down") }
                        .disabled(matchIndices.isEmpty)
                    Button(action: { showFind = false; findQuery = "" }) { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
                .padding(8)
                .background(.bar)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(transcription.orderedSegments.enumerated()), id: \.offset) { i, segment in
                            SegmentRow(
                                segment: segment,
                                name: transcription.displayName(for: segment.speaker),
                                color: color(for: segment.speaker),
                                isCurrent: i == currentSegmentIndex,
                                highlight: findQuery,
                                isFindMatch: matchIndices.contains(i),
                                onRename: { newName in
                                    transcription.speakerNames[segment.speaker] = newName
                                    try? context.save()
                                }
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
                .onChange(of: scrollTarget) { _, target in
                    if let target {
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                        scrollTarget = nil
                    }
                }
                .onChange(of: findQuery) { findCursor = 0 }
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
        .background {
            Button("") { showFind = true; findFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
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
    let highlight: String
    let isFindMatch: Bool
    let onRename: (String) -> Void

    @State private var showRename = false
    @State private var draft = ""

    var highlightedText: AttributedString {
        var attr = AttributedString(segment.text)
        guard !highlight.isEmpty else { return attr }
        let lowerText = segment.text.lowercased()
        let lowerQuery = highlight.lowercased()
        var searchRange = lowerText.startIndex..<lowerText.endIndex
        while let r = lowerText.range(of: lowerQuery, range: searchRange) {
            let lower = lowerText.distance(from: lowerText.startIndex, to: r.lowerBound)
            let length = lowerText.distance(from: r.lowerBound, to: r.upperBound)
            let attrStart = attr.index(attr.startIndex, offsetByCharacters: lower)
            let attrEnd = attr.index(attrStart, offsetByCharacters: length)
            attr[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.5)
            searchRange = r.upperBound..<lowerText.endIndex
        }
        return attr
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button(name) { draft = name; showRename = true }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                        .foregroundStyle(color)
                        .popover(isPresented: $showRename) {
                            Form {
                                TextField("Nom du speaker", text: $draft)
                                    .frame(width: 200)
                                    .onSubmit { onRename(draft); showRename = false }
                                Button("Renommer") { onRename(draft); showRename = false }
                            }
                            .padding(12)
                        }
                    Text(ExportFormatter.timestamp(segment.start))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(highlightedText)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(isFindMatch ? Color.yellow.opacity(0.8) : .clear, lineWidth: 1))
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
