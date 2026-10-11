# Design

## Context

See `proposal.md` — Why. Current state that shapes the approach:

- `AppModel` is created inside `RemoteView` as a `@StateObject` and destroyed on
  `onDisappear`. It owns the connect/disconnect lifecycle, the WebSocket event
  stream and the 1 Hz progress ticker. Nothing above a screen holds it.
- `HostsView` is the `@main` root: a `NavigationStack` over the host list that
  pushes `RemoteView`. Host management (add/edit/delete/check) and discovery live
  in the same view.
- `LibraryView` is a sheet with its own segmented picker and a `Done` button.
- There is no macOS host: compilation and unit tests happen only in CI, so the
  design must keep everything that can be wrong in plain, testable values, and
  the UI layer must stay small and obvious because it cannot be seen running.

## Goals / Non-Goals

**Goals:**

- Playback and connection outlive any single screen.
- One place decides what a top-level destination is, so the drawer and the
  shortcut strip cannot drift apart.
- The pieces with real logic (destination list, gesture → key mapping,
  mini-player visibility) are pure functions with unit tests.
- A destination that does not exist yet is honest about it.

**Non-Goals:**

- Any library content redesign (grid, tabs, detail screens) — a later phase.
- A user-selectable theme. Only the requirement that chrome does not hardcode a
  colour.
- Multi-host session management beyond a switcher (one active host at a time).
- Reconnecting/backoff policy changes to `AppModel`.

## Decisions

### Player state moves to an app-level `Session`

`Session` is a `@MainActor ObservableObject` holding `host`, `password` and the
active `AppModel`. `RootView` owns it via `@StateObject` and injects it. The
mini-player, the Remote and Now Playing all read `Session.model`.

*Alternative considered:* keep the model in `RemoteView` and pass a binding up.
Rejected: SwiftUI re-creates `@StateObject` per screen identity, so a pushed
library screen would still destroy it; ownership must be above the stack.

### Root swaps on session state, not on a route

`RootView` renders `HostsView` when `Session.model == nil` and `ShellView`
otherwise. "No active host" and "active host" are two genuinely different apps,
not two screens in one stack, so this is a branch rather than a route.

*Alternative considered:* always show the shell and let a nil host render the
picker inside it. Rejected: the drawer, app bar and mini-player are meaningless
without a host, and this keeps the picker free of shell chrome.

### The drawer is a custom slide-over, not `NavigationSplitView`

`ShellView` is a `ZStack`: the `NavigationStack` of the current destination, then
a scrim and the drawer panel offset to the left, dragged/tapped open. Matches
Yatse's temporary Material drawer and works identically in portrait.

*Alternative considered:* `NavigationSplitView` (a sidebar). Rejected: it is a
permanent split on iPad and a two-level navigation on iPhone — neither is the
overlay drawer the spec describes.

### One stack, destination selected by value

`ShellView` holds `@State var destination: ShellDestination` and a `NavigationPath`.
The stack's root is `view(for: destination)`; changing the destination resets the
path. Detail pushes (e.g. a show's episodes) go onto the path of that destination.

*Alternative considered:* a separate stack per destination. Rejected: three
stacks to keep in sync for no visible difference, and back must not cross the
drawer boundary anyway.

### The drawer and the shortcut strip share one destination model

`ShellDestination` is the single source of truth for a top-level destination: its
title, its SF Symbol and whether it is implemented. The drawer lists all of them;
the shortcut strip lists the five quick ones. A unit test asserts the order and
membership, so the two cannot drift.

### Unimplemented destinations render a placeholder with the reason

`PlaceholderScreen` takes a title and a one-line message naming why (e.g. "PVR is
out of scope for this build"). No destination is a silent dead end.

### The touchpad mapping is a pure function

`TouchpadGestureResolver.key(forTranslation:threshold:)` returns a `TouchKey`
(`.up/.down/.left/.right/.select`) or nil. The view feeds it the drag and sends
the resulting key through `AppModel.key`. The resolver is unit-tested; the view
is a thin shell around it.

### The mini-player visibility rule is a pure function

`MiniPlayer.isVisible(for:)` is true when there is an active player
(`AppModel.activePlayer != nil`). Kept out of the view so the "shown only during
playback" rule is testable.

### Minimise the compile surface by reusing existing views

Library sections route to the **existing** `LibraryView`, given an initial
section and an embedded mode (no `Done`, no own `NavigationStack`). The Remote is
the only screen genuinely rewritten. This keeps the un-runnable UI delta as small
as it can be while meeting the spec.

## Risks / Trade-offs

- **[The UI cannot be seen before shipping]** → the UI is kept thin over pure,
  unit-tested values; anything non-obvious lives in a tested helper, not in a
  `body`. Stated plainly as unverified in the tasks.
- **[A custom drawer is easy to make look wrong]** → it is a plain offset panel
  over a scrim with a drag gesture, no bespoke animation curve, so it degrades to
  something predictable.
- **[Reusing `LibraryView` inside the shell breaks its sheet contract]** → it
  gains an explicit `embedded` mode rather than being quietly reused; the sheet
  usages are updated in the same change.
- **[`send(_:_:)` currently decodes every result as `String`]** → `GUI.SetFullscreen`
  returns a bool, which would throw `malformedResponse`. The command path is made
  result-agnostic (decode into a type that ignores the payload), while JSON-RPC
  errors still surface.
- **[Session outlives a removed host]** → if the active host is deleted, the
  session deactivates back to the picker.

## Migration Plan

Additive and behavioural only; no persisted-data change. The session is created
at launch with no active host, so the app opens on the picker exactly as before
until a host is chosen. Rollback is reverting the commit.

## Open Questions

- Whether Home should be a dashboard of shortcuts or the Remote with the drawer
  open — deferred; this change gives Home a minimal screen and can revisit.
