import Foundation
import SwiftData

public enum TranscriptionStatus: String, Codable, Sendable {
    case pending, done, failed
}

@Model
public final class Transcription {
    public var id: UUID = UUID()
    public var fileName: String = ""
    public var fileBookmark: Data = Data()
    public var createdAt: Date = Date()
    public var duration: TimeInterval = 0
    public var detectedLanguage: String?
    public var statusRaw: String = TranscriptionStatus.pending.rawValue
    public var errorMessage: String?
    public var fullText: String = ""
    public var speakerNames: [String: String] = [:]
    @Relationship(deleteRule: .cascade, inverse: \Segment.transcription)
    public var segments: [Segment] = []

    public var status: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var orderedSegments: [Segment] {
        segments.sorted { $0.order < $1.order }
    }

    /// Custom name if set, else "Speaker N" derived from "speaker_<n>" ids, else the raw id.
    public func displayName(for speaker: String) -> String {
        if let custom = speakerNames[speaker], !custom.isEmpty { return custom }
        if speaker.hasPrefix("speaker_"), let n = Int(speaker.dropFirst("speaker_".count)) {
            return "Speaker \(n + 1)"
        }
        return speaker
    }

    public init(fileName: String, fileBookmark: Data, duration: TimeInterval) {
        self.fileName = fileName
        self.fileBookmark = fileBookmark
        self.duration = duration
    }
}

@Model
public final class Segment {
    public var text: String = ""
    public var start: TimeInterval = 0
    public var end: TimeInterval = 0
    public var speaker: String = ""
    public var order: Int = 0
    public var transcription: Transcription?

    public init(text: String, start: TimeInterval, end: TimeInterval, speaker: String, order: Int) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
        self.order = order
    }
}
