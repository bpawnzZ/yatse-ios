# AGENT.md — working notes for this repo

Durable handoff notes. **Read this before touching the project**, and keep it
current: it is the only on-disk record of why things are the way they are.

`YatseRemote` is a clean-room SwiftUI iOS remote for Kodi, built from static
analysis of the Android Yatse 12.0.0 APK plus the public Kodi JSON-RPC docs. No
decompiled code bodies are copied. See `README.md` and `docs/CLEANROOM.md`.

---

## Current state (2026-10-11, last update)

- **`main` HEAD `aaf982f`** — "real artwork transparency, a bar that appears on
  play, and browsable addons (#9)".
- **Latest green runs:** build `38189133360` (main, post-merge) and tests
  `38188627860` → **98 tests, 0 failures**. Previous milestone PR #8 = `756f62c`
  (93 tests), #7 = `9513833` (76 tests).
- **Latest IPA sent to Alpha's Telegram:** message 453 in `hermes_2` topic 7
  (build `38189133360`, 1,958,909 bytes). Re-sends are fine; the send script
  verifies the hash before uploading.
- **There is no Swift toolchain on this box.** `which swiftc` is empty. CI is the
  only compiler: never claim a Swift change builds, or a test passes, until a run
  says so. A green build is `xcodebuild` on a GitHub macOS runner, not a local
  check.
- **On-device testing has started** (previously this file said it had not). Alpha
  installs the IPA and reports what he sees; that loop has already found four real
  bugs this file records: the invisible Movies icon, the now-playing bar not
  appearing on play, artwork buried under the backdrop blur, and `Files`
  failing on every call. **Nothing visual is verified until he says so** — CI can
  compile and unit-test, and cannot see the screen.
- Repo is **private**. macOS runner minutes bill at a **10× multiplier** (GitHub
  Free: 2,000 min/month ≈ 200 macOS minutes). Every commit to `main` — even a
  docs-only one — burns a macOS run, because there is no `paths-ignore`.
  Flipping the repo public makes macOS minutes free.
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
  the current destination, `.id(destination)` so changing destination clears
  pushed detail screens, `PlaybackBar` as a `.safeAreaInset(edge: .bottom)`, and
  the drawer as a ZStack overlay. Destinations are selected by value, not pushed;
  favourites that are *places inside* a destination are pushed.
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
  window, not a destination), the Favorites section, and the header's mic/search
  buttons (both still open `PlaceholderSheet` — library search is not
  implemented). `RemoteShortcut` **delegates its icon and title to the
  destination it points at** — they used to be two separate maps that drifted,
  which is how the Movies tile went blank.
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
- `YatseRemote/UI/AddonsScreen.swift` — `Addons.GetAddons` grouped by type. A
  **plugin add-on opens like a folder**: its row is a `NavigationLink` into
  `DirectoryView(path: addon.browsePath)` where `browsePath` is
  `plugin://<addonid>/`. Enable/disable is a **swipe action** — the tap means
  "open" now, and a switch on every row buried that. Add-ons with no browsable
  tree (skins, scrapers, fonts) stay plain rows. `enabled`/`broken` are real
  booleans on Kodi 19+ (confirmed live on 21.3); disabled add-ons must stay
  listed or the switch could never be turned back on.
- `YatseRemote/Core/Favorites.swift` — `Favorite` / `FavoriteTarget` /
  `FavoriteStore` (UserDefaults key `yatse.favorites.v1`). A target's `id` is
  derived from the target, so the same place cannot be saved twice and the star
  knows filled from outline. A section favourite switches destination; anything
  deeper is pushed onto the shell's path.
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
7. **Consider `paths-ignore` on both workflows** so docs-only commits stop burning
   a 10× macOS run.
