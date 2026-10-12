# Design

## Context

See `proposal.md` — Why. Two measured facts from the reference host drive most of
this design:

1. **Add-on type.** Across all 68 installed add-ons, `xbmc.addon.video` appears
   **zero** times. The six video add-ons report `xbmc.python.pluginsource`
   (`plugin.video.youtube`, `plugin.video.jellycon`, `plugin.video.plexkodiconnect`,
   `…plexkodiconnect.movies`, `…plexkodiconnect.tvshows`,
   `plugin.video.themoviedb.helper`). A seventh plugin source,
   `script.pystone.benchmark`, is not a video add-on.
2. **Add-on artwork is not fetchable the way library artwork is.** Add-on icons
   arrive as `image://%2fstorage%2f.kodi%2faddons%2f…%2ficon.png`, which decodes
   to a *local filesystem path*; plugin entries decode to `special://home/…`.
   `Artwork.url` strips `image://`, percent-decodes, and returns
   `URL(string:)` — for those values a schemeless relative URL or an unsupported
   scheme, which `URLSession` refuses. Only library artwork decodes to an
   absolute `http://<media server>` URL today. This is why every add-on and
   plugin-content icon currently falls back to the placeholder.

Existing pieces this builds on: `LibraryView` already renders a two-column
`LazyVGrid` of `PosterTile`s with pagination; `DirectoryView` renders a `List` and
is shared by Files and add-on content; `FavoriteStore` persists favourites and
`AppDrawer` currently expands them into one row each; `ShellView.select()` clears
the pushed path, which is why nothing is remembered.

## Goals / Non-Goals

**Goals:**
- The Addons destination lists video add-ons and nothing else.
- Add-ons, the content inside them, and favourites all read as the same
  two-column poster grid.
- A place inside a video add-on can be saved from a long press and reached again
  from a Favorites destination.
- The drawer is reachable while browsing, and the place last reached in a
  destination is restored when it is re-entered.

**Non-Goals:**
- A grid for the Files destination — it keeps its list, so `library-browsing`
  behaviour is unchanged.
- Launching an add-on on the host (`Addons.ExecuteAddon`); still unimplemented.
- Surfacing the non-video add-on types anywhere (skins, scrapers, fonts,
  resources, scripts, repositories) — they are omitted from the destination.
- Persisting navigation memory across launches.
- Any new Kodi method: `Addons.GetAddons`, `Addons.SetAddonEnabled` and
  `Files.GetDirectory` are already in use.

## Decisions

### Video add-ons are identified by a pure rule on `Addon`

`Addon.isVideoAddon` = the add-on is a plugin source **and** its identifier is in
the `plugin.video.*` namespace. Pure and unit-tested, because the failure it
guards is invisible: the wrong key does not error, it renders an empty screen.

Alternatives considered: filtering on `xbmc.addon.video` — measured as
non-existent on the reference host, so it would show nothing; accepting every
plugin source — brings in `script.pystone.benchmark`; calling
`Addons.GetAddonDetails` per add-on to read `extrainfo.provides` (the host does
report `video audio` there) — 68 extra round trips to draw one screen.

### One tile type, parameterised — not a second tile

`PosterTile` gains an initialiser taking its artwork URL, title and detail line;
the existing `MediaItem` initialiser becomes a convenience over it. The
Favorites grid, the add-on grid and the add-on content grid then all render the
one tile.

Alternatives: a separate `AddonTile` (two tile designs free to drift — the repo
has already been bitten by two parallel maps for the same thing drifting, which
is what blanked the Movies tile); a protocol the tile is generic over (an
abstraction for two call sites).

### The grid is `LibraryView`'s grid; `DirectoryView` gains a layout

`DirectoryView` takes a layout, defaulting to the list so Files is untouched, and
add-on content passes the grid. Reuses the existing tile, empty state and error
handling rather than growing a second browser.

### Add-on and plugin artwork is fetched through the host's image endpoint

`Artwork` gains a route for artwork whose decoded value is not an absolute URL:
build `{scheme}://{host}:{port}/image/{original image:// value}` so Kodi serves
it. Absolute `http(s)` values keep today's direct fetch, so library artwork is
unchanged.

Alternatives: leaving it — every tile in the new grid would be a grey
placeholder, which is the point of the grid; fetching `image://` directly — no
such endpoint exists, the scheme is Kodi's texture id.

### A favourite records optional artwork

`Favorite` gains optional `art`/`thumbnail` copied from the entry it was saved
from. **Optional is load-bearing**: `FavoriteStore.load()` decodes with `try?`,
so a non-optional field would make every existing favourite fail to decode and
silently disappear — the same trap `Host.lastCheck` is guarded against. The
storage key stays `yatse.favorites.v1`; JSON written before this change decodes
with the new fields nil, and unknown keys are ignored on the way back, so
rollback is safe.

Alternatives: bumping the key — discards saved favourites for no benefit; storing
only a title — the grid has no posters.

### Favorites becomes a destination; the drawer stops expanding favourites

A `favorites` case on `ShellDestination` gives it a title, icon and row for free
(the drawer and the shortcut strip already read that type), and it is presented
with the shared grid. The drawer's per-favourite rows are removed: a drawer
cannot hold a two-column poster grid at 300pt, and one row per favourite grows
without bound. Removal moves to a long press on the tile in the grid.

### Enable/disable moves into the long-press menu

`.swipeActions` is a `List` affordance and does not exist on a `LazyVGrid`, so
converting the add-on list to a grid would silently delete the enable/disable
action. The long-press menu carries Enable/Disable and Add to/Remove from
Favorites, giving the add-on tile one place for its actions.

### Navigation memory is a per-destination pushed path held by the shell

`ShellView` keeps `[ShellDestination: [Favorite]]`; `select()` saves the outgoing
path and restores the incoming one instead of clearing. The path element stays
`Favorite` because `navigationDestination(for: Favorite.self)` is the only route
registered on the shell's stack — reusing it avoids a second route type for the
same screens.

Alternatives: persisting the memory (a stale folder path would restore to
somewhere the user no longer recognises, and only the session was asked for);
putting the memory in `Session` (it is navigation state, not host state).

### The drawer control is threaded to pushed screens

`DirectoryView` takes an optional drawer closure and shows the leading toolbar
button when it has one; `AddonsScreen` and `FilesScreen` pass theirs down and
`DirectoryView` forwards it to any `DirectoryView` it pushes. The shell already
renders the drawer above the stack — only the control was missing.

Alternatives: hoisting the drawer into the shell's chrome for every screen (a
larger change to the shell for the same result).

## Risks / Trade-offs

- **[Restoring a non-empty path in the same update that changes the stack's
  identity]** → `pushed` is restored before `destination` changes; if a
  transition glitch survives that ordering, the fallback is restoring in an
  `onChange` one frame later. **Not verifiable in CI** — needs a device report.
- **[CI cannot see any of this]** → the grid, the context menu, the drawer button
  on a pushed screen and the location restore are all visual or behavioural.
  Mitigated by unit-testing every rule that can be extracted (the video filter,
  the favourite's decode compatibility, the artwork URL shape, the destination's
  symbol) and by stating plainly what remains unverified.
- **[Four of the six listed add-ons answer the plugin root with an error]**
  (measured: JellyCon and the three PlexKodiConnect add-ons) → tiles that open an
  error screen rather than content. Mitigated by showing the host's error in place
  of the content; if the user wants those browsable, a known sub-path is a
  follow-up per add-on.
- **[Favourites saved by earlier builds have no artwork]** → placeholder tiles
  until they are saved again. Optional fields keep them valid in the meantime.
- **[A long press on a tile inside a grid must not swallow the tap that opens
  it]** → the menu is attached to the tile rather than to the link or button, and
  confirmed on device.
- **[Fewer add-ons are listed than the host has]** → a user looking for a skin or
  a scraper will not find one. This is the requested behaviour; the other types
  are one predicate away.

## Migration Plan

No stored-format break: the favourite fields are optional and the storage key is
unchanged, so an existing install keeps its favourites and the previous build
reads anything this one writes. Rollback is a revert of the commit. The IPA is
re-signed on device, so shipping the change is the same install flow as before.

## Open Questions

- Which of the four add-ons that refuse a browse at their plugin root expose a
  sub-path worth opening by default. Deferrable: the current behaviour (show the
  host's error) is honest and needs no spec or task change.
