# YatseRemote — iOS Kodi remote

A from-scratch SwiftUI remote for Kodi, written against a specification
reverse-engineered from the **Yatse 12.0.0** Android APK. Clean-room: the
protocol surface (method names, parameter properties, discovery records, default
ports) came from static analysis of the shipped artifact; the Swift here is
original code written from that spec and the public Kodi JSON-RPC v13 docs.

The full reverse-engineering report lives outside this repo with the APK:

```
~/reverseEngineer/yatse/REPORT.md      # findings, evidence IDs, method tables
~/reverseEngineer/yatse/probe-evidence.txt   # live Kodi 21.3 payload validation
```

See [`docs/CLEANROOM.md`](docs/CLEANROOM.md) for what was and was not taken.

## What it does

| Area | Implemented |
|---|---|
| Hosts | add / edit / delete, Basic auth, password in Keychain, HTTP or HTTPS, Wake-on-LAN (MAC + port) |
| Discovery | Bonjour `_xbmc-jsonrpc-h._tcp` / `_xbmc-jsonrpc._tcp` |
| Now playing | poster, title, show/artist line, live progress, seek |
| Transport | play/pause, stop, previous, next, shuffle, repeat, subtitle track, audio track |
| Shell | host-centric: slide-out drawer (Home, Movies, TV Shows, Music, Pvr, Files, Addons, Remote, then Settings and About) with a host header and switcher, and a persistent mini-player while a player is active |
| Remote | one screen (no tabs): app bar with host name and power/cast/remote, a shortcut strip, volume and utility tile rows, an accent d-pad with an outlined select, a bare Back control, touchpad mode, keyboard text entry; the current item's artwork as a blurred background with translucent tiles while playing |
| Queue | current playlist, jump to entry, remove entry, clear |
| Library | Movies, TV Shows → Episodes, Artists → Albums, paged at 60 rows, tap to play |
| Status | connection state, server name + version, in-app error surface |
| Self-check | ordered, read-only, per-layer connection diagnostic with a copyable redacted report and persisted per-host status |

## App shell

The app is host-centric. Before a host is chosen it shows the host picker; once
one is active the root becomes a shell scoped to that host, and player state is
owned by an app-level `Session` (not by a screen), so playback and the live event
stream survive moving between destinations.

- **Drawer** — a slide-over list with a host header (name, switcher, keyboard /
  mic / search actions) and the destinations above. Selecting the current host
  again is a no-op; deleting the active host returns the app to the picker.
- **Mini-player** — pinned above every destination while a player is active, with
  a thumbnail, the title, and stop / play-pause / next. Tapping its title opens
  the Remote.
- **Remote** — a single screen with no tabs: the app bar, the shortcut strip
  (Home, Movies, TV Shows, Music, Pictures), volume and utility tiles, the d-pad,
  a bare Back arrow, and a touchpad toggle. While something plays, the item's
  artwork is the blurred background and the tiles turn translucent.
- **Not implemented** — Pvr, Files and Addons show a placeholder naming the
  destination rather than a dead end.

## Connection self-check

The host list and the remote each expose a **Check** action. It runs a fixed,
ordered, **read-only** probe sequence against one saved host and reports the
outcome of *every* probe — including the ones it did not reach — instead of only
the first failure. One run therefore names the layer that is broken rather than a
symptom, across six layers: reachability, credentials/identity, library read,
artwork fetch, notification channel, and reported server compatibility.

The result is shown live in a sheet, can be copied as a plain-text report
(app version, scheme/host/port, server name and version, per-probe outcome and
detail) that never contains the host password, and the last outcome is persisted
per host so the host list distinguishes **never checked** from **checked and
failed** (naming the failing layer and the time).

Read-only is enforced mechanically: the runner issues only methods from a fixed
allowlist and refuses anything outside it, so a diagnostic cannot disturb what is
currently playing.

The same sequence runs headless from a development host:

```bash
export KODI_HOST=http://10.13.13.7:8080
export KODI_USER=...        # supplied via environment only — never stored in this repo
export KODI_PASS=...
python3 scripts/check-host.py
```

`scripts/check-host.py` reads the host, username and password **only** from the
environment (`KODI_HOST`, `KODI_USER`, `KODI_PASS`), defines no defaults, and
exits non-zero with a clear message if any is missing. It uses the Python
standard library only. See `AGENT.md` for the traps this change encodes.

## Not implemented (deliberately, with reasons)

- **Plex / Emby / Jellyfin backends** — each is a second, unrelated protocol
  stack. Yatse ships all four; this app is the Kodi backend done properly.
- **SSDP/UPnP discovery and DLNA casting** — iOS gates multicast to
  `239.255.255.250:1900` behind `com.apple.developer.networking.multicast`,
  which a free-signed sideload build cannot carry. Bonjour needs no entitlement.
- **Offline download / on-device transcode** — Yatse does this with its bundled
  `libffmpegJNI.so`; a real port means shipping ffmpeg, not wiring JSON-RPC.
- **PVR / EPG, widgets, wearables, CarPlay, Tasker-style plugin surfaces,
  billing** — platform-specific to Android.

## Licensing — everything is unlocked

There is no unlocker, no trial, no in-app purchase, no ad SDK and no feature
flag anywhere in this codebase. `grep -riE 'unlock|premium|licen[cs]|billing|trial|paywall' YatseRemote/`
matches exactly one thing: `NSLock`'s `unlock()` in `KodiClient`. Every feature
this app ships is on for every user, permanently.

Yatse's own resource strings show what the Android app gates behind its one-time
Unlocker purchase (`str_unlocker_benefits_title2` "Pro features",
`str_locked_function_detail_trial`, `str_start_trial_description`): extra colour
themes (`str_color_unlocker`), the offline download queue (`str_download_*`,
`str_save_downloads`), and streaming/transcoding with the BubbleUPnP
trial-limited to 10 minutes per session. None of those subsystems exist in this
app — they are absent, not locked, and no gate was ported to sit in front of
them. The features that *are* implemented (library browsing, queue, remote,
full non-paginated queue) have no limits attached.

## Requirements

- iOS 17 or newer (built with the iOS 26 SDK on CI)
- A Kodi box (tested against Kodi 21.3-Omega) with **Settings → Services →
  Control → Allow remote control via HTTP** enabled
- The Kodi image endpoint is behind the same Basic auth as JSON-RPC, so set a
  username/password or artwork will not load

## Build it

CI does the building; there is no macOS step in this workflow and no signing
certificate anywhere.

```bash
# locally, on macOS:
brew install xcodegen
xcodegen generate      # writes YatseRemote.xcodeproj from project.yml
open YatseRemote.xcodeproj
```

`YatseRemote.xcodeproj` is generated and gitignored — `project.yml` is the
source of truth.

### CI

`.github/workflows/build-ipa.yml` runs on push to `main`, on tags, on PRs, and
on demand:

1. `xcodegen generate`
2. `xcodebuild build` for `generic/platform=iOS` with every signing setting
   forced off on the command line
3. packages `Payload/YatseRemote.app` into `YatseRemote-unsigned.ipa`, stripping
   `_CodeSignature` and `embedded.mobileprovision`
4. verifies the archive and that no signature survives, then uploads the IPA and
   its SHA-256

`.github/workflows/tests.yml` is separate: the unit tests run on a simulator with
ad-hoc signing, and a flaky simulator run can never block an IPA.

### Install on a device

The IPA is unsigned on purpose — SideStore, AltStore or Sideloadly re-sign it
with your own Apple ID. Copy the `YatseRemote-unsigned.ipa` artifact's SHA-256
from the build log and check it before installing.

Free re-signing caveat: the app needs no special entitlements, so nothing here
degrades after re-signing. Local-network access is granted per app by iOS on
first use — accept the prompt or discovery and JSON-RPC both fail.

## Traps worth knowing

- Kodi's webserver serves HTTP and WebSocket JSON-RPC on the **same port**
  (8080 by default) at `/jsonrpc`. Port 9090 is Kodi's own web UI and is
  unauthenticated on many installs; this app talks to 8080 with credentials.
- Notifications arrive interleaved with responses on the WebSocket, so the first
  frame after a call is not necessarily that call's reply. Match on `method`
  (notifications) vs `id` (responses).
- Kodi omits fields that do not apply to an item (`season` on a movie,
  `showtitle` on a song), and returns `artist` as a string in
  `AudioLibrary.GetArtists` but as an array in `GetSongs`. Every model decodes
  leniently for this reason.
- Artwork arrives as `image://http%3a%2f%2f.../`. Strip the `image://` prefix,
  percent-decode, and drop the trailing slash.
- `System.FriendlyName` exists in Yatse's method table but Kodi 21.3 answers
  `-32601 Method not found`. Server identity comes from
  `Application.GetProperties` instead.

## Tests

```bash
xcodebuild test -project YatseRemote.xcodeproj -scheme YatseRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:YatseRemoteTests
```

The fixtures in `YatseRemoteTests` are verbatim responses captured from a live
Kodi 21.3 box, including `currentsubtitle: {}` and the `-32601` error envelope.
