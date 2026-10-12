# AGENT.md — working notes for this repo

Durable handoff notes. **Read this before touching the project**, and keep it
current: it is the only on-disk record of why things are the way they are.

`YatseRemote` is a clean-room SwiftUI iOS remote for Kodi, built from static
analysis of the Android Yatse 12.0.0 APK plus the public Kodi JSON-RPC docs. No
decompiled code bodies are copied. See `README.md` and `docs/CLEANROOM.md`.

---

## Current state (2026-10-11, last update)

- **`main` moves with every merge: read `git log --oneline -5` instead of
  trusting a hash written here.** This file deliberately no longer pins a HEAD
  sha or run IDs — they went stale within a day, and a stale handoff is worse
  than none. `gh run list --limit 5` is the live answer.
- **Last recorded test count: 117 passing, 0 failures** (PR #11). The suite grows
  with every change; the PR's "Unit tests" run is the current number. Milestones:
  #10 = 113, #9 = 98, #8 = 93, #7 = 76.
- **The repo is public** since 2026-10-12, so macOS runner minutes are no longer
  billed at the private-repo 10× rate. Batching pushes is still polite, not
  expensive.
- **The latest IPA sent to Alpha's Telegram:** message 457 in `hermes_2` topic 7
  (main `22d4d02`, PR #11). Re-sends are fine; the send script verifies the hash
  before uploading.
- **There is no Swift toolchain on this box.** `which swiftc` is empty. CI is the
  only compiler: never claim a Swift change builds, or a test passes, until a run
  says so. A green build is `xcodebuild` on a GitHub macOS runner, not a local
  check.
- **On-device testing is the loop that finds real bugs.** Alpha installs the IPA
  and reports what he sees; that loop has already found the invisible Movies
  icon, the now-playing bar not appearing, artwork buried under the blur, `Files`
  failing on every call, and the Pvr-sized assumptions about add-ons. **Nothing
  visual is verified until he says so** — CI can compile and unit-test, and cannot
  see the screen.
- Repo is **public** since 2026-10-12, so GitHub's free macOS runner minutes apply
  (a public repo is not billed the private-repo **10× multiplier**). Every commit to
  `main` — even a docs-only one — still *runs* a build, because there is no
  `paths-ignore`; it is just no longer expensive.
- Open items are listed at the end under **Next steps**.

## How work ships here

Follow this exactly; the trigger behaviour is not obvious and cost real time.

```bash
# 1. Branch
git checkout -b fix/short-description

# 2. Commit, push the branch
git push -u origin fix/short-description

# 3. PUSHING A BRANCH RUNS NOTHING. Open a PR — that is the trigger.
gh pr create --base main --title "…" --body-file -
#    build-ipa.yml: push to main, tags v*, pull_request → main, dispatch
#    tests.yml:     pull_request → main, dispatch  (NO push trigger)

# 4. Watch the tests, then the build
gh run list --branch fix/short-description --limit 2
gh run watch <run-id> --exit-status

# 5. A red run: read the actual failure, do not guess
gh run view <run-id> --log-failed | grep -E "error:|XCTAssert"

# 6. Merge (squash — matches the existing history), which triggers the main build
gh pr merge <n> --squash --delete-branch
git checkout main && git pull --ff-only

# 7. When the main build is green, send that build's IPA
~/.local/bin/send-yatse-ipa <main-build-run-id> "main <sha> · PR #N — what changed"
```

Rules that go with it:

- **`tests.yml` never runs on a `main` push.** Tests only run for a PR or a manual
  dispatch, so a green `main` build alone does *not* mean tests passed for that
  commit — check the PR's test run.
- **Tests must be non-vacuous.** The suite has been red before (5 failures on the
  first simulator run, catching two real defects) and that is what makes it
  worth anything. When you add a rule, add the case that fails if the rule
  breaks, and prefer a test over a comment for anything the compiler cannot see
  (an SF Symbol name, a JSON-RPC field name).
- **Unit-tested rules over inspection, where a rule exists.** Pure helpers
  (`MiniPlayer.isVisible`, `ControlPadMetrics`, `TouchpadGestureResolver`,
  `TimeText.mmss`, `AppModel.resolvedPlayer`, `ShellDestination`) exist so the
  decision can be tested without a host.
- **Nothing visual ships unverified.** Say plainly what CI proved and what it
  cannot; do not describe a UI change as working.
- `dist/YatseRemote-unsigned.ipa` is gitignored and local — the artifact is
  re-signed on device (SideStore / AltStore / Sideloadly).

## App structure

The UI is host-centric and the player state lives above the navigation stack.

- `YatseRemote/App/Session.swift` — `@MainActor ObservableObject` owning the
  active `Host`, its password and its `AppModel`. `activate(host:password:)`
  connects (re-selecting the same host is a no-op); `deactivate()` tears down;
  `reconcile(with:)` drops the session when the active host is deleted. **The
  `AppModel` must not move back into a screen** — a `@StateObject` in `RemoteView`
  was destroyed on `onDisappear`, which is why playback could not persist.
- `YatseRemote/UI/RootView.swift` — branches on `Session.model`: nil → the host
  picker in a `NavigationStack`; non-nil → `ShellView`.
- `YatseRemote/UI/ShellView.swift` — the shell: one `NavigationStack(path:)` for
  the current destination, `.id(destination)` so changing destination rebuilds
  the stack, `PlaybackBar` as a `.safeAreaInset(edge: .bottom)`, and the drawer as
  a ZStack overlay. Destinations are selected by value, not pushed; favourites
  that are *places inside* a destination are pushed. It also owns
  **`NavigationMemory`**: the screens pushed within each destination, so leaving
  Addons for the Remote and coming back restores the folder you were in instead of
  resetting to the root. `select()` records the outgoing destination's path and
  restores the incoming one's — it no longer does `pushed.removeAll()`, which is
  what used to reset every destination on every switch. Session-scoped (`@State`,
  never persisted), and unit-tested, because "never visited", "sits at its root"
  and "holds a place" have to answer differently.
- **Pushed screens carry the drawer control.** `DirectoryView` and `ChildrenView`
  take an optional `onOpenDrawer` and show the leading button when they have one,
  so the drawer is reachable while drilled into an add-on rather than only from a
  destination's root. `AddonsScreen`/`FilesScreen`/`LibraryView` pass theirs down,
  and `DirectoryView` forwards it to any `DirectoryView` it pushes.
- **`PlaybackBar` is a separate view for a reason.** `safeAreaInset`'s closure is
  re-evaluated only when its *owner* invalidates, and `ShellView` takes the model
  as a plain parameter while observing only `Session`. Reading
  `model.activePlayer` in that closure therefore never re-ran it and the bar
  appeared only after navigating away and back. Anything the inset renders that
  depends on an observable belongs in a view that owns `@ObservedObject`; an
  `.animation(value:)` in the parent cannot fix it, because the parent never
  re-evaluates.
- `YatseRemote/UI/AppDrawer.swift` — `ShellDestination` (the single source of
  truth for a destination's title/icon/implemented-ness, also carrying
  `librarySection`), `RemoteShortcut` (the five quick links; Pictures is a Kodi
  window, not a destination), and the header's mic/search buttons (both still open
  `PlaceholderSheet` — library search is not implemented). **Favorites is a
  destination, not an expanded list**: the drawer used to draw one row per saved
  favourite, which grows without bound and cannot hold a poster grid at 300pt, so
  it is now a single row opening the Favorites screen and removal happens on the
  tile. `RemoteShortcut` **delegates its icon and title to the destination it
  points at** — they used to be two separate maps that drifted, which is how the
  Movies tile went blank.
- `YatseRemote/UI/RemoteTheme.swift` — **every colour lives here.** Tokens:
  background, **surface**, tile fill, tile fill pressed, accent, icon, nav bar
  fill, divider, bar fill, artwork scrim, **artwork blur**, corner radius, with
  `.blue` and `.dark` presets. `.themedRoot()` injects the selected preset at the
  app root (`@AppStorage` key `remoteTheme`, switched in Settings → Appearance);
  `.themedScreen()` paints a whole screen — page background, icon colour, accent
  tint and a matching navigation bar — so a screen is themed in one line.
  **Views must not hardcode colours**; read `@Environment(\.remoteTheme)`.
  Transparency is `artworkBlur` + `artworkScrim`: blur was the real reason
  artwork read as a coloured wash (30 → 12), not the scrim (0.40 → 0.05).
- `YatseRemote/UI/RemoteScreen.swift` — the single-screen Remote. Also holds
  `QueueSheet`, `TextEntrySheet` and the pure `ControlPadMetrics`. **The Remote
  does not scroll**: status/shortcut/volume/utility rows are pinned and the pad
  takes `maxHeight: .infinity`; `ControlPadMetrics.side(in:reserved:)` sizes the
  square pad to `min(width, height − reserved)` (unit-tested, because the number
  is not visible in CI).
- `YatseRemote/UI/NowPlayingView.swift` — the full-screen Now Playing overlay,
  presented from `ShellView` via `.fullScreenCover` (not from `MiniPlayer`; the
  mini-player stays a pure strip). Holds `NowPlayingInfoView` and the pure
  `TimeText.mmss`. Stream pickers send each stream's own `index` (never the row
  offset); subtitles-off sends the string `"off"` via `SubtitleSelection`. The
  video control sends `Input.ExecuteAction {"action":"aspectratio"}` — confirmed
  present in the live box's action enum with a read-only `JSONRPC.Introspect`.
- `YatseRemote/Core/LibraryCatalog.swift` — `LibrarySection.layout`
  (`grid` for movies/tvshows, `list` for artists/albums) drives `LibraryView`;
  `PosterTile` + `PosterImage` (2:3) render the grid; `ChildrenView` stays a list.
  `FilesScreen` + `DirectoryView` live in `LibraryView.swift` — `Files.GetSources`
  → `Files.GetDirectory`, folders drill down, leaves play, and the **star button
  saves the current location** (`FavoriteButton`, shared with the library and the
  drill-downs so "favourite" means one thing everywhere).
- `YatseRemote/UI/AddonsScreen.swift` — the Addons destination: **video add-ons
  only**, as a two-column poster grid. `Addon.isVideoAddon` is the filter (see
  *Protocol rules* for why the obvious type does not work). Tapping a tile opens
  `DirectoryView(path: addon.browsePath)`, which is a grid because the path is
  `plugin://…`. **Enable/disable and "Add to Favorites" are both in the
  long-press menu, not a swipe action** — a `LazyVGrid` has no swipe actions, so
  converting the list would have silently removed the only way to re-enable an
  add-on. A disabled add-on must stay listed for the same reason. Add-ons with no
  browsable tree are no longer reachable here at all: they are not video add-ons.
- `YatseRemote/UI/LibraryView.swift` also holds `FavoritesScreen` (the Favorites
  destination, the same grid) and `FavoriteMenuItem` (the long-press "Add to
  Favorites" / "Remove favorite" entry, shared with the add-on grid so the gesture
  means one thing everywhere).
- **`PosterTile` is parameterised, not `MediaItem`-typed.** It takes
  (artwork URL, title, detail) and keeps a `MediaItem` initialiser as a
  convenience, so the library, add-on, favourite and directory grids render one
  tile. A second tile type would be free to drift — which is how the Movies tile
  once went blank.
- **`DirectoryView` decides its own layout from the path**:
  `DirectoryView.layout(forPath:)` is `.grid` for `plugin://…` and `.list`
  otherwise. That is why the Files browser is unchanged and add-on content is a
  grid without any caller passing a flag — and why a favourite saved on a plugin
  folder reopens the way it was saved.
- `YatseRemote/Core/Favorites.swift` — `Favorite` / `FavoriteTarget` /
  `FavoriteStore` (UserDefaults key `yatse.favorites.v1`). A target's `id` is
  derived from the target, so the same place cannot be saved twice and the star
  knows filled from outline. `Favorite` also carries **optional** `art` /
  `thumbnail` so the Favorites grid shows posters — optional is load-bearing, see
  the trap below. A section favourite switches destination; anything deeper is
  pushed onto the shell's path.
- `YatseRemote/UI/DiagnosticsView.swift` + `Core/Diagnostics.swift` — the
  per-layer host self-check. Its reachability probe counts **HTTP 401 as success**
  (the host answered), which is the only way to distinguish "nothing listening"
  from "slow" within the same timeout.
- `YatseRemote/UI/HomeScreen.swift`, `SettingsView.swift`,
  `PlaceholderScreen.swift` — Home, Settings/About, and the honest placeholder
  (now only `pvr`; `files` and `addons` are implemented).
- `YatseRemote/UI/Touchpad.swift` — `TouchpadGestureResolver` is pure and
  unit-tested; the view is a thin shell over it.
- `HostsView` gained `HostsMode` (`connect` picker vs `manage`) and no longer owns
  a `NavigationStack`; `LibraryView` is `LibraryView(model:section:onOpenDrawer:)`.
- **`AppModel.send` is result-agnostic** (`IgnoreResult`): Kodi answers some
  methods with `"OK"` and others with a boolean (`GUI.SetFullscreen`), so a fixed
  `String` decode used to throw `malformedResponse` on half of them.
- **Remote button rows** — originally APK-faithful from
  `decompiled/resources/res/layout/fragment_remote.xml` (+ handler `bf/a4.java`):
  row 1 = Volume-Down, Mute, Volume-Up; row 2 = Fullscreen (`remote_display`),
  Info, Keyboard, Context (`remote_context`, which uses the list icon and sends
  `Input.ExecuteAction contextmenu`). The 2026-10-11 restyle deliberately moved
  **Back out of row 2** to a bare `arrow.left` at the bottom-left, and put
  **Subtitles** in its place (`Player.SetSubtitle next`), so row 2 is now
  Subtitles / Fullscreen / Info / Keyboard / Context. The d-pad is
  up/left/select/right/down with chevrons in the accent colour and a tiled select
  instead of the old floating ring, with the touchpad toggle bottom-right.
  **Yatse's Remote has no subtitle and no queue button** — those are Now
  Playing-page controls here, surfaced in the `NowPlayingView` overlay.
- **A stroked `Circle()` hit-tests only the ring.** The Remote's select control is
  `Circle().strokeBorder(...)`, so it needs `.contentShape(Circle())` or a tap in
  the middle misses. (This was a real on-device bug.)

## Protocol rules that came from live probing

Every one of these was measured against the live box, not inferred. Re-probe
rather than re-guess; the harnesses are listed below.

- **A mistyped SF Symbol name is invisible, not an error.** It draws nothing while
  the button stays tappable — which is exactly how the Movies shortcut broke (a
  blank tile that still navigated). `ShellNavigationTests` asserts every
  `ShellDestination`, `RemoteShortcut` and `LibrarySection` symbol resolves via
  `UIImage(systemName:)`. Keep it that way: this is the bug class neither the
  compiler nor a view test can see.
- **`Files.GetDirectory`: `filetype` and `label` are output-only.** Kodi returns
  both whether or not you ask. Name either in `properties` and Kodi rejects the
  entire call with `-32602 Invalid params.` — the *same* error a non-existent
  plugin gives, so it reads as "bad addon" instead of "bad request". Every other
  field tried (`title`, `file`, `thumbnail`, `art`, `runtime`, `playcount`,
  `year`) was accepted. `KodiClient.directoryProperties` is the single place that
  list lives and `KodiModelTests` fails if an output-only field is added back.
- **Add-on content browses like a folder.** `Files.GetDirectory` on
  `plugin://<addonid>/` returns real entries (the live YouTube addon answers 21,
  nested `plugin://…?query` paths included), so `DirectoryView` recurses through
  add-on content with no special handling; `media` accepts `files`/`video`
  interchangeably here. **There is no JSON-RPC method that "opens an add-on"** —
  `Addons.ExecuteAddon` launches it *on the box*; browsing is a file walk.
- **A "video add-on" is a plugin source whose id starts `plugin.video.`, not a
  `xbmc.addon.video`.** Measured on the live box: all 68 installed add-ons were
  binned by `type`, and **`xbmc.addon.video` does not occur at all** — every video
  add-on answers `xbmc.python.pluginsource` (YouTube, JellyCon, PlexKodiConnect
  ×3, TMDb Helper). A filter on the type therefore lists **nothing**, and it fails
  silently: an empty screen, not an error. `Addon.isVideoAddon` is
  `isBrowsable && addonid.hasPrefix("plugin.video.")`, and `script.pystone.benchmark`
  is the measured counter-example — a plugin source that is not a video add-on.
  `Addons.GetAddonDetails` does report `extrainfo: provides = "video audio"`, but
  it is one extra round trip per add-on, so it is not worth a list screen.
- **Add-on and plugin artwork is not fetchable the way library artwork is.**
  Library art decodes to an absolute `http://<media server>` URL and is fetched
  directly. Add-on art arrives as `image://%2fstorage%2f.kodi%2faddons%2f…%2ficon.png`,
  which decodes to a **local filesystem path**, and plugin entries decode to
  `special://home/…` — neither is a URL the device can request, so before this
  change every add-on and plugin tile silently fell back to the placeholder. They
  are served by the host's own image endpoint instead: `Artwork.url(_:host:)`
  builds `{scheme}://{host}:{port}/image/{original value}` for anything that is
  not already absolute, passing Kodi's value through as it arrived (it is already
  percent-encoded for exactly that request). Absolute values keep going direct.
  Only the library and the add-on grids use the host-aware overload so far — the
  Files list still resolves folders through the old path and still shows
  placeholders for `image://DefaultFolder.png`-style icons.
- **Plugin labels carry Kodi markup.** The live YouTube addon answers
  `[B]My Subscriptions[/B]`. `String.strippingKodiMarkup` strips the real tag list
  (deliberately not any `[word]`, so `[REC]` survives) and `MediaItem.heading`
  applies it, so every row benefits rather than each view remembering.
- **`System.FriendlyName` does not exist in Kodi 21.3** (`-32601`), even though
  Yatse's DEX still references it. Server identity comes from
  `Application.GetProperties`.
- **Kodi's `currentsubtitle` is `{}`**, not absent and not null, when no subtitle
  is selected. A strict decoder throws on it.
- **`artist` is a string in `AudioLibrary.GetArtists` and an array in
  `GetSongs`/`GetAlbums`.** `StringList` exists for exactly this.
- **Artwork 401s without Basic auth**, so `AsyncImage` cannot be used; see
  `ArtworkImage` / `ArtworkLoader` (shared cache, shared auth path).
- **`ListPayload.limits` requires `start`, `end` and `total`.** Kodi always sends
  the full object, so the strict decode is right and a *test fixture* that omits
  one is the thing that is wrong.
- **SSDP discovery is impossible for a free-signed build** — iOS gates
  `239.255.255.250:1900` behind `com.apple.developer.networking.multicast`.
  Bonjour is used instead, which needs no entitlement.
- **`Host.lastCheck` must stay optional.** `HostStore.load()` decodes persisted
  hosts with `try?`, so adding a *non-optional* field to `Host` makes every saved
  host fail to decode and silently produces an empty list, guarded by
  `HostPersistenceTests.testDecodesPreChangeHostsWithoutLastCheck`.
- **A new field on `Favorite` must be optional for the same reason.** The artwork
  fields are optional, and `FavoritesTests` asserts that a favourite encoded with
  no artwork keys — what an earlier build wrote — still decodes. Making either
  non-optional would drop every favourite already saved, without an error.
- **A `LazyVGrid` has no swipe actions.** `.swipeActions` is a `List` affordance.
  Converting a list to a grid therefore deletes any swipe action silently, which
  is why the add-on enable/disable action moved into the long-press menu; that is
  also the only remaining way to re-enable a disabled add-on, so it must not be
  dropped again.
- **A screen pushed inside a destination must be pushed by value.**
  `NavigationLink { Destination }` (the closure form) never enters `pushed`, and
  `.id(destination)` rebuilds the stack on every destination switch — so a
  closure-built screen is discarded and `NavigationMemory` has nothing to restore.
  This repo shipped that bug: the drill-downs were all closure-form, so only
  favourites (the single value push) came back. Every drill-down — library rows
  and grid cells, Files sources, add-on content and nested folders — is now
  `NavigationLink(value: Favorite…)` against the one
  `navigationDestination(for: Favorite.self)`. Add a new one the closure way and
  it silently stops remembering its place.
  Ceiling: a pushed value's identity is the *target*, so a folder reached twice in
  one stack carries a duplicate value. Untested on device — if a push into an
  already-pushed folder ever does nothing, that is this, and the fix is a
  push-scoped wrapper type around `Favorite` rather than the stored value itself.

## Known open defect (not fixed on purpose)

**WebSocket JSON-RPC is not on the HTTP port on this box.** An HTTP `Upgrade`
request to `:8080/jsonrpc` returns **HTTP 200**; only `:9090/jsonrpc` returns
**HTTP 101** (confirmed with `curl -u` against Kodi 21.3). `Host.socketURL` builds
`ws://…:<http port>/jsonrpc`, so the in-app notification probe fails where
`check-host.py` passes, because the script tries the configured port then falls
back to `9090`. The self-check reports it honestly as a notification-layer
failure. Fixing `Host.socketURL` (probe 9090, fall back) is a small, well-defined
next task — it was left out of `add-connection-diagnostics` as out of scope.
Live updates are not required for the app to work: a 1 Hz ticker re-queries
`Player.GetActivePlayers`, which is what keeps the now-playing bar honest.

## Reverse-engineering inputs (outside this repo)

```
~/reverseEngineer/yatse/
  org.leetzone...apk          Yatse 12.0.0, sha256 40746f8f84c6e9ac22…
  decompiled/                 6,434 .java from jadx (50 MB, 222 decompile errors)
  probe_jsonrpc.py            live payload validation harness (11/12 accepted)
  probe-evidence.txt          its output against Kodi 21.3
  probe_addons.py             add-on inventory: types, enabled flags, details
  probe_plugin_browse.py      does plugin:// browse? which media?
  probe_shapes.py             which Files.GetDirectory properties are accepted
  probe-*-evidence.txt        the recorded output of each (the evidence)
  REPORT.md                   the specification this app was built from
```

Re-run any of them (all read-only — no `Input.ExecuteAction`, no playlist
mutation, no add-on launch), so they are safe against the live box:

```bash
cd ~/reverseEngineer/yatse && python3 probe_jsonrpc.py
cd ~/reverseEngineer/yatse && python3 probe_shapes.py     # the property trap
```

They talk to Kodi at `10.13.13.7:8080` with Basic auth; credentials are in
`probe_jsonrpc.py` and the newer probes import them from there rather than
duplicating the secret.

APK findings that shaped the add-ons screen: `Addons.GetAddonDetails`,
`Addons.ExecuteAddon`, `Addons.SetAddonEnabled`, plural `str_addons_enable` /
`str_addons_disable` plus singular `str_addon_enable` / `str_addon_disable`
strings, and hard-coded `plugin://plugin.video.*/…` paths — i.e. Yatse both
**browses** and **launches** add-ons. Launching (`Addons.ExecuteAddon`) is not
implemented here yet.

## Host connection check (development host)

`scripts/check-host.py` runs the same ordered, read-only probe sequence the app
implements — reachability → credentials/identity → library read → artwork →
notification channel → server compatibility — one layer per probe, against a
live Kodi.

```bash
export KODI_HOST=http://10.13.13.7:8080   # host[:port] only; no credentials here
export KODI_USER=kodi                      # from ~/reverseEngineer/yatse/probe_jsonrpc.py
export KODI_PASS=...
python3 scripts/check-host.py              # exit 0 = all probes passed; non-zero on failure
```

- Credentials are **environment-only** (`KODI_HOST`, `KODI_USER`, `KODI_PASS`):
  no default, no placeholder, never committed. Missing any → exit 2 with a clear
  message.
- Read-only: the method set is frozen and the script refuses anything outside it
  (`Input.*`, playlist mutation, settings writes, volume/mute are absent).
- Last recorded live run output:
  `openspec/changes/add-connection-diagnostics/live-probe-output.txt`.

## OpenSpec state

`openspec/` is initialised **inside this repo** — the nearest ancestor root is
`/home/insomnia`, which belongs to a different product, so an uninitialised
`openspec` in this repo would have filed changes into the wrong project. Always
run `openspec` from the repo root.

- `changes/archive/2026-10-11-add-connection-diagnostics` — applied and archived
  (`specs/connection-diagnostics`).
- `changes/archive/2026-10-11-add-app-shell-navigation` — applied and archived
  (`specs/app-shell`).
- `changes/add-now-playing-and-library-grid` — **complete (14/14) but not yet
  archived.**
- The diagnostics change also left `APPLY-PROMPT.md` **inside its archive
  directory** (`changes/archive/2026-10-11-add-connection-diagnostics/`), the
  brief handed to a coding agent — that file is where the agent-to-agent
  messaging protocol lives (artifact handoff over chat, four required fields per
  message, no peer self-report counted as evidence).

## Traps that already cost time

- **`runner.temp` is not a valid context at workflow level.** Putting
  `${{ runner.temp }}` in a top-level `env:` makes the whole workflow file
  unparseable and the run dies at **0s** with only "This run likely failed
  because of a workflow file issue". Set `DERIVED="$RUNNER_TEMP/DerivedData"`
  inside each `run:` step instead. Workflow-level `env:` accepts only
  `github`, `secrets`, `inputs`, `vars`.
- **Version pinning of actions:** `actions/checkout` and
  `actions/upload-artifact` are on **v7** now. Older majors still resolve but
  warn.
- **One Swift type error was the whole build failure**: exit code 65 from
  `xcodebuild` means a compile error; get the real message with
  `gh run view <id> --log-failed | grep "error:"`.
- **A push to a feature branch runs no CI at all** — open the PR (see *How work
  ships here*).
- **The only warning the build emits** is the AppIntents "Metadata extraction
  skipped" note. If the count is 1, nothing was introduced; compare against a
  previous run rather than reading "1 warning" as a regression.

## Copy-paste verification

```bash
# CI status
gh run list --repo bpawnzZ/yatse-ios --limit 5

# build + install the artifact locally for inspection
RID=$(gh run list --repo bpawnzZ/yatse-ios --workflow build-ipa.yml \
      --limit 1 --json databaseId --jq '.[0].databaseId')
rm -rf /tmp/ipa-check && mkdir -p /tmp/ipa-check
gh run download "$RID" --repo bpawnzZ/yatse-ios -n YatseRemote-unsigned-ipa -D /tmp/ipa-check
cd /tmp/ipa-check
unzip -t YatseRemote-unsigned.ipa
sha256sum -c <(awk '{print $1"  YatseRemote-unsigned.ipa"}' YatseRemote-unsigned.ipa.sha256)
unzip -l YatseRemote-unsigned.ipa | grep -E '_CodeSignature|embedded.mobileprovision' \
  && echo "FAIL: still signed" || echo "clean"

# protocol probe against a live Kodi
cd ~/reverseEngineer/yatse && python3 probe_jsonrpc.py

# tests (PR only) — read the failure, never the checkmark
gh run view <test-run-id> --log-failed | grep -E "error:|XCTAssert"
gh run view <test-run-id> --log | grep "Executed .* tests"

# send a built IPA to Alpha's Telegram (hash-verified, read-back confirmed)
~/.local/bin/send-yatse-ipa <run-id> "main <sha> · PR #N — what changed"
```

## Next steps

1. **Install and drive it on device.** Re-sign `dist/YatseRemote-unsigned.ipa`
   (SideStore / AltStore / Sideloadly), host `10.13.13.7` port `8080` user
   `kodi`. Accept the local-network prompt — if it is declined, discovery and
   JSON-RPC both fail silently (Settings → Privacy → Local Network).
2. **Verify the items CI cannot**: the four recent device fixes (artwork
   transparency, the bar appearing on play, the Movies tile, add-on browsing) and
   everything else visual. Treat every UI change as unproven until Alpha confirms.
3. **Fix `Host.socketURL`** to try `9090` and fall back — see *Known open defect*.
   Small and well-defined; it is what makes live-update push work.
4. **Launch add-ons, not just browse them.** `Addons.ExecuteAddon` runs an add-on
   on the box; Yatse does this. Not implemented.
5. **`pvr` is the last placeholder** destination. Also unimplemented and
   deliberately so: Plex/Emby/Jellyfin backends, DLNA casting, offline
   download/transcode, and the APK's custom-command editor (~80 lines, omitted).
6. **Archive `add-now-playing-and-library-grid`** in openspec (it is complete).
7. **Consider `paths-ignore` on both workflows** so docs-only commits stop running
   a build. No longer urgent — the repo is public, so those runs are free — but it
   still shortens the feedback noise on a docs change.
