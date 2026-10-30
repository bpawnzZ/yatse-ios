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
            ["Home", "Movies", "TV Shows", "Music", "Pvr", "Files", "Addons", "Favorites", "Remote", "Settings", "About / Help"]
        )
    }

    func testDrawerSplitsDestinationsFromSettingsAndAbout() {
        XCTAssertEqual(
            ShellDestination.destinations.map(\.title),
            ["Home", "Movies", "TV Shows", "Music", "Pvr", "Files", "Addons", "Favorites", "Remote"]
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
        // Home and Pictures drive the host instead of switching this app's screen:
        // Picture opens a window on it, Home sends it to its own home screen.
        // `RemoteScreen.activate` handles both by name.
        XCTAssertNil(RemoteShortcut.home.destination)
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
        XCTAssertTrue(ShellDestination.favorites.isImplemented)
        XCTAssertTrue(ShellDestination.remote.isImplemented)
        XCTAssertTrue(ShellDestination.settings.isImplemented)
    }

    // MARK: Destination navigation memory

    private func place(_ title: String, _ path: String) -> Favorite {
        Favorite(title: title, target: .directory(path: path))
    }

    func testUnvisitedDestinationHasNothingPushed() {
        XCTAssertTrue(NavigationMemory().path(for: .addons).isEmpty)
    }

    func testRecordedPlaceIsRestoredForItsOwnDestination() {
        var memory = NavigationMemory()
        let saved = place("Subscriptions", "plugin://plugin.video.youtube/special/my_subscriptions")
        memory.record([saved], for: .addons)
        XCTAssertEqual(memory.path(for: .addons), [saved])
    }

    func testRecordingOneDestinationLeavesAnotherAlone() {
        var memory = NavigationMemory()
        let addons = place("Subscriptions", "plugin://plugin.video.youtube/special/x")
        let files = place("Films", "smb://nas/films/")
        memory.record([addons], for: .addons)
        memory.record([files], for: .files)
        XCTAssertEqual(memory.path(for: .addons), [addons])
        XCTAssertEqual(memory.path(for: .files), [files])
    }

    /// A destination left at its root remembers nothing, so returning to it lands
    /// on the root rather than reopening a place that was already closed.
    func testDestinationLeftAtItsRootRemembersNothing() {
        var memory = NavigationMemory()
        memory.record([place("Subscriptions", "plugin://x/")], for: .addons)
        memory.record([], for: .addons)
        XCTAssertTrue(memory.path(for: .addons).isEmpty)
    }

    /// Opening a favourite becomes that destination's place, which is what makes
    /// leaving and coming back land where the user last was.
    func testOpeningAFavouriteRecordsItAsThePlace() {
        var memory = NavigationMemory()
        let favourite = Favorite(title: "My Subscriptions",
                                 target: .directory(path: "plugin://plugin.video.youtube/special/x"))
        memory.record([favourite], for: .favorites)
        XCTAssertEqual(memory.path(for: .favorites), [favourite])
    }

    /// The point of the memory is the *deepest* screen, not the first one: coming
    /// back must land on the screen that was left, several pushes down.
    func testADeepPathIsRestoredWholeAndInOrder() {
        var memory = NavigationMemory()
        let addon = place("YouTube", "plugin://plugin.video.youtube/")
        let subscriptions = place("Subscriptions", "plugin://plugin.video.youtube/special/subs")
        let playlist = place("Watch later", "plugin://plugin.video.youtube/special/subs/later")

        memory.record([addon, subscriptions, playlist], for: .addons)

        XCTAssertEqual(memory.path(for: .addons), [addon, subscriptions, playlist])
        XCTAssertEqual(memory.path(for: .addons).last?.title, "Watch later")
    }

    /// Every destination keeps its own place independently — including the video
    /// sections and Favorites, which reach the stack through a different control
    /// than the add-ons browser does.
    func testEachDestinationKeepsItsOwnPlace() {
        var memory = NavigationMemory()
        let show = Favorite(title: "The Wire", target: .episodes(tvshowID: 12))
        let artist = Favorite(title: "Portishead", target: .albumsOfArtist(artistID: 7))
        let favourite = place("My Subscriptions", "plugin://plugin.video.youtube/special/x")

        memory.record([show], for: .tvShows)
        memory.record([artist], for: .music)
        memory.record([favourite], for: .favorites)

        XCTAssertEqual(memory.path(for: .tvShows), [show])
        XCTAssertEqual(memory.path(for: .music), [artist])
        XCTAssertEqual(memory.path(for: .favorites), [favourite])
        XCTAssertTrue(memory.path(for: .movies).isEmpty)
    }

    /// The two halves of a library drill-down have to agree. The row asks for a
    /// `ChildrenRequest` to load the screen, and the value it pushes — the only
    /// thing the memory ever sees — is built from that request's target. A
    /// mismatch would come back on a different screen than the row that was tapped.
    func testALibraryRowPushesThePlaceItsChildRequestNames() throws {
        let show = try JSONDecoder().decode(
            MediaItem.self,
            from: Data(#"{"label":"The Wire","tvshowid":12}"#.utf8)
        )

        let request = try XCTUnwrap(LibrarySection.tvshows.childRequest(for: show))
        let pushed = Favorite(title: show.heading, target: request.favoriteTarget)

        XCTAssertEqual(pushed.target, .episodes(tvshowID: 12))
        XCTAssertEqual(pushed.title, "The Wire")
    }

    /// Rows that play instead of drilling down push nothing, so nothing is added
    /// to the place and the memory cannot invent a screen for them.
    func testRowsThatPlayDoNotPush() throws {
        let film = try JSONDecoder().decode(
            MediaItem.self,
            from: Data(#"{"label":"Heat","movieid":3}"#.utf8)
        )
        XCTAssertNil(LibrarySection.movies.childRequest(for: film))
    }

    // MARK: Remote's way back

    /// The Remote is the only destination reached *from* another one, so it is
    /// the only one that has to remember where it came from: the jump button on
    /// every browse screen sends the user here, and the control in its place has
    /// to send them back to the folder they were in, not to the drawer's idea of
    /// "Addons".
    func testOpeningTheRemoteRemembersWhereItWasOpenedFrom() {
        XCTAssertEqual(ShellDestination.addons.returnTarget(whenSelecting: .remote), .addons)
        XCTAssertEqual(ShellDestination.files.returnTarget(whenSelecting: .remote), .files)
        XCTAssertEqual(ShellDestination.movies.returnTarget(whenSelecting: .remote), .movies)
    }

    func testOnlySelectingTheRemoteSetsAWayBack() {
        // The rule fires when the Remote is the destination being selected, from
        // anywhere. Selecting anything else must never set one, or the drawer's
        // behaviour would change too.
        for destination in ShellDestination.allCases {
            for item in ShellDestination.allCases where item != .remote {
                XCTAssertNil(destination.returnTarget(whenSelecting: item),
                             "\(item.title) from \(destination.title) should not set a return target")
            }
        }
    }

    func testReselectingTheRemoteKeepsTheEarlierTarget() {
        // Tapping Remote again while already on it must not wipe where it was
        // opened from — nil here means the shell leaves the remembered target
        // alone.
        XCTAssertNil(ShellDestination.remote.returnTarget(whenSelecting: .remote))
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

    /// The layout control draws one of these, so a mode naming a symbol that does
    /// not exist would show an invisible toolbar button.
    func testEveryViewModeSymbolExists() {
        assertSymbolsExist(ViewMode.allCases.map(\.systemImage))
    }

    /// The utility row is built inline rather than from an enum, so its symbols go
    /// through `RemoteTileSymbol.all`. The row and the test read the same
    /// constants, so a typo fails here instead of shipping an invisible button.
    func testEveryRemoteTileSymbolExists() {
        assertSymbolsExist(RemoteTileSymbol.all)
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
        // Home has no destination — its tile drives the host — but it still wears
        // the drawer Home row's word and mark, so it stays in this check.
        XCTAssertEqual(RemoteShortcut.home.title, ShellDestination.home.title)
        XCTAssertEqual(RemoteShortcut.home.systemImage, ShellDestination.home.systemImage)
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

    /// The surface sends `action`, not `key`: a tap and a swipe are one gesture,
    /// so every finished touch has to resolve to something. A nil-driven surface
    /// is one where the swipe lands and nothing happens.
    func testTouchpadTapResolvesToSelect() {
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: .zero), .select)
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: CGSize(width: 5, height: -5)), .select)
    }

    func testTouchpadSwipeResolvesToItsDirection() {
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: CGSize(width: 120, height: 4)), .right)
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: CGSize(width: -120, height: 4)), .left)
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: CGSize(width: 4, height: -120)), .up)
        XCTAssertEqual(TouchpadGestureResolver.action(forTranslation: CGSize(width: 4, height: 120)), .down)
    }

    // MARK: Touchpad step count

    /// How many key presses one swipe is worth. Written against `pointsPerStep`
    /// rather than against a hard-coded number, so retuning the sensitivity does
    /// not fail the tests that describe the shape of the mapping.

    func testTouchpadStepsScaleWithSwipeLength() {
        let step = TouchpadGestureResolver.pointsPerStep
        XCTAssertEqual(TouchpadGestureResolver.steps(forTranslation: CGSize(width: step, height: 2)), 1)
        XCTAssertEqual(TouchpadGestureResolver.steps(forTranslation: CGSize(width: step * 3, height: 2)), 3)
        // The dominant axis decides, exactly as it does for the key itself.
        XCTAssertEqual(TouchpadGestureResolver.steps(forTranslation: CGSize(width: 2, height: -step * 2)), 2)
    }

    /// Same distance, released faster, has to move further — that is the whole
    /// point of reading speed as well as length.
    func testTouchpadFlickAddsStepsForTheSameTravel() {
        let travelled = CGSize(width: 120, height: 6)
        let slow = TouchpadGestureResolver.steps(forTranslation: travelled, predictedEnd: travelled)
        let flick = TouchpadGestureResolver.steps(
            forTranslation: travelled,
            predictedEnd: CGSize(width: 320, height: 6)
        )
        XCTAssertGreaterThan(flick, slow)
        XCTAssertGreaterThanOrEqual(flick, 5)
    }

    func testTouchpadStepsAreCapped() {
        let huge = TouchpadGestureResolver.steps(
            forTranslation: CGSize(width: 4_000, height: 0),
            predictedEnd: CGSize(width: 9_000, height: 0)
        )
        XCTAssertEqual(huge, TouchpadGestureResolver.stepCap)
    }

    /// A tap is `select`, and a select has to land exactly once: repeating it
    /// would open whatever is under the finger and then immediately open it again.
    /// A fast tap has a large projected end, so the tap branch must decide on
    /// travel alone.
    func testTouchpadTapSelectsExactlyOnce() {
        XCTAssertEqual(TouchpadGestureResolver.steps(forTranslation: .zero), 1)
        XCTAssertEqual(
            TouchpadGestureResolver.steps(
                forTranslation: CGSize(width: 6, height: -4),
                predictedEnd: CGSize(width: 400, height: 300)
            ),
            1
        )
    }

    // MARK: Seek on the arrows

    /// Fullscreen playback is the one context where left/right seek instead of
    /// moving focus — and it is what turns a multi-step swipe into real distance
    /// through the film. Kodi owns the escalation (10s → 30s → 1min → 3min → 5min);
    /// the app only has to name the step action.
    func testFullscreenPlaybackTurnsTheArrowsIntoSeekSteps() {
        XCTAssertEqual(AppModel.actionForPlayback("left", seeking: true), "stepback")
        XCTAssertEqual(AppModel.actionForPlayback("right", seeking: true), "stepforward")
    }

    func testArrowsNavigateWhenNotFullscreen() {
        XCTAssertEqual(AppModel.actionForPlayback("left", seeking: false), "left")
        XCTAssertEqual(AppModel.actionForPlayback("right", seeking: false), "right")
    }

    /// A video playing fullscreen is no reason for up/down to stop moving. Seeking
    /// must not swallow the rest of the pad — `select` is deliberately absent here
    /// because the centre *does* change meaning there; see the next test.
    func testSeekingLeavesEveryOtherActionAlone() {
        for action in ["up", "down"] {
            XCTAssertEqual(AppModel.actionForPlayback(action, seeking: true), action)
        }
    }

    /// The centre raises the controls bar while a video plays fullscreen — `osd`,
    /// which is what a keyboard's Enter sends on a playing video. With the bar up,
    /// Kodi's current window is the OSD (12901) rather than fullscreen video (12005),
    /// so the gate goes false and the centre selects again, activating the focused
    /// control. The window id carries that state, so nothing else has to track it.
    func testCentreButtonRaisesTheControlsBarWhileFullscreenPlayback() {
        XCTAssertEqual(AppModel.actionForPlayback("select", seeking: true), "osd")
        XCTAssertEqual(AppModel.actionForPlayback("select", seeking: false), "select")
    }

    /// The `o` overlay can be asked for whenever a player is running — Kodi toggles
    /// it (the dialog closes itself on this action), so the app must not gate it on
    /// which window the box has focused: opening the overlay changes that window, and
    /// gating on it was why the second press did nothing.
    func testPlayerInfoIsAskedForWheneverSomethingIsPlaying() {
        XCTAssertEqual(AppModel.playerInfoAction(playing: true), "playerprocessinfo")
        XCTAssertNil(AppModel.playerInfoAction(playing: false))
    }

    // MARK: Tray pulls

    /// Up on the playback bar opens the full player, down on that player closes it.
    /// Both directions share one rule, so they cannot disagree about the threshold.
    func testTrayPullsResolveByDirection() {
        let far = TraySwipe.minimumTravel + 20
        XCTAssertTrue(TraySwipe.isPull(CGSize(width: 4, height: -far), direction: .up))
        XCTAssertTrue(TraySwipe.isPull(CGSize(width: 4, height: far), direction: .down))
    }

    /// A short drag is a tap, a drag the other way is not a pull, and a sideways
    /// drag is never either: the bar is covered in transport buttons a thumb slides
    /// across, and none of those should open a full-screen surface.
    func testTrayPullsIgnoreShortSidewaysAndReversedDrags() {
        let far = TraySwipe.minimumTravel + 20
        XCTAssertFalse(TraySwipe.isPull(CGSize(width: 4, height: -10), direction: .up))
        XCTAssertFalse(TraySwipe.isPull(CGSize(width: 4, height: -far), direction: .down))
        XCTAssertFalse(TraySwipe.isPull(CGSize(width: 4, height: far), direction: .up))
        XCTAssertFalse(TraySwipe.isPull(CGSize(width: far * 2, height: -far), direction: .up))
        XCTAssertFalse(TraySwipe.isPull(CGSize(width: -far * 2, height: far), direction: .down))
    }

    // MARK: Scroll memory

    func testNothingIsRememberedForAPlaceNeverScrolled() {
        XCTAssertNil(ScrollMemory().top(for: ScrollPlace.addons))
    }

    func testAPlaceScrolledDownIsRemembered() {
        let memory = ScrollMemory()
        memory.record(140, for: ScrollPlace.library(.movies))
        XCTAssertEqual(memory.top(for: ScrollPlace.library(.movies)), 140)
    }

    /// Item 0 *is* the top of the list, which is the same as having no memory: a
    /// list left at its top has to come back at its top, not pinned to item 0.
    func testLeavingAListAtItsTopForgetsThePlace() {
        let memory = ScrollMemory()
        let movies = ScrollPlace.library(.movies)
        memory.record(140, for: movies)
        memory.record(0, for: movies)
        XCTAssertNil(memory.top(for: movies))

        memory.record(140, for: movies)
        memory.record(nil, for: movies)
        XCTAssertNil(memory.top(for: movies))
    }

    func testEachPlaceKeepsItsOwnScroll() {
        let memory = ScrollMemory()
        let youtube = ScrollPlace.directory("plugin://plugin.video.youtube/")
        memory.record(90, for: youtube)

        XCTAssertEqual(memory.top(for: youtube), 90)
        XCTAssertNil(memory.top(for: ScrollPlace.directory("/storage/films/")),
                     "a second folder was given the first folder's scroll")
        XCTAssertNil(memory.top(for: ScrollPlace.library(.movies)))
    }

    /// Two places must never share a key. A collision sends one screen to another
    /// screen's position, and nothing else in the app can see it happen.
    func testEveryPlaceHasItsOwnKey() {
        let keys = [
            ScrollPlace.library(.movies),
            ScrollPlace.library(.tvshows),
            ScrollPlace.library(.artists),
            ScrollPlace.directory("/storage/films/"),
            ScrollPlace.directory("plugin://plugin.video.youtube/"),
            ScrollPlace.children(.episodes(tvshowID: 12)),
            ScrollPlace.children(.albumsOfArtist(artistID: 7)),
            ScrollPlace.addons,
            ScrollPlace.favorites,
        ]
        XCTAssertEqual(Set(keys).count, keys.count, "two places share a scroll key: \(keys)")
    }

    /// A favourite reopens the screen it was saved from, so it has to derive the
    /// same key — otherwise its place is restored but its scroll is not.
    func testAFavouriteDerivesTheSameKeyAsThePlaceItWasSavedFrom() {
        let path = "plugin://plugin.video.youtube/special/my_subscriptions"
        let favourite = Favorite(title: "My Subscriptions", target: .directory(path: path))
        XCTAssertEqual(ScrollPlace.directory(path), favourite.target.id)
    }

    // MARK: Mini-player visibility

    func testMiniPlayerHiddenWithNoPlayer() {
        XCTAssertFalse(MiniPlayer.isVisible(activePlayer: nil))
    }

    func testMiniPlayerShownWithAPlayer() {
        XCTAssertTrue(MiniPlayer.isVisible(activePlayer: ActivePlayer(playerid: 0, type: "audio")))
        XCTAssertTrue(MiniPlayer.isVisible(activePlayer: ActivePlayer(playerid: 1, type: "video")))
    }

    /// The progress line and the time readout are gated on the host reporting a
    /// duration: a live stream reports none, and "0:00 of 0:00" over an empty line
    /// is worse than saying nothing.
    func testMiniPlayerShowsProgressOnlyWithADuration() {
        XCTAssertTrue(MiniPlayer.showsProgress(durationSeconds: 1485))
        XCTAssertFalse(MiniPlayer.showsProgress(durationSeconds: 0))
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

    // MARK: Connection recovery

    /// The latched-handshake bug: a handshake that timed out left the status
    /// failed, and with it live state dead — the ticker and the event stream were
    /// both skipped, so the now-playing bar could never appear, while every other
    /// call still reached the host. A poll that succeeds is proof the host is
    /// answering, so it revives the status. `.idle` is a deliberate disconnect and
    /// must never be revived.
    func testASuccessfulPollRevivesOnlyAFailedStatus() {
        XCTAssertTrue(AppModel.revivesFromFailure(.failed("The request timed out.")))
        XCTAssertFalse(AppModel.revivesFromFailure(.connected))
        XCTAssertFalse(AppModel.revivesFromFailure(.connecting))
        XCTAssertFalse(AppModel.revivesFromFailure(.idle))
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
