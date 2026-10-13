import XCTest
@testable import YatseRemote

/// The seek track's position arithmetic. It is pure so it is checked here rather
/// than on a screen, which is the only way CI can see it at all.
final class SeekFractionTests: XCTestCase {
    func testMidwayThroughIsHalf() {
        XCTAssertEqual(SeekFraction.of(position: 120, duration: 240), 0.5)
    }

    func testTheEndsAreTheTrackEnds() {
        XCTAssertEqual(SeekFraction.of(position: 0, duration: 240), 0)
        XCTAssertEqual(SeekFraction.of(position: 240, duration: 240), 1)
    }

    func testPastTheEndStaysAtTheEnd() {
        XCTAssertEqual(SeekFraction.of(position: 300, duration: 240), 1)
    }

    func testBeforeTheStartStaysAtTheStart() {
        XCTAssertEqual(SeekFraction.of(position: -5, duration: 240), 0)
    }

    /// Nothing playing reports no duration, and a live stream reports none either:
    /// both must read as the start of the track rather than dividing by zero.
    func testNoDurationIsTheStart() {
        XCTAssertEqual(SeekFraction.of(position: 0, duration: 0), 0)
        XCTAssertEqual(SeekFraction.of(position: 30, duration: 0), 0)
    }
}
