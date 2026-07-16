import Foundation

public enum ExportFormatter {
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    @MainActor
    public static func plainText(_ t: Transcription) -> String {
        t.orderedSegments
            .map { "[\(t.displayName(for: $0.speaker))] \($0.text)" }
            .joined(separator: "\n")
    }

    @MainActor
    public static func markdown(_ t: Transcription) -> String {
        let lines = t.orderedSegments
            .map { "**\(t.displayName(for: $0.speaker))** [\(timestamp($0.start))] : \($0.text)" }
            .joined(separator: "\n")
        return "# \(t.fileName)\n\n\(lines)"
    }
}
