import Foundation
import SwiftData
import AVFoundation

public enum ServiceError: LocalizedError {
    case missingAPIKey
    case missingFile
    case audioTooLong

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Clé API Mistral manquante — ajoute-la dans les Réglages."
        case .missingFile: return "Fichier audio introuvable."
        case .audioTooLong: return "Fichier trop long : l'API supporte 3 h d'audio maximum."
        }
    }
}

extension Transcription {
    /// Resolves the stored bookmark; returns nil if the file is gone.
    public func resolvedFileURL() -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: fileBookmark, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { fileBookmark = fresh }
        return url
    }
}

@MainActor
public final class TranscriptionService {
    let api: TranscriptionAPI
    let context: ModelContext
    let apiKeyProvider: () -> String?

    static let maxDuration: TimeInterval = 3 * 3600

    public init(api: TranscriptionAPI = MistralClient(),
                context: ModelContext,
                apiKeyProvider: @escaping () -> String? = { KeychainStore.apiKey() }) {
        self.api = api
        self.context = context
        self.apiKeyProvider = apiKeyProvider
    }

    @discardableResult
    public func importFile(_ url: URL) async -> Transcription {
        let bookmark = (try? url.bookmarkData()) ?? Data()
        let duration = await loadDuration(url)
        let t = Transcription(fileName: url.lastPathComponent, fileBookmark: bookmark, duration: duration)
        context.insert(t)
        try? context.save()
        if duration > Self.maxDuration {
            t.status = .failed
            t.errorMessage = ServiceError.audioTooLong.errorDescription
            try? context.save()
            return t
        }
        await run(t, fileURL: url)
        return t
    }

    public func retry(_ t: Transcription) async {
        guard let url = t.resolvedFileURL() else {
            t.status = .failed
            t.errorMessage = ServiceError.missingFile.errorDescription
            try? context.save()
            return
        }
        if t.duration > Self.maxDuration {
            t.status = .failed
            t.errorMessage = ServiceError.audioTooLong.errorDescription
            try? context.save()
            return
        }
        await run(t, fileURL: url)
    }

    func run(_ t: Transcription, fileURL: URL) async {
        t.status = .pending
        t.errorMessage = nil
        try? context.save()

        guard let key = apiKeyProvider(), !key.isEmpty else {
            t.status = .failed
            t.errorMessage = ServiceError.missingAPIKey.errorDescription
            try? context.save()
            return
        }
        do {
            let result = try await api.transcribe(fileURL: fileURL, apiKey: key)
            for old in t.segments { context.delete(old) }
            t.segments = []
            for (i, s) in (result.segments ?? []).enumerated() {
                t.segments.append(Segment(text: s.text, start: s.start, end: s.end,
                                          speaker: s.speaker ?? "speaker_0", order: i))
            }
            t.fullText = result.text
            t.detectedLanguage = result.language
            t.status = .done
        } catch {
            t.status = .failed
            t.errorMessage = error.localizedDescription
        }
        try? context.save()
    }

    func loadDuration(_ url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
