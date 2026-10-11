# Design

## Context

See `proposal.md` — Why. Current state that shapes the approach:

- `KodiClient` already owns request construction, Basic auth, the ephemeral
  `URLSession` (12 s request timeout) and the WebSocket task. It throws a typed
  `KodiError` that already distinguishes transport, HTTP status, JSON-RPC error
  and malformed response — the layers this change needs to report are already
  modelled, they are just not surfaced individually.
- `AppModel` holds the only connection to a host and already tracks a
  single-slot `lastError`, which is exactly the mechanism that cannot
  distinguish layers today.
- `ArtworkImage` performs authenticated image fetches outside `KodiClient`, so
  the artwork layer is not currently reachable from client code.
- `Host` is persisted to `UserDefaults` as JSON via synthesized `Codable`, and
  `HostStore.load()` uses `try?` — a decode failure silently yields an empty
  host list.
- There is no macOS host: everything below must be verifiable by unit tests over
  injected values or by the existing fixtures, then by CI.

## Goals / Non-Goals

**Goals:**

- One run produces a per-layer verdict, so a device-side failure report names
  the layer instead of a symptom.
- The probe sequence is data, so every probe — including the ones not reached —
  appears in the result without bespoke reporting code per probe.
- Read-only enforcement is mechanical, not a review convention.

**Non-Goals:**

- Probing more than the selected host, periodically or in the background.
- Repairing a failed layer, or retrying it with different settings.
- A general logging/telemetry framework. The report is a string; where it goes
  is the user's business.
- Probing the EventServer (UDP 9777) transport, which this app does not speak.

## Decisions

### One declarative probe list, evaluated by a single runner

`Diagnostics` owns an ordered `[Probe]`, where a `Probe` is an id, a display
name, the connectivity layer it covers, the read-only method it issues (or a
custom closure for the two non-JSON-RPC probes), and an optional dependency on
an earlier probe. The runner walks it once and produces `[ProbeResult]` with
state `passed | failed | notRun` plus detail text.

*Alternative considered:* six hand-written check functions building a result
incrementally. Rejected: the spec requires reporting probes that were never
reached, and hand-written sequencing is where "not reached" results get dropped.

### Cheapest layer first, and dependents are skipped rather than run

Order: reachability → credentials/identity → library read permission → artwork
fetch → notification channel → server compatibility. A probe whose dependency
failed is marked `notRun`.

*Alternative considered:* run all probes independently. Rejected: against a dead
host that costs a full timeout per probe and fills the report with six
downstream failures whose only real cause is the first one.

### The reachability probe is a plain connect, not a JSON-RPC call

It opens a short (4 s) request to the host with no credentials, and treats
`HTTP 401` as **success** — the host answered.

*Alternative considered:* reuse the 12 s JSON-RPC timeout. Rejected: it cannot
tell "nothing is listening" from "the request is slow", which is the single most
common real-world cause (wrong IP, firewall, wrong port).

### Read-only enforcement is a set the runner checks

A `Set<String>` of permitted methods, and the runner refuses to issue anything
outside it (throwing rather than sending). A unit test asserts every probe's
method is in the set.

*Alternative considered:* rely on code review, since the probe list is small.
Rejected: the target box may be mid-playback, the constraint is a hard MUST in
the spec, and a set plus one assertion is cheaper than the review habit it
replaces.

### Timeouts are per probe and the budget is their sum

4 s for reachability, 8 s for the JSON-RPC probes, 3 s for the WebSocket wait.
Worst case ≈35 s, which is a bounded run without a global watchdog.

*Alternative considered:* a task group with an overall deadline that cancels
stragglers. Rejected as machinery with no observable difference: the probes are
sequential and individually bounded, so the only thing a watchdog adds is a
report that cannot say which probe was slow.

### The artwork probe reuses the authenticated loader path

It fetches the poster of the currently playing item, else the first library
item. With no artwork available it is reported `notRun` with the reason, never
failed.

*Alternative considered:* build a synthetic `/image/` URL. Rejected: a synthetic
texture URL is not what the app actually fetches, so a pass would prove nothing
and a failure would be misleading.

### The WebSocket probe treats a silent socket as a pass

It opens the socket, waits up to 3 s for a frame, and passes on handshake with no
error — recording "connected, no frame within 3 s" as the detail. Only a socket
error fails it.

*Alternative considered:* require a frame. Rejected: Kodi sends nothing while
idle, so that would report a healthy notification channel as broken.

### Last-check state lives on `Host` as an optional field

`Host` gains an optional `lastCheck` value. It must stay optional: `HostStore`
decodes persisted hosts with `try?`, so a required new field would make every
existing host fail to decode and silently produce an empty list.

*Alternative considered:* a separate dictionary keyed by host id. Rejected: two
stores to keep in sync, and removing a host would leave an orphan entry.

## Risks / Trade-offs

- **[Persisted hosts are silently wiped by a non-optional new field]** →
  `lastCheck` is optional, and a unit test decodes a pre-change `Host` JSON and
  asserts the host survives. This is the highest-consequence risk in the change.
- **[A probe passes for the wrong reason]** — e.g. the reachability probe passes
  because a captive portal answers, not Kodi → the credentials probe immediately
  fails on the same run, and the report shows both, which is the honest signal.
- **[Diagnostics drift from real request paths]** — a probe that hand-rolls a
  request can pass while the app's real path fails → probes reuse `KodiClient`
  for everything except the reachability connect, which has no counterpart in
  real use.
- **[Report leaks a credential]** → the report is assembled from a fixed field
  list that excludes the password, plus a unit test asserting a host with a
  known password produces no report containing it.
- **[35 s feels hung]** → the sheet shows per-probe progress as each result
  lands, so the run is visibly advancing.

## Migration Plan

Additive only. No deployment step: the change ships in the next IPA build and
older builds ignore the added optional field if a user downgrades. Rollback is
reverting the commit; no persisted data depends on the new field.

## Open Questions

- Whether to add an EventServer (UDP 9777) probe when and if that transport is
  implemented — it cannot be probed meaningfully while the app does not use it.
