import XCTest
@testable import VoxtralCore

final class MistralClientTests: XCTestCase {
    func testDecodeResponseWithDiarization() throws {
        let json = """
        {"model":"voxtral-mini-2602","text":"Hello there. Hi.","language":"en",
         "segments":[
           {"text":"Hello there.","start":0.0,"end":1.8,"speaker_id":"speaker_0","type":"transcription_segment"},
           {"text":"Hi.","start":2.0,"end":2.6,"speaker_id":"speaker_1","type":"transcription_segment"}
         ]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(TranscriptionResult.self, from: json)
        XCTAssertEqual(r.text, "Hello there. Hi.")
        XCTAssertEqual(r.language, "en")
        XCTAssertEqual(r.segments?.count, 2)
        XCTAssertEqual(r.segments?[1].speaker, "speaker_1")
    }

    func testDecodeResponseWithoutSegments() throws {
        let json = #"{"text":"Hello.","language":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(TranscriptionResult.self, from: json)
        XCTAssertEqual(r.text, "Hello.")
        XCTAssertNil(r.segments)
    }

    func testMultipartBody() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).mp3")
        try Data([0x49, 0x44, 0x33]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let request = try MistralClient.makeRequest(fileURL: tmp, apiKey: "sk-test", boundary: "BOUNDARY")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=BOUNDARY")

        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nvoxtral-mini-2602"))
        XCTAssertTrue(body.contains("name=\"diarize\"\r\n\r\ntrue"))
        XCTAssertTrue(body.contains("name=\"timestamp_granularities\"\r\n\r\nsegment"))
        XCTAssertTrue(body.contains("filename=\"\(tmp.lastPathComponent)\""))
        XCTAssertTrue(body.hasSuffix("--BOUNDARY--\r\n"))
        XCTAssertFalse(body.contains("name=\"language\""))
    }
}
