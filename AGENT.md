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
