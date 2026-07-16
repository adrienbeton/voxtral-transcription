import XCTest
import SwiftData
@testable import VoxtralCore

struct MockAPI: TranscriptionAPI {
    var result: Result<TranscriptionResult, Error>
    func transcribe(fileURL: URL, apiKey: String) async throws -> TranscriptionResult {
        try result.get()
    }
}

final class TranscriptionServiceTests: XCTestCase {
    // Keeps containers alive: mainContext doesn't retain it, and in-memory
    // stores are torn down when the container deallocates.
    var containers: [ModelContainer] = []

    @MainActor
    func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return container.mainContext
    }

    func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID()).mp3")
        try Data([0x49, 0x44, 0x33, 0x00]).write(to: url)
        return url
    }

    @MainActor
    func testImportSuccess() async throws {
        let context = try makeContext()
        let json = TranscriptionResult(
            text: "Bonjour. Salut.", language: "fr",
            segments: [
                .init(text: "Bonjour.", start: 0, end: 1, speaker: "speaker_0"),
                .init(text: "Salut.", start: 1.2, end: 2, speaker: "speaker_1"),
            ])
        let service = TranscriptionService(api: MockAPI(result: .success(json)), context: context,
                                           apiKeyProvider: { "sk-test" })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.fullText, "Bonjour. Salut.")
        XCTAssertEqual(t.detectedLanguage, "fr")
        XCTAssertEqual(t.orderedSegments.count, 2)
        XCTAssertEqual(t.orderedSegments[1].speaker, "speaker_1")
        XCTAssertNotNil(t.resolvedFileURL())
    }

    @MainActor
    func testImportAPIFailure() async throws {
        let context = try makeContext()
        let service = TranscriptionService(
            api: MockAPI(result: .failure(APIError.http(status: 401, body: "unauthorized"))),
            context: context, apiKeyProvider: { "sk-bad" })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .failed)
        XCTAssertNotNil(t.errorMessage)
    }

    @MainActor
    func testImportWithoutAPIKey() async throws {
        let context = try makeContext()
        let service = TranscriptionService(api: MockAPI(result: .failure(APIError.invalidResponse)),
                                           context: context, apiKeyProvider: { nil })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .failed)
        XCTAssertEqual(t.errorMessage, ServiceError.missingAPIKey.errorDescription)
    }

    @MainActor
    func testRetryAfterFailure() async throws {
        let context = try makeContext()
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let failing = TranscriptionService(
            api: MockAPI(result: .failure(APIError.invalidResponse)),
            context: context, apiKeyProvider: { "sk" })
        let t = await failing.importFile(url)
        XCTAssertEqual(t.status, .failed)

        let ok = TranscriptionResult(text: "Hello", language: "en",
                                     segments: [.init(text: "Hello", start: 0, end: 1, speaker: "speaker_0")])
        let succeeding = TranscriptionService(api: MockAPI(result: .success(ok)),
                                              context: context, apiKeyProvider: { "sk" })
        await succeeding.retry(t)
        XCTAssertEqual(t.status, .done)
        XCTAssertNil(t.errorMessage)
        XCTAssertEqual(t.orderedSegments.count, 1)
    }
}
