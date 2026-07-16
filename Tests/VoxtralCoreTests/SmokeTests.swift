import XCTest
@testable import VoxtralCore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(VoxtralCore.version, "0.1.0") }
}
