import XCTest
@testable import YatseRemote

/// Guards the shell's navigation model and the two pure rules the shell relies
/// on — the touchpad gesture mapping and the mini-player visibility rule. These
/// are the parts of the shell that can be verified without a host; the SwiftUI
/// rendering itself cannot be seen in CI.
final class ShellNavigationTests: XCTestCase {

    // MARK: Drawer order and grouping

    func testDrawerListsEveryDestinationInOrder() {
        XCTAssertEqual(
            ShellDestination.allCases.map(\.title),
            ["Home", "Movies", "TV Shows", "Music", "Pvr", "Files", "Addons", "Remote", "Settings", "About / Help"]
        )
    }

    func testDrawerSplitsDestinationsFromSettingsAndAbout() {
        XCTAssertEqual(
            ShellDestination.destinations.map(\.title),
            ["Home", "Movies", "TV Shows", "Music", "Pvr", "Files", "Addons", "Remote"]
        )
        XCTAssertEqual(ShellDestination.secondary, [.settings, .about])
    }

    // MARK: Shortcut strip

    func testShortcutStripOrder() {
        XCTAssertEqual(
            RemoteShortcut.allCases.map(\.title),
            ["Home", "Movies", "TV Shows", "Music", "Pictures"]
        )
    }

    func testShortcutDestinationsAreImplemented() {
        for shortcut in RemoteShortcut.allCases {
            if let destination = shortcut.destination {
                XCTAssertTrue(destination.isImplemented, "\(shortcut.title) → \(destination.title) is not implemented")
            }
        }
        // Pictures is a Kodi window command, not a shell destination.
        XCTAssertNil(RemoteShortcut.pictures.destination)
    }

    // MARK: Destination mapping

    func testLibraryDestinationsMapToSections() {
        XCTAssertEqual(ShellDestination.movies.librarySection, .movies)
        XCTAssertEqual(ShellDestination.tvShows.librarySection, .tvshows)
        XCTAssertEqual(ShellDestination.music.librarySection, .artists)
        XCTAssertNil(ShellDestination.home.librarySection)
    }

    func testUnimplementedDestinationsAreFlagged() {
        XCTAssertFalse(ShellDestination.pvr.isImplemented)
        XCTAssertFalse(ShellDestination.files.isImplemented)
        XCTAssertFalse(ShellDestination.addons.isImplemented)
        XCTAssertTrue(ShellDestination.remote.isImplemented)
        XCTAssertTrue(ShellDestination.settings.isImplemented)
    }

    // MARK: Touchpad resolver

    func testTouchpadHorizontalSwipe() {
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: 120, height: 10)), .right)
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: -120, height: 10)), .left)
    }

    func testTouchpadVerticalSwipe() {
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: 8, height: 120)), .down)
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: 8, height: -120)), .up)
    }

    func testTouchpadDominantAxisWins() {
        // A mostly-horizontal drag resolves horizontally even with some vertical.
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: 80, height: 40)), .right)
        XCTAssertEqual(TouchpadGestureResolver.key(forTranslation: CGSize(width: 40, height: 80)), .down)
    }

    func testTouchpadSubThresholdIsNil() {
        XCTAssertNil(TouchpadGestureResolver.key(forTranslation: CGSize(width: 5, height: 5)))
        XCTAssertNil(TouchpadGestureResolver.key(forTranslation: CGSize(width: -10, height: 10)))
    }

    // MARK: Mini-player visibility

    func testMiniPlayerHiddenWithNoPlayer() {
        XCTAssertFalse(MiniPlayer.isVisible(activePlayer: nil))
    }

    func testMiniPlayerShownWithAPlayer() {
        XCTAssertTrue(MiniPlayer.isVisible(activePlayer: ActivePlayer(playerid: 0, type: "audio")))
        XCTAssertTrue(MiniPlayer.isVisible(activePlayer: ActivePlayer(playerid: 1, type: "video")))
    }

    // MARK: Volume clamp

    func testVolumeClamp() {
        XCTAssertEqual(AppModel.clampedVolume(-20), 0)
        XCTAssertEqual(AppModel.clampedVolume(0), 0)
        XCTAssertEqual(AppModel.clampedVolume(42), 42)
        XCTAssertEqual(AppModel.clampedVolume(100), 100)
        XCTAssertEqual(AppModel.clampedVolume(150), 100)
    }
}
