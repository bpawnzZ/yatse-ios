# Proposal

## Why

The Addons destination lists every installed add-on — 68 on the reference host —
grouped by kind as text rows, so the six video add-ons the user actually browses
are buried among skins, scrapers, fonts and resource packs. Nothing inside an
add-on can be saved, and drilling into one drops the drawer: leaving for the
Remote and coming back resets the browse to the top. The device-test loop is live
again, so these are the next gaps worth closing.

## What Changes

- The Addons destination lists **only video add-ons**. Every other add-on type
  (skins, scrapers, fonts, resources, scripts, repositories) is no longer listed.
- Add-ons are presented as a **two-column poster grid**, and the content reached
  inside one is presented the same way.
- Enable/disable moves from a swipe action to the **long-press menu**, because a
  grid has no swipe actions; a disabled video add-on stays listed so it can be
  turned back on.
- A new **Favorites** destination in the drawer, presented as a two-column poster
  grid alongside the existing library grids.
- A favourite **records the artwork** of the place it was saved from, so the grid
  renders posters; a favourite saved before this change has no artwork and renders
  the placeholder tile.
- **Long-press inside a video add-on** offers Add to Favorites, and Remove
  favorite when that place is already saved.
- The **drawer control is available on screens pushed inside a destination**, not
  only on the destinations themselves.
- Selecting a destination **remembers the screens pushed within it**, so returning
  to Addons — or any other destination — restores the place last visited instead
  of clearing it.
- Correct the `app-shell` requirement that still names Files and Addons as
  unimplemented; both shipped (PRs #8 and #9) and only Pvr remains.

## Capabilities

### New Capabilities

- `video-addons`: what the Addons destination lists, and how the add-ons and the
  content inside them are presented and acted on.
- `favorites`: saved places — the drawer entry and its grid, the artwork a
  favourite carries, and adding or removing one from the browse.

### Modified Capabilities

- `app-shell`: the drawer gains a Favorites entry; selecting a destination
  remembers rather than clears the screens pushed within it; the drawer control is
  reachable from a pushed screen; and the unimplemented-destinations requirement
  is corrected to Pvr alone.

## Impact

- `YatseRemote/UI/AddonsScreen.swift` — the video-only filter, the grid, the
  long-press menu.
- `YatseRemote/UI/LibraryView.swift` — `PosterTile` gains an initialiser that does
  not require a `MediaItem`; `DirectoryView` gains a layout and the optional
  drawer control; a Favorites grid screen.
- `YatseRemote/UI/AppDrawer.swift` — the Favorites destination and its row.
- `YatseRemote/Core/Favorites.swift` — optional artwork on a favourite.
- `YatseRemote/Core/KodiModels.swift` — `Addon.isVideoAddon`; the add-on icon URL
  route.
- `YatseRemote/UI/ShellView.swift` — the per-destination pushed path.
- No new dependency and no new Kodi method: `Addons.GetAddons`,
  `Addons.SetAddonEnabled` and `Files.GetDirectory` are already in use.
- `Favorite` gains **optional** fields, so stored JSON stays decodable under the
  existing key. A non-optional field would silently drop every saved favourite —
  the failure mode `Host.lastCheck` already documents.
- Not changed: the Files destination keeps its list, Pvr stays a placeholder, and
  launching an add-on (`Addons.ExecuteAddon`) is still not implemented.
- `library-browsing` behaviour is unchanged (Files remains a list); what this
  change reuses is shared infrastructure — `PosterTile` and `DirectoryView`.
  `add-now-playing-and-library-grid`, which owns that delta spec, is complete but
  still unarchived; archiving it is independent of this change.
