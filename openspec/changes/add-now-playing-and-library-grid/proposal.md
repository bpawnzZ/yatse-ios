# Proposal

## Why

Three usability gaps remain after the app-shell change, all reported from the
first on-device run of the app:

- The Remote wastes the bottom third of the screen. Its directional pad is a
  fixed-size block inside a scrolling stack, so the arrows and select — the
  controls a thumb reaches for most — are small and float in the middle of the
  page instead of filling the space below the tile rows.
- There is no Now Playing surface. Tapping the mini-player currently just jumps
  the shell to the Remote, so there is nowhere to scrub, see what is playing, or
  change the audio/subtitle streams without leaving the app for the TV.
- Movies and TV Shows render as one-per-row lists, which shows a handful of
  titles at a time and ignores poster artwork, where the reference app is a
  two-wide grid of posters.

## What Changes

- **Remote fills the screen.** The Remote stops scrolling and pins its status,
  shortcut, volume and utility rows to the top; the directional pad grows to
  consume the remaining height (up / left / select / right / down), with the bare
  Back control and the touchpad toggle below it. The pad stays a square sized to
  the space available, so it is as large as the device allows.
- **Now Playing overlay.** Tapping the mini-player opens a full-screen Now
  Playing surface over a see-through rendering of the current item's artwork. It
  carries a seek slider with elapsed/duration, transport controls (previous,
  rewind, play/pause, forward, next), stop, repeat and shuffle, an Info/details
  view, and pickers for the audio stream, the subtitle stream (including off) and
  the video/zoom mode, plus the queue.
- **Poster grid.** Movies and TV Shows browse as a two-column grid of poster
  tiles with the title (and year/detail) beneath each; the other library sections
  keep their list. Drill-down screens (a show's episodes, an artist's albums) keep
  their current list.

## Capabilities

### New Capabilities

- `now-playing-overlay`: the full-screen Now Playing surface — its see-through
  artwork backdrop, transport and seek controls, and the stream (audio, subtitle,
  video/zoom) selection and info/queue it exposes.
- `library-browsing`: how a library section is presented — a two-column poster
  grid for poster media (Movies, TV Shows) with a fallback list for text media.

### Modified Capabilities

- `app-shell`: the **Remote Screen Chrome** requirement changes — the Remote no
  longer scrolls, the directional pad fills the free space below the tile rows,
  and the utility row is stated as the Back / Fullscreen / Info / Keyboard /
  Context set that the shipped code already uses.

## Impact

- **New code**: the Now Playing overlay view and its sub-surfaces (info, stream
  pickers, queue re-homed from `QueueSheet`), and a poster-tile view for the grid.
- **Modified code**: `YatseRemote/UI/RemoteScreen.swift` (non-scrolling layout,
  space-filling control pad), `YatseRemote/UI/MiniPlayer.swift` (tap opens the
  overlay instead of the Remote), `YatseRemote/UI/ShellView.swift` (presents the
  overlay), `YatseRemote/UI/LibraryView.swift` (grid vs list), `AppModel`
  (select a stream by index, shuffle/repeat setters, previous/next),
  `KodiModels.swift` (decode the audio-stream and subtitle lists and the item's
  plot/metadata), `KodiClient.swift` (request those properties).
- **Tests**: pure rules — the section → layout mapping and a control-pad sizing
  helper — plus decoder tests for the newly fetched stream/item fields. CI cannot
  render SwiftUI, so these are the only verifiable surface.
- **No** Info.plist, entitlement, CI-workflow, dependency or asset changes.
- **Unverified until a device run**: the overlay's appearance, the pad's filled
  proportions and the grid's spacing cannot be seen in CI.
