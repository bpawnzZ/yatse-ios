# Proposal

## Why

The app speaks Kodi JSON-RPC correctly, but its UI is still a straight port of
the protocol layer: a host list that pushes one long, unstyled scrolling remote,
and library browsing as flat list rows. The Android app this is specified from is
**host-centric** — a persistent navigation drawer, a persistent mini-player, and
a single structured Remote screen — and none of that chrome exists here.

Two concrete problems follow from the current shape:

- **Playback state dies on navigation.** Each `RemoteView` builds its own
  `AppModel` with `@StateObject`, so leaving the remote (to browse the library,
  or to go back to the host list) tears down the model, its event stream and its
  ticker. A mini-player that must outlive the screen is impossible until the
  player state is owned above the navigation stack.
- **There is no shell.** The screen hierarchy is flat: host list → remote, with
  library/queue/keyboard as sheets. There is no drawer, no host switcher outside
  the list, and no place to hang the other destinations.

## What Changes

- Add an **app-level session** that owns the active host and its player state, so
  playback and connection survive navigation.
- Change the root: before a host is chosen the app shows the host picker; once a
  host is active the root becomes a **host-centric shell** with a slide-out
  drawer. Host management moves under Settings / the picker.
- Add the **navigation drawer** as Yatse defines it: a header with the host name,
  a host switcher, and keyboard / mic / search actions; then Home, Movies, TV
  Shows, Music, Pvr, Files, Addons, Remote; a divider; then Settings and About.
- Add a **persistent mini-player** shown whenever a player is active, on every
  destination, with a thumbnail, the title, and stop / pause / next.
- Rebuild the **Remote as one screen** (no tabs): top app bar with the host name
  and power / cast / remote actions; a shortcut strip (Home, Movies, TV Shows,
  Music, Pictures); a volume tile row; a utility tile row; a large d-pad with
  accent arrows and an outlined OK; a bare Back arrow; and a touchpad toggle.
- When playback is active the Remote background becomes the (blurred) artwork and
  the tiles turn translucent.
- Destinations that are not implemented yet (Pvr, Files, Addons) show a clear
  placeholder rather than a dead end.

## Capabilities

### New Capabilities

- `app-shell`: how the app is structured around an active host — the session that
  owns player state, the navigation drawer, the persistent mini-player, and the
  Remote screen's chrome.

### Modified Capabilities

None — this repository has no main specs yet; `add-connection-diagnostics` added
only its own capability delta.

## Impact

- **New code**: `YatseRemote/App/Session.swift` (active-host + player state),
  `YatseRemote/UI/RootView.swift` (picker vs shell), `YatseRemote/UI/ShellView.swift`
  (drawer + mini-player + destination routing), `YatseRemote/UI/AppDrawer.swift`
  (the drawer and the destination model), `YatseRemote/UI/MiniPlayer.swift`,
  `YatseRemote/UI/RemoteScreen.swift`, `YatseRemote/UI/Touchpad.swift`,
  `YatseRemote/UI/HomeScreen.swift`, `YatseRemote/UI/SettingsView.swift`,
  `YatseRemote/UI/PlaceholderScreen.swift`.
- **Modified code**: `HostsView` (acts as picker or manager and activates the
  session), `LibraryView` (embeddable, opens to a chosen section), `AppModel`
  (volume stepping, fullscreen, a result-agnostic command send).
- **Tests**: new unit tests for the destination model, the touchpad gesture
  resolver, the mini-player visibility rule and the shortcut mapping — pure
  values, no networking. This is the only surface CI can verify.
- **No** Info.plist, entitlement, CI-workflow or dependency changes. The drawer,
  shell and mini-player are SwiftUI-only. Accent colour stays the asset colour, so
  nothing hardcodes the drawing's blue.
- **Out of scope**: the library-parity work (poster grid, per-section tabs,
  detail screens, context menus), the Now Playing full page, PVR, Files, Addons,
  a user-configurable theme, and hardware-volume-key control. These are recorded
  as follow-on phases, not built here.
