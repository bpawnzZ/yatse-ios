# Design

## Context

See `proposal.md` — Why. Current state that shapes the approach:

- `RemoteScreen` is a `ScrollView` over a `VStack`; the d-pad is three fixed
  78pt rows (`dpadButton`/`selectButton`). It cannot grow because the stack sizes
  to its content.
- `MiniPlayer` takes an `onOpen` closure; `ShellView` passes `{ select(.remote) }`.
  The overlay needs the model, which lives in `Session` above the stack, so the
  presentation belongs to `ShellView`, not to `MiniPlayer`.
- `LibraryView` is one `List` given a `LibrarySection`; `ChildrenView` is a second
  `List`. `LibrarySection` already centralises a section's method, properties,
  sort and its `childRequest`, so it is the natural place to also decide layout.
- `AppModel` already has `seek(toSeconds:)`, `skip(_:)`, `toggleShuffle()`,
  `cycleRepeat()`. `KodiClient.playerProperties` already *requests*
  `audiostreams` / `subtitles`, but `PlayerProperties` only decodes the current
  ones, and `currentItem` does not request `plot`/`year`/`genre`, so there is no
  data for pickers or an info view yet.
- There is no Mac: only CI compiles. Anything with logic must be a pure, tested
  value; the UI must stay thin and obvious because it is never seen running.

## Goals / Non-Goals

**Goals:**

- The Remote uses the whole screen, with the d-pad as large as the device allows.
- A Now Playing surface that can scrub and switch audio/subtitle streams without
  leaving the app.
- Movies and TV Shows browse as a two-wide poster grid; nothing else changes
  shape.
- The decisions that can be wrong (section → layout, pad sizing, stream
  semantics) live in pure, unit-tested values.

**Non-Goals:**

- A drag-to-dismiss interactive transition, or an overlay that tracks the finger
  the way Yatse's sliding panel does — a presented cover is enough for now.
- Landscape-specific Remote layout beyond the pad filling whatever space exists.
- Per-section library tabs, sort menus, detail screens or context menus — a later
  phase.
- Editing the queue's order; jump and remove only.

## Decisions

### The overlay is a `fullScreenCover` presented by `ShellView`

`ShellView` owns `@State showingNowPlaying`; `MiniPlayer`'s `onOpen` sets it, and
the cover renders `NowPlayingView(model:)`. The overlay draws its own artwork
backdrop and translucent scrim, so it does not depend on the system sheet
chrome.

*Alternative considered:* a `.sheet` with detents and
`.presentationBackground(.ultraThinMaterial)`. Rejected: the see-through artwork
is the point, and a cover gives full control of the backdrop across iOS versions.
*Alternative considered:* presenting from `MiniPlayer`. Rejected: the mini-player
is a pure, reusable strip; the shell is the thing that owns overlay state.

### The Remote pins its rows and the pad fills the remainder

`RemoteScreen`'s `ScrollView` is replaced by a `VStack` with no scroll: the
status line, shortcut strip, volume row and utility row are fixed at the top, and
the control pad takes `.frame(maxHeight: .infinity)`. Inside, a `GeometryReader`
sizes the pad square to `min(width, height)`, so the arrows and select are as
large as the device permits. Back and the touchpad toggle stay in a short row
beneath the pad.

*Alternative considered:* keep the scroll view and let the pad grow with
`maxHeight`. Rejected: a scroll view still clips to content and the pad would
not fill a tall screen; the user asked for the space to be consumed.
*Risk:* on a short screen the pinned rows plus a large pad could crowd. Mitigated
by sizing the pad to the available height (never overflowing) and keeping the
rows compact.

### The pad's size is a pure function

`ControlPadMetrics.side(in available: CGSize, reserved: CGFloat)` returns the
square's side. The view reads it; a unit test asserts it is bounded by height
when height is the constraint, by width when width is, and never negative. This
is the one non-obvious number in the layout, so it is the one that is tested.

### Section layout is a property of `LibrarySection`

`LibrarySection` gains `layout: LibraryLayout` (`grid` for movies and tvshows,
`list` for artists and albums) and the grid/list column choice for the grid.
`LibraryView` reads it: a `LazyVGrid` of two flexible columns for `grid`, the
existing `List` for `list`. Pagination, empty/error states and the toolbar are
shared by both branches, so there is still one browser, not two.
`ChildrenView` stays a `List` — an episode or a track is read as text.

*Alternative considered:* a separate `GridLibraryView`. Rejected: it duplicates
pagination, refresh and states for a column-count difference.

### The poster tile is a thin view over the existing artwork loader

`PosterTile` shows artwork (2:3), the title and the detail line, and routes a tap
through the same `section.childRequest` decision the list uses, so drill-down
behaviour is identical between layouts. Artwork uses the existing authenticated
`ArtworkLoader`/`ArtworkCache`; a new container-filling image variant is added
next to `ArtworkImage` rather than changing that view's fixed-size contract.

### Stream pickers and info come from newly requested fields

`PlayerProperties` decodes `audiostreams: [AudioStream]` and
`subtitles: [SubtitleStream]` (already requested by the client). `PlayerItem`
gains `plot`, `year` and `genre` (a `StringList`), and `currentItem` requests
them. The overlay builds its pickers from those arrays with each stream's
`index`; selecting sends `Player.SetAudioStream` / `Player.SetSubtitle` with that
index, and subtitles-off sends `subtitle: "off"`. All bodies decode leniently, so
a build that returns no stream list simply shows no picker rather than failing.

*Alternative considered:* fetch streams in a separate call. Rejected: the fields
are already in the existing `Player.GetProperties` request; only the model was
missing.

### Video/zoom is a single action, validated read-only during apply

Kodi exposes no video-stream list, so the overlay's video control advances zoom
with `Input.ExecuteAction` (`aspectratio`) — the behaviour, not a menu. The exact
action string is confirmed against the live box's `JSONRPC.Introspect` action
enum by a read-only probe during implementation, not guessed; if the enum lacks
it, it falls back to `Player.SetVideoStream` next/previous.

## Risks / Trade-offs

- **[The UI cannot be seen before shipping]** → keep every decision in a pure,
  tested value (`ControlPadMetrics`, `LibrarySection.layout`) and the views thin.
  Stated as unverified in the tasks.
- **[Stream indices are not the array position]** → always send the stream's own
  `index` field, never the row's offset; the pickers are keyed by `index`.
- **[`aspectratio` may not be a valid action]** → validated read-only first; a
  documented fallback exists, and no task asserts it works without that check.
- **[A two-column grid on a tiny screen is cramped]** → the columns are flexible
  (`GridItem(.flexible())`), so they divide the width rather than overflow.
- **[The overlay adds a per-second repaint of a blurred image]** → the existing
  1 Hz ticker already drives position; the backdrop is loaded once and cached.

## Migration Plan

Additive and behavioural only; no persisted-data or protocol-shape change. Roll
back by reverting the commit. The Remote, mini-player tap target, and library
rendering are the only visible changes.

## Open Questions

- Whether the overlay should later become the interactive slide-up panel (drag to
  reveal the Remote behind it) rather than a cover — deferred; the cover meets the
  stated behaviour and the specs do not name the transition.
