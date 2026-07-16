import XCTest
import SwiftData
@testable import VoxtralCore

final class ModelsTests: XCTestCase {
    @MainActor
    func testCreateAndFetchTranscription() throws {
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let t = Transcription(fileName: "meeting.mp3", fileBookmark: Data(), duration: 120)
        t.segments.append(Segment(text: "Hello", start: 0, end: 2.5, speaker: "speaker_0", order: 0))
        context.insert(t)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transcription>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].status, .pending)
        XCTAssertEqual(fetched[0].segments.count, 1)
    }

    @MainActor
    func testSpeakerDisplayName() {
        let t = Transcription(fileName: "a.mp3", fileBookmark: Data(), duration: 0)
        XCTAssertEqual(t.displayName(for: "speaker_0"), "Speaker 1")
        t.speakerNames["speaker_0"] = "Adrien"
        XCTAssertEqual(t.displayName(for: "speaker_0"), "Adrien")
        XCTAssertEqual(t.displayName(for: "weird_id"), "weird_id")
    }
}
