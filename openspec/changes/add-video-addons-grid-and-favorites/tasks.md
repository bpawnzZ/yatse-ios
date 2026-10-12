# Tasks

## 1. The Addons destination lists video add-ons only

- [ ] 1.1 Add a pure `Addon.isVideoAddon` (a plugin source whose identifier is in the `plugin.video.*` namespace) plus unit tests in `KodiModelTests` asserting it is true for each of the six measured video add-ons, false for `script.pystone.benchmark`, false for a skin/scraper-style type, and false for an add-on that is not a plugin source; verify the CI "Unit tests" run passes (Swift is not compilable on the development host).
- [ ] 1.2 Rewrite `YatseRemote/UI/AddonsScreen.swift` to list only add-ons passing that rule, deleting the grouping it no longer needs (`AddonGroup`, the `groups` property and the `Section` wrapper); verify the CI "Build unsigned IPA" run compiles it.
- [ ] 1.3 Give the destination an honest empty state — it states that the host has no video add-ons rather than showing an empty grid or an error; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 1.4 Record in `AGENT.md` that video add-ons are `xbmc.python.pluginsource` with a `plugin.video.*` id on the reference host and that `xbmc.addon.video` does not occur at all, so filtering on it silently yields an empty screen; verify the note names both the rule and the measured counter-example.

## 2. Add-on and plugin artwork can be fetched

- [ ] 2.1 Add a route in `Artwork` for artwork whose decoded value is not an absolute URL — build the host's own image endpoint URL (`{scheme}://{host}:{port}/image/{original image:// value}`) instead of handing the decoded path to `URLSession`, leaving absolute `http(s)` values on the existing direct fetch; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 2.2 Unit-test the rule with the values the host actually returns: `image://%2fstorage%2f.kodi%2faddons%2fplugin.video.youtube%2ficon.png` produces a URL carrying the configured host, scheme and port, an absolute `image://http%3a%2f%2f…` value keeps its existing form, `special://home/…` is routed through the host, and an empty value produces no URL; verify the CI "Unit tests" run passes.
- [ ] 2.3 Point the add-on tile and the add-on content tile at that route, and record in `AGENT.md` the protocol trap: add-on and plugin icons decode to local paths or `special://` values, unlike library artwork which decodes to an absolute URL to the media server; verify the note names both shapes.

## 3. The shared poster tile and the grid

- [ ] 3.1 Parameterise `PosterTile` with an initialiser taking its artwork URL, title and detail line, keeping the existing `MediaItem` initialiser as a convenience over it so the library grid is unchanged; verify the CI "Build unsigned IPA" run compiles the library grid against the renamed initialiser.
- [ ] 3.2 Give `DirectoryView` a layout that defaults to the existing list, and render a two-column `LazyVGrid` of poster tiles when it is the grid; add-on content passes the grid while the Files destination keeps passing the list; verify the CI "Build unsigned IPA" run compiles it and the Files browser still renders a list.
- [ ] 3.3 Render the video add-ons from task 1 as a two-column grid of the shared tile — artwork, name and a detail line — with a placeholder when an add-on carries no artwork; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 3.4 Update the Addons wording in `README.md` and `AGENT.md` (video add-ons, the grid, the content grid); verify the described behaviour matches the code.

## 4. Favorites: stored artwork, the destination, and its grid

- [ ] 4.1 Add optional artwork to `Favorite` and copy it through `FavoriteStore.toggle`, keeping the existing `yatse.favorites.v1` key; add a persistence test asserting a stored favourite written without artwork still decodes and lists, and that saving the same place twice replaces rather than duplicates; verify the CI "Unit tests" run passes.
- [ ] 4.2 Add the `favorites` case to `ShellDestination` with its title, symbol and implemented-ness; verify the CI "Unit tests" run passes with the existing `ShellNavigationTests` symbol assertion extended to cover it.
- [ ] 4.3 Build the Favorites grid screen from the shared tile, list `favorites` in the drawer, remove the drawer's per-favourite rows, and give it an empty state that states nothing is saved; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 4.4 Offer removal from the grid, so a favourite can be deleted without leaving the destination; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 4.5 Update `README.md` and `AGENT.md` for the Favorites destination and the optional-artwork rule, recording why the new fields must stay optional; verify the note names the decode trap it protects against.

## 5. Long-press actions on add-on tiles

- [ ] 5.1 Add the long-press menu to the add-on tile and to entries inside a video add-on, offering "Add to Favorites" and, when the place is already saved, "Remove favorite", saving the displayed (markup-stripped) name and the entry's artwork; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 5.2 Move enabling and disabling into that same menu and drop the swipe action, recording in `AGENT.md` why — a grid has no swipe actions, so converting the list would have silently removed the only way to re-enable an add-on; verify the note says that and the code has no remaining `swipeActions` in `AddonsScreen`.
- [ ] 5.3 Unit-test the pure part of the save: an add-on root saves its browse path and a child folder saves its own path, the two ids differ, the title is the displayed name rather than the raw label, and saving the same entry twice yields one favourite; verify the CI "Unit tests" run passes.

## 6. The drawer while browsing, and remembering the place

- [ ] 6.1 Give `DirectoryView` an optional drawer control in its leading toolbar position, pass it from `AddonsScreen` and `FilesScreen`, and forward it to any `DirectoryView` it pushes so it survives further drill-downs; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 6.2 Replace `ShellView.select()`'s clearing of the pushed path with per-destination memory: keep each destination's pushed screens and restore them when it is selected again; verify the CI "Build unsigned IPA" run compiles it.
- [ ] 6.3 Unit-test the pure memory rule — a destination never visited yields nothing pushed, a recorded place is returned for its own destination, recording one destination leaves another's untouched, opening a favourite records that destination's place, and the rule is session-scoped rather than persisted; verify the CI "Unit tests" run passes.
- [ ] 6.4 Update `AGENT.md` for the drawer control on pushed screens and the per-destination memory, including that restoring a path in the same update as the stack's identity change cannot be proved by CI; verify the note says what remains unverified.

## 7. Integration

- [ ] 7.1 Re-run the read-only add-on probe against the live host (no `Addons.ExecuteAddon`, no `Addons.SetAddonEnabled`, no `Input.*`) and confirm the six video add-ons it lists are the ones the filter admits, recording which of them answer a browse at their plugin root; verify the recorded output matches what the filter shows.
- [ ] 7.2 Push the branch, open the PR, and confirm both `build-ipa.yml` and `tests.yml` are green on the same commit, reading the test run's failure log rather than its checkmark; report both run IDs and the test count.
- [ ] 7.3 Send the main build's IPA with `~/.local/bin/send-yatse-ipa`, and confirm the send script's hash check and read-back both pass; verify the message it reports matches the commit.

## Workflow follow-up

- Install the resulting IPA and confirm what no task above can: the add-on grid,
  the grid inside an add-on, both long-press menus, the drawer button on a pushed
  screen, returning to Addons landing on the place last visited, and the
  favourites grid rendering posters — there is no Mac in the development loop, so
  CI can compile and unit-test but cannot see the screen.
- Archive `add-now-playing-and-library-grid`, which is complete (14/14) and still
  unarchived, and archive this change once the project's review requirements are
  satisfied.
- Parked follow-ons: launching an add-on on the host (`Addons.ExecuteAddon`), a
  grid for the Files destination, and Pvr.
