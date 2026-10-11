# Tasks

## 1. Session owns player state

- [x] 1.1 Add `YatseRemote/App/Session.swift`: a `@MainActor` `ObservableObject` holding the active `Host`, its password and its `AppModel`, with `activate(host:password:)` and `deactivate()`; verify the CI "Build unsigned IPA" run for the branch compiles it (Swift is not compilable on the development host).
- [x] 1.2 Make `RootView` (`YatseRemote/UI/RootView.swift`) show `HostsView` when no host is active and `ShellView` otherwise, and update `@main` to render `RootView`; verify it compiles in CI.
- [x] 1.3 Make `HostsView` activate the session instead of pushing `RemoteView`, and give it a picker/manager mode so it can be reused under Settings; verify it compiles in CI.

## 2. Destination model and drawer

- [x] 2.1 Add `ShellDestination` (title, SF Symbol, implemented-ness, drawer grouping) in `YatseRemote/UI/AppDrawer.swift`, plus the drawer view with the host header, host switcher and keyboard/mic/search actions; verify it compiles in CI.
- [x] 2.2 Add a unit test asserting the drawer order (Home, Movies, TV Shows, Music, Pvr, Files, Addons, Remote, Settings, About) and the shortcut-strip order (Home, Movies, TV Shows, Music, Pictures), and that every shortcut with a shell destination maps to an implemented one; verify it passes in the CI "Unit tests" run.

## 3. Shell and mini-player

- [x] 3.1 Add `ShellView` (`YatseRemote/UI/ShellView.swift`) as the ZStack of a destination `NavigationStack` plus the slide-over drawer and scrim, resetting the path on destination change; verify it compiles in CI.
- [x] 3.2 Add `MiniPlayer` (`YatseRemote/UI/MiniPlayer.swift`) pinned across destinations, showing thumbnail, title and stop/play-pause/next, with a static `isVisible(for:)` rule; verify it compiles in CI.
- [x] 3.3 Add a unit test asserting `MiniPlayer.isVisible` is false with no active player and true with one; verify it passes in CI.

## 4. Remote screen chrome

- [x] 4.1 Rewrite the Remote as one screen (`YatseRemote/UI/RemoteScreen.swift`) with the app bar (hamburger, host name, power, cast, remote), shortcut strip, volume tile row, utility tile row, accent-arrow d-pad with outlined OK, bare Back arrow and touchpad toggle; verify it compiles in CI.
- [x] 4.2 Render the current item's artwork as a blurred background with translucent tiles while playing, and the plain background otherwise; verify it compiles in CI.
- [x] 4.3 Add `YatseRemote/UI/Touchpad.swift` with a pure `TouchpadGestureResolver` and a surface view; verify it compiles in CI.
- [x] 4.4 Add a unit test for the resolver: a horizontal swipe resolves to left/right, a vertical swipe to up/down, the dominant axis wins, and a sub-threshold move resolves to nil; verify it passes in CI.

## 5. Destinations and commands

- [x] 5.1 Add `HomeScreen`, `SettingsView` (current host, host management, app version, disconnect) and `PlaceholderScreen` (Pvr, Files, Addons); route Movies/TV Shows/Music to `LibraryView(model:section:onOpenDrawer:)` and add that parameterised `LibraryView`; verify it compiles in CI.
- [x] 5.2 Add `AppModel` `stepVolume(by:)` and `toggleFullscreen()`, and make the command send result-agnostic (so `GUI.SetFullscreen`'s boolean result does not throw `malformedResponse`); verify it compiles in CI.
- [x] 5.3 Add a unit test for `AppModel.clampedVolume`'s clamping at 0 and 100; verify it passes in CI.

## 6. Integration

- [x] 6.1 Push the branch and confirm both `build-ipa.yml` and `tests.yml` are green on the same commit; report both run IDs and the test count.
- [x] 6.2 Update `README.md` (the shell, drawer, mini-player and the Remote layout) and `AGENT.md` (the session-ownership change and the shell file map); verify the described behaviour matches the merged code.

## Workflow follow-up

- Install the resulting IPA on a device and confirm the drawer, mini-player and
  Remote layout render and behave as described — the step no task above can
  verify (there is no Mac in the development loop).
- The library-parity phase (poster grid, per-section tabs, detail screens,
  context menus), the Now Playing full page, PVR/Files/Addons, a configurable
  theme, and hardware-volume-key control remain later phases.
- Archive the change once the project's review requirements are satisfied.
