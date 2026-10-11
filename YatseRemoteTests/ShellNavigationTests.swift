import XCTest
import UIKit
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
        XCTAssertTrue(ShellDestination.files.isImplemented)
        XCTAssertTrue(ShellDestination.addons.isImplemented)
        XCTAssertTrue(ShellDestination.remote.isImplemented)
        XCTAssertTrue(ShellDestination.settings.isImplemented)
    }

    // MARK: Icons

    /// A mistyped SF Symbol name draws nothing while leaving the button
    /// tappable — exactly how the Movies shortcut broke (an invisible control
    /// that still navigated). Neither the compiler nor a view test can see it,
    /// but `UIImage(systemName:)` answers nil. Every symbol the drawer, the
    /// shortcut strip and the favourite rows can draw is checked here.
    func testEveryDestinationSymbolExists() {
        assertSymbolsExist(ShellDestination.allCases.map(\.systemImage))
    }

    func testEveryShortcutSymbolExists() {
        assertSymbolsExist(RemoteShortcut.allCases.map(\.systemImage))
    }

    func testEveryLibrarySectionSymbolExists() {
        assertSymbolsExist(LibrarySection.allCases.map(\.systemImage))
    }

    /// The row and the drawer must agree: they drifted once and only the row
    /// broke, so the mapping lives in one place now.
    func testShortcutsAndDrawerAgreeOnIconsAndTitles() {
        for shortcut in RemoteShortcut.allCases {
            guard let destination = shortcut.destination else { continue }
            XCTAssertEqual(shortcut.systemImage, destination.systemImage,
                           "\(shortcut.rawValue) uses a different icon than \(destination.rawValue)")
            XCTAssertEqual(shortcut.title, destination.title)
        }
    }

    private func assertSymbolsExist(_ names: [String],
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        let missing = names.filter { UIImage(systemName: $0) == nil }
        XCTAssertTrue(missing.isEmpty,
                      "SF Symbols that do not resolve on this SDK: \(missing.joined(separator: ", "))",
                      file: file, line: line)
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

    // MARK: Playback state resolution

    /// The stuck-bar bug: the bar's visibility is `activePlayer != nil`, so the
    /// model must resolve an empty player list to nil even when something was
    /// playing a moment ago. Falling back to the previous player here is what
    /// left the bar on screen over stale metadata.
    func testEmptyActivePlayerListClearsTheLastPlayer() {
        let previous = ActivePlayer(playerid: 0, type: "video")
        XCTAssertNil(AppModel.resolvedPlayer(answer: [], previous: previous))
        XCTAssertNil(AppModel.resolvedPlayer(answer: [], previous: nil))
    }

    /// A dropped request is not a stop: keep the last good value rather than
    /// blinking the bar out for one failed poll.
    func testFailedPollKeepsTheLastPlayer() {
        let previous = ActivePlayer(playerid: 0, type: "video")
        XCTAssertEqual(AppModel.resolvedPlayer(answer: nil, previous: previous), previous)
        XCTAssertNil(AppModel.resolvedPlayer(answer: nil, previous: nil))
    }

    func testVideoPlayerWinsOverAudio() {
        let audio = ActivePlayer(playerid: 0, type: "audio")
        let video = ActivePlayer(playerid: 1, type: "video")
        XCTAssertEqual(AppModel.resolvedPlayer(answer: [audio, video], previous: nil), video)
        XCTAssertEqual(AppModel.resolvedPlayer(answer: [audio], previous: nil), audio)
    }

    // MARK: Volume clamp

    func testVolumeClamp() {
        XCTAssertEqual(AppModel.clampedVolume(-20), 0)
        XCTAssertEqual(AppModel.clampedVolume(0), 0)
        XCTAssertEqual(AppModel.clampedVolume(42), 42)
        XCTAssertEqual(AppModel.clampedVolume(100), 100)
        XCTAssertEqual(AppModel.clampedVolume(150), 100)
    }

    // MARK: Control-pad sizing

    func testControlPadBoundedByHeightWhenHeightIsSmaller() {
        XCTAssertEqual(ControlPadMetrics.side(in: CGSize(width: 400, height: 300)), 300)
        XCTAssertEqual(ControlPadMetrics.side(in: CGSize(width: 400, height: 300), reserved: 56), 244)
    }

    func testControlPadBoundedByWidthWhenWidthIsSmaller() {
        XCTAssertEqual(ControlPadMetrics.side(in: CGSize(width: 320, height: 700), reserved: 56), 320)
    }

    func testControlPadNeverNegative() {
        XCTAssertEqual(ControlPadMetrics.side(in: CGSize(width: 400, height: 40), reserved: 56), 0)
        XCTAssertEqual(ControlPadMetrics.side(in: .zero, reserved: 56), 0)
    }

    // MARK: Now Playing mappings

    func testRepeatModeCyclesOffAllOne() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
        XCTAssertEqual(RepeatMode.from("nonsense"), .off)
    }

    func testSubtitleSelectionSendsOffNotIndex() {
        // "off" must be the string, never index 0 — index 0 is a real stream.
        XCTAssertEqual(SubtitleSelection.off.payloadValue as? String, "off")
        XCTAssertEqual(SubtitleSelection.stream(2).payloadValue as? Int, 2)
        XCTAssertNil(SubtitleSelection.stream(0).payloadValue as? String)
    }

    func testTimeTextFormatting() {
        XCTAssertEqual(TimeText.mmss(0), "0:00")
        XCTAssertEqual(TimeText.mmss(65), "1:05")
        XCTAssertEqual(TimeText.mmss(3661), "1:01:01")
        XCTAssertEqual(TimeText.mmss(-5), "0:00")
    }
}
