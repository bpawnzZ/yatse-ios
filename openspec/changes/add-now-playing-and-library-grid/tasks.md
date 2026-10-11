# Tasks

## 1. Remote fills the screen

- [x] 1.1 Add a pure `ControlPadMetrics.side(in:reserved:)` to the Remote that returns the square pad's side, and a unit test asserting it is bounded by the height when height is the smaller dimension, bounded by the width when width is, and never negative; verify the CI "Unit tests" run passes (Swift is not compilable on the development host).
- [x] 1.2 Rewrite `YatseRemote/UI/RemoteScreen.swift` as a non-scrolling layout: status, shortcut, volume and utility rows pinned at the top, the control pad sized by `ControlPadMetrics` and expanded with `maxHeight: .infinity` to consume the remaining height (arrows + outlined select), and the bare Back control and touchpad toggle in a short row beneath; verify the CI "Build unsigned IPA" run compiles it.
- [x] 1.3 Update the Remote description in `README.md` and the Remote notes in `AGENT.md` to the pinned, space-filling layout; verify the described behaviour matches the code.

## 2. Now Playing data and commands

- [x] 2.1 Decode the streams and item metadata the overlay needs: add `audiostreams: [AudioStream]` and `subtitles: [SubtitleStream]` to `PlayerProperties`, add `plot`, `year` and `genre` to `PlayerItem`, request `plot`/`year`/`genre` in `KodiClient.currentItem`, and add decoder unit tests for a payload that carries streams and metadata and one that omits them; verify the CI "Unit tests" run passes.
- [x] 2.2 Add the `AppModel` commands the overlay drives — `selectAudioStream(index:)`, `selectSubtitle(index:)`, `subtitlesOff()`, `setShuffle(_:)`, `setRepeat(_:)`, `previous()` and `next()` — and a unit test for the pure repeat-cycle mapping (`off → all → one → off`); verify the CI "Build unsigned IPA" run compiles and the "Unit tests" run passes.

## 3. Now Playing overlay

- [x] 3.1 Add `YatseRemote/UI/NowPlayingView.swift`: a see-through artwork backdrop over a translucent scrim, a seek slider with elapsed/duration, the transport row (previous, rewind, play/pause, forward, next, stop), repeat and shuffle, an Info/details view, audio/subtitle/video pickers keyed by each stream's own `index`, and the queue (re-homing `QueueSheet`); verify the CI "Build unsigned IPA" run compiles it.
- [x] 3.2 Present the overlay from `ShellView` as a `fullScreenCover` and change `MiniPlayer`'s activation to open it instead of switching the destination; verify the CI "Build unsigned IPA" run compiles it.
- [x] 3.3 Add a unit test for the pure stream-selection mapping — audio/subtitle selection sends the stream's `index`, and "off" sends the subtitle-off sentinel rather than an index — so the stream semantics are checked without a host; verify the CI "Unit tests" run passes.
- [x] 3.4 Update `README.md` and `AGENT.md` for the overlay (what it opens from, what it exposes, and that the queue lives there now); verify the described behaviour matches the code.

## 4. Library poster grid

- [x] 4.1 Add `LibrarySection.layout` (`grid` for Movies and TV Shows, `list` for Artists and Albums) and a unit test asserting the mapping; verify the CI "Unit tests" run passes.
- [x] 4.2 Add a poster-tile view (artwork at 2:3, title, detail, placeholder when art is missing) and a container-filling artwork image beside `ArtworkImage`, and render a two-column `LazyVGrid` in `YatseRemote/UI/LibraryView.swift` for grid sections while keeping the `List` for list sections and for `ChildrenView`; verify the CI "Build unsigned IPA" run compiles it.
- [x] 4.3 Update `README.md` and `AGENT.md` for the grid; verify the described behaviour matches the code.

## 5. Integration

- [x] 5.1 Confirm the video/zoom action string against the live Kodi action enum with a read-only probe (no `Input.ExecuteAction`, no playlist mutation, no settings writes), and record which action the overlay will send; verify the probe output names the action and the code sends that one.
- [x] 5.2 Push the branch and confirm both `build-ipa.yml` and `tests.yml` are green on the same commit; report both run IDs and the test count.

## Workflow follow-up

- Install the resulting IPA on a device and confirm the control pad fills the
  screen, the Now Playing overlay renders and scrubs/switches streams, and Movies
  and TV Shows render as a two-wide grid — the step no task above can verify
  (there is no Mac in the development loop).
- The library-parity follow-ons (per-section tabs, sort menus, detail screens,
  context menus), PVR/Files/Addons, a configurable theme, and hardware-volume-key
  control remain later phases.
- Archive the change once the project's review requirements are satisfied.
