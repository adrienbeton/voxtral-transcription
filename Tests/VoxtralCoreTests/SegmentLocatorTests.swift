import XCTest
@testable import VoxtralCore

final class SegmentLocatorTests: XCTestCase {
    let segments: [(start: TimeInterval, end: TimeInterval)] = [(0, 2), (2.5, 5), (6, 9)]

    func testLocate() {
        XCTAssertEqual(SegmentLocator.index(at: 0, in: segments), 0)
        XCTAssertEqual(SegmentLocator.index(at: 1.9, in: segments), 0)
        XCTAssertEqual(SegmentLocator.index(at: 2.2, in: segments), 0) // gap: stick to previous
        XCTAssertEqual(SegmentLocator.index(at: 3, in: segments), 1)
        XCTAssertEqual(SegmentLocator.index(at: 100, in: segments), 2)
        XCTAssertNil(SegmentLocator.index(at: -1, in: segments))
        XCTAssertNil(SegmentLocator.index(at: 0, in: []))
    }
}
