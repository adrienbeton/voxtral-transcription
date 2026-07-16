import SwiftUI
import SwiftData
import VoxtralCore

struct SidebarView: View {
    @Binding var selection: Transcription?
    let searchText: String
    @Environment(\.modelContext) private var context
    @Query(sort: \Transcription.createdAt, order: .reverse) private var transcriptions: [Transcription]

    var filtered: [Transcription] {
        guard !searchText.isEmpty else { return transcriptions }
        let q = searchText.localizedLowercase
        return transcriptions.filter {
            $0.fileName.localizedLowercase.contains(q) || $0.fullText.localizedLowercase.contains(q)
        }
    }

    var body: some View {
        List(filtered, id: \.persistentModelID, selection: $selection) { t in
            NavigationLink(value: t) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        statusIcon(t.status)
                        Text(t.fileName).fontWeight(.medium).lineLimit(1)
                    }
                    Text("\(t.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ExportFormatter.timestamp(t.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tag(t)
            .contextMenu {
                Button("Retranscrire") {
                    let service = TranscriptionService(context: context)
                    Task { await service.retry(t) }
                }
                Button("Supprimer", role: .destructive) {
                    if selection == t { selection = nil }
                    context.delete(t)
                    try? context.save()
                }
            }
        }
    }

    @ViewBuilder
    func statusIcon(_ status: TranscriptionStatus) -> some View {
        switch status {
        case .pending: ProgressView().controlSize(.small)
        case .done: EmptyView()
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }
}
