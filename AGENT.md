# AGENT.md — working notes for this repo

Durable handoff notes. Read this before touching the project.

## Current state (2026-10-11)

- **IPA builds green on CI and has been verified by hand.** Run `38116012941`
  on `bpawnzZ/yatse-ios` (private). Artifact: `YatseRemote-unsigned-ipa`.
- Verified on the downloaded artifact, not from the checkmark:
  - `unzip -t` clean; `Payload/YatseRemote.app/` present
  - Mach-O 64-bit **arm64** (`magic 0xfeedfacf`, `cputype 0x100000c`)
  - **no** `_CodeSignature` / `embedded.mobileprovision` entries
  - `sha256` matches the published `.sha256`
  - `MinimumOSVersion 17.0`, `DTSDKName iphoneos26.5`, `DTXcode 2660` (Xcode 26.6)
  - `NSAppTransportSecurity → NSAllowsLocalNetworking = true`
  - `NSBonjourServices = [_xbmc-jsonrpc-h._tcp, _xbmc-jsonrpc._tcp]`
- Unit tests run in `.github/workflows/tests.yml` (simulator, opt-in/dispatch) —
  separate from the IPA build so a flaky simulator run can never block shipping.
- Repo is **private**. macOS runner minutes bill at a 10× multiplier on private
  repos (GitHub Free: 2,000 min/month → ~200 macOS minutes). Flip to public for
  free macOS minutes if that matters more than the visibility.
- The app has **not** been run on a physical device yet. Everything so far is
  compile-verified, unit-tested and artifact-verified.

## App shell (add-app-shell-navigation)

The UI is host-centric and the player state lives above the navigation stack.

- `YatseRemote/App/Session.swift` — `@MainActor ObservableObject` owning the
  active `Host`, its password and its `AppModel`. `activate(host:password:)`
  connects (re-selecting the same host is a no-op); `deactivate()` tears down;
  `reconcile(with:)` drops the session when the active host is deleted. **The
  `AppModel` must not move back into a screen** — a `@StateObject` in `RemoteView`
  was destroyed on `onDisappear`, which is why playback could not persist.
- `YatseRemote/UI/RootView.swift` — branches on `Session.model`: nil → the host
  picker in a `NavigationStack`; non-nil → `ShellView`.
- `YatseRemote/UI/ShellView.swift` — the shell: one `NavigationStack` for the
  current destination, `.id(destination)` so changing destination clears pushed
  detail screens, the mini-player as a `.safeAreaInset(edge: .bottom)`, and the
  drawer as a ZStack overlay. Destinations are selected by value, not pushed.
- `YatseRemote/UI/AppDrawer.swift` — `ShellDestination` (the single source of
  truth for a destination's title/icon/implemented-ness) and `RemoteShortcut`
  (the five quick links; Pictures is a Kodi window, not a destination). The
  drawer and the shortcut strip both read `ShellDestination`, so they cannot
  drift — guarded by `ShellNavigationTests`.
- `YatseRemote/UI/MiniPlayer.swift` — `isVisible(activePlayer:)` is the pure
  visibility rule.
- `YatseRemote/UI/RemoteScreen.swift` — the rebuilt single-screen Remote (was
  `RemoteView.swift`). Also holds `QueueSheet`, `TextEntrySheet` and the pure
  `ControlPadMetrics`. **The Remote does not scroll**: status/shortcut/volume/
  utility rows are pinned and the pad takes `maxHeight: .infinity`;
  `ControlPadMetrics.side(in:reserved:)` sizes the square pad to
  `min(width, height − reserved)` so it fills the free space without overflowing
  (unit-tested, because the number is not visible in CI).
- `YatseRemote/UI/NowPlayingView.swift` — the full-screen Now Playing overlay,
  presented from `ShellView` via `.fullScreenCover` (not from `MiniPlayer`; the
  mini-player stays a pure strip). Holds `NowPlayingInfoView` and the pure
  `TimeText.mmss`. Stream pickers send each stream's own `index` (never the row
  offset); subtitles-off sends the string `"off"` via `SubtitleSelection`. The
  video control sends `Input.ExecuteAction {"action":"aspectratio"}` — confirmed
  present in the live box's action enum with a read-only `JSONRPC.Introspect`
  (2026-10-11), so no fallback is used. `QueueSheet` is surfaced here.
- `YatseRemote/Core/LibraryCatalog.swift` — `LibrarySection.layout`
  (`grid` for movies/tvshows, `list` for artists/albums) drives `LibraryView`;
  `PosterTile` + `PosterImage` (2:3) render the grid; `ChildrenView` stays a list.
- `YatseRemote/UI/Touchpad.swift` — `TouchpadGestureResolver` is pure and
  unit-tested; the view is a thin shell over it.
- `YatseRemote/UI/HomeScreen.swift`, `SettingsView.swift`,
  `PlaceholderScreen.swift` — Home, Settings/About, and the honest placeholder.
- `HostsView` gained `HostsMode` (`connect` picker vs `manage`) and no longer owns
  a `NavigationStack`; `LibraryView` is now `LibraryView(model:section:onOpenDrawer:)`.
- **`AppModel.send` is result-agnostic** (`IgnoreResult`): Kodi answers some
  methods with `"OK"` and others with a boolean (`GUI.SetFullscreen`), so a fixed
  `String` decode used to throw `malformedResponse` on half of them.
- **Remote button rows are APK-faithful**, taken from
  `decompiled/resources/res/layout/fragment_remote.xml` (+ handler `bf/a4.java`):
  row 1 = Volume-Down, Mute, Volume-Up; row 2 = Back (`remote_return`),
  Fullscreen (`remote_display`), Info, Keyboard, Context (`remote_context`, which
  uses the list icon and sends `Input.ExecuteAction contextmenu`). The d-pad is
  up/left/select/right/down with a bare Back and the touchpad toggle
  bottom-right. **Yatse's Remote has no subtitle and no queue button** — those are
  Now Playing-page controls here, now surfaced in the `NowPlayingView` overlay
  (the `QueueSheet` and playlist `AppModel` methods are no longer unreferenced).
- **A stroked `Circle()` hit-tests only the ring.** The Remote's select control is
  `Circle().strokeBorder(...)`, so it needs `.contentShape(Circle())` or a tap in
  the middle misses. (This was a real on-device bug.)

## Reverse-engineering inputs (outside this repo)

```
~/reverseEngineer/yatse/
  org.leetzone...apk          Yatse 12.0.0, sha256 40746f8f84c6e9ac22…
  decompiled/                 6,434 .java from jadx (50 MB, 222 decompile errors)
  probe_jsonrpc.py            live payload validation harness
  probe-evidence.txt          11/12 payload shapes accepted by Kodi 21.3
  REPORT.md                   the specification this app was built from
```

Re-run the live protocol probe:

```bash
cd ~/reverseEngineer/yatse && python3 probe_jsonrpc.py
```

It is read-only by design (no `Input.ExecuteAction`, no playlist mutation) so it
is safe to run against the live box. It talks to Kodi at `10.13.13.7:8080` with
Basic auth; credentials are in the script.

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
- **`System.FriendlyName` does not exist in Kodi 21.3** (`-32601`), even though
  Yatse's DEX still references it. Server identity comes from
  `Application.GetProperties`.
- **Kodi's `currentsubtitle` is `{}`**, not absent and not null, when no subtitle
  is selected. A strict decoder throws on it.
- **`artist` is a string in `AudioLibrary.GetArtists` and an array in
  `GetSongs`/`GetAlbums`.** `StringList` exists for exactly this.
- **Artwork 401s without Basic auth**, so `AsyncImage` cannot be used; see
  `ArtworkImage`.
- **SSDP discovery is impossible for a free-signed build** — iOS gates
  `239.255.255.250:1900` behind `com.apple.developer.networking.multicast`.
  Bonjour is used instead, which needs no entitlement.
- **WebSocket JSON-RPC is not on the HTTP port on this box.** An HTTP `Upgrade`
  request to `:8080/jsonrpc` returns **HTTP 200**; only `:9090/jsonrpc` returns
  **HTTP 101** (confirmed with `curl -u` against Kodi 21.3). The app's
  pre-existing `Host.socketURL` builds `ws://…:<http port>/jsonrpc`, so the
  in-app notification probe will likely fail where `check-host.py` passes — the
  script tries the configured port then falls back to `9090`. The self-check
  reports this honestly as a notification-layer failure; fixing `Host.socketURL`
  is **out of scope** for `add-connection-diagnostics`.
- **`Host.lastCheck` must stay optional.** `HostStore.load()` decodes persisted
  hosts with `try?`, so adding a *non-optional* field to `Host` makes every saved
  host fail to decode and silently produces an empty list. `lastCheck` is a
  stored optional defaulting to `nil`, guarded by a back-compat decode test
  (`HostPersistenceTests.testDecodesPreChangeHostsWithoutLastCheck`).

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
```

## Next steps

1. Install the IPA on a device (SideStore / AltStore / Sideloadly re-sign it) and
   drive a real Kodi box. Nothing has been exercised on-device yet.
2. If the local-network prompt is declined, discovery and JSON-RPC both fail
   silently — re-enable under Settings → Privacy → Local Network.
3. Out of scope on purpose (see README): Plex/Emby/Jellyfin backends, DLNA
   casting, offline download/transcode, PVR/EPG, Android-only surfaces.
