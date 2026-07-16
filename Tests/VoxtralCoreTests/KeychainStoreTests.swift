import XCTest
@testable import VoxtralCore

final class KeychainStoreTests: XCTestCase {
    let service = "voxtral-transcription-tests"

    override func tearDown() { KeychainStore.deleteAPIKey(service: service) }

    func testRoundTrip() throws {
        XCTAssertNil(KeychainStore.apiKey(service: service))
        try KeychainStore.setAPIKey("sk-abc", service: service)
        XCTAssertEqual(KeychainStore.apiKey(service: service), "sk-abc")
        try KeychainStore.setAPIKey("sk-updated", service: service)
        XCTAssertEqual(KeychainStore.apiKey(service: service), "sk-updated")
        KeychainStore.deleteAPIKey(service: service)
        XCTAssertNil(KeychainStore.apiKey(service: service))
    }
}
