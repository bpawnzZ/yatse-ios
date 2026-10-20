import XCTest
@testable import YatseRemote

/// What `play(item:)` does before it sends `Player.Open`. Pure, so the rule is
/// checked here rather than needing a Kodi box on the CI runner.
final class PlaybackReplacementTests: XCTestCase {
    private func player(_ id: Int, _ type: String) -> ActivePlayer {
        ActivePlayer(playerid: id, type: type)
    }

    func testAnIdleBoxOpensAtOnce() {
        XCTAssertEqual(AppModel.replacement(for: []), .immediate)
    }

    func testAPlayingVideoIsStoppedFirst() {
        XCTAssertEqual(
            AppModel.replacement(for: [player(1, "video")]),
            .stopThenOpen(playerid: 1))
    }

    func testMusicIsNotStopped() {
        // A video takes the player from music without the failure this fixes, so
        // the 1.5 s wait must not be paid there.
        XCTAssertEqual(AppModel.replacement(for: [player(0, "audio")]), .immediate)
        XCTAssertEqual(
            AppModel.replacement(for: [player(0, "audio"), player(2, "video")]),
            .stopThenOpen(playerid: 2))
    }

    func testTheWaitIsWhatTheDesktopUses() {
        XCTAssertEqual(AppModel.replacePause, .milliseconds(1500))
    }
}
