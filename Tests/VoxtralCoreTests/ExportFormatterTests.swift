import XCTest
@testable import VoxtralCore

final class ExportFormatterTests: XCTestCase {
    @MainActor
    func makeTranscription() -> Transcription {
        let t = Transcription(fileName: "meeting.mp3", fileBookmark: Data(), duration: 4000)
        t.speakerNames["speaker_0"] = "Adrien"
        t.segments = [
            Segment(text: "Bonjour à tous.", start: 0, end: 2, speaker: "speaker_0", order: 0),
            Segment(text: "Salut.", start: 3661.5, end: 3663, speaker: "speaker_1", order: 1),
        ]
        return t
    }

    func testTimestamp() {
        XCTAssertEqual(ExportFormatter.timestamp(0), "00:00:00")
        XCTAssertEqual(ExportFormatter.timestamp(3661.5), "01:01:01")
    }

    @MainActor
    func testPlainText() {
        let out = ExportFormatter.plainText(makeTranscription())
        XCTAssertEqual(out, "[Adrien] Bonjour à tous.\n[Speaker 2] Salut.")
    }

    @MainActor
    func testMarkdown() {
        let out = ExportFormatter.markdown(makeTranscription())
        XCTAssertEqual(out, """
        # meeting.mp3

        **Adrien** [00:00:00] : Bonjour à tous.
        **Speaker 2** [01:01:01] : Salut.
        """)
    }
}
