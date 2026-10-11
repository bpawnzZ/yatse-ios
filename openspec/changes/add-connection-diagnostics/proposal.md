# Proposal

## Why

YatseRemote builds and its decoders are unit-tested in CI, but **no networking
path in it has ever executed against a real Kodi instance**: there is no macOS
host in the development loop, so the first run of any request is on a sideloaded
phone. Every failure mode therefore looks identical from the outside — a spinner,
or one line of text in the remote's error slot. A report of "it doesn't work"
cannot be turned into a fix without a Mac and a debugger.

The Android app this was specified from ships a host connection check
(`str_checkconfig`, `str_host_check_ok`, `str_host_httperror`, `str_error_server_connect`).
This app has none, and it has six independent layers that can each fail
silently and independently: DNS/socket reachability, HTTP status, credentials,
JSON-RPC method permission, the authenticated `/image/` artwork endpoint, and
the WebSocket notification channel.

## What Changes

- Add a **connection self-check** that runs a fixed, ordered probe sequence
  against a saved host and reports the outcome of *every* probe, not just the
  first failure — so one run identifies the broken layer instead of one symptom.
- Probes are ordered cheapest-first and cover each layer separately:
  reachability, credentials, library read permission, artwork fetch,
  notification channel, and reported server compatibility.
- Present the result in a sheet reachable from the host list and from the
  remote, with a plain-text report that can be copied out — host details, server
  identity, and per-probe outcomes, with no password in it.
- Persist the last check outcome per host so the host list distinguishes
  **never checked** from **checked and failed**, and names the failing layer.
- Every probe is read-only. A diagnostic must never disturb what the user is
  currently watching, and must not be able to.

## Capabilities

### New Capabilities

- `connection-diagnostics`: how the app probes a host's connectivity one layer
  at a time, attributes each failure to the layer that produced it, and reports
  the result without mutating any host state.

### Modified Capabilities

None — this repository has no existing specs.

## Impact

- **New code**: `YatseRemote/Core/Diagnostics.swift` (probe sequence, result
  model, read-only method allowlist), `YatseRemote/UI/DiagnosticsView.swift`
  (report, copy, re-run).
- **Modified code**: `AppModel` (expose a diagnostic run, store last outcome),
  `KodiClient` (a bounded WebSocket handshake probe and a probe-able artwork
  fetch, reusing the existing auth path), `HostsView` and `RemoteView` (entry
  points and status surface).
- **Tests**: new unit tests for probe aggregation, the read-only allowlist, and
  report redaction, driven by the existing verbatim Kodi fixtures. No new
  fixtures or dependencies.
- **No** Info.plist, entitlement, or CI-workflow changes. No new dependencies.
- **Out of scope**: background/periodic health checks (the app carries no
  background modes and adding one needs an entitlement), any automatic repair of
  a failed probe, and probing hosts other than the selected one.
