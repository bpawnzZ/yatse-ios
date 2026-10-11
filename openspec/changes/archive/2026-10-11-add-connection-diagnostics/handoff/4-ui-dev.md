# Handoff — 4.2 / 4.3 / 3.2-wiring (ui-dev)

- **Task ids**: 4.2 (`UI/DiagnosticsView.swift`), 4.3 (entry points + host-row
  status + `DiagnosticsStatusTests.swift`), 3.2 wiring (persist/read last check
  from the UI run)
- **State**: code complete — **compiler-UNVERIFIED**. No Swift toolchain, no
  Xcode, no macOS on this host; CI is the only compiler. The rendered sheet has
  **NOT been seen on a device** — nothing here proves it works, only (once CI is
  green) that it compiles.
- **Branch**: `diag/check-host` (shared tree; not pushed)

## Files touched (only these; all mine)

| Path | Change |
|---|---|
| `YatseRemote/UI/DiagnosticsView.swift` | NEW — `HostCheckStatus` (row mapping), `DiagnosticsView` (sheet) |
| `YatseRemote/UI/HostsView.swift` | host-row status line + trailing "Check" swipe → sheet |
| `YatseRemote/UI/RemoteView.swift` | toolbar "Connection check" button → sheet |
| `YatseRemote/App/AppModel.swift` | `var diagnosticsContext: DiagnosticsContext` (reaches the private `KodiClient`) |
| `YatseRemoteTests/DiagnosticsStatusTests.swift` | NEW — status-mapping tests |

## What is implemented

- **Run + progress (4.2):** `DiagnosticsView` calls
  `Diagnostics(host:context:).run { result in results.append(result) }`; each
  `ProbeResult` is appended to `@State` as it lands (the progress closure is
  `@MainActor`, so appends happen on main), so the sheet advances per probe
  instead of showing a single ~35 s spinner.
- **Copy (4.2):** `UIPasteboard.general.string = report.text` (report already
  excludes the password by construction).
- **Persist + read back (3.2 wiring):** the sheet's `onFinish` callback maps
  `report → HostCheckSummary` via **one** function,
  `HostCheckStatus.summary(for:)`, and persists with
  `HostStore.recordCheck(for:summary:)`. The host row renders
  `HostCheckStatus(summary: host.lastCheck)`, so both surfaces are derived from
  the same `report.succeeded` / `report.failingLayer` values.
- **Host-row status (4.3):** `HostCheckStatus` is a pure value type with three
  states — `neverChecked` ("Not checked", no timestamp), `failed`
  ("Failed — <layer title>", `ConnectionLayer(rawValue:)?.title ?? raw`,
  timestamp), `reachable` ("Reachable", timestamp). Timestamp is
  `yyyy-MM-dd HH:mm` in UTC (`en_US_POSIX`), so formatting is deterministic.
- **Entry points (4.3):** `HostsView` row trailing swipe "Check"; `RemoteView`
  toolbar `stethoscope` button. Both present the same `DiagnosticsView`.

## Verification

```
$ openspec validate "add-connection-diagnostics" --strict
Change 'add-connection-diagnostics' is valid
exit=0
```

No compile/test run is possible locally (no Swift toolchain). The unit tests in
`DiagnosticsStatusTests.swift` assert all three status branches, the raw-value
fallback for an unknown layer, deterministic UTC timestamp formatting, and the
`report → summary → row` round trip; they are expected to pass in CI but were
**not executed here**.

## Blocker / dependency

None outstanding. Depends on already-committed surfaces: `Diagnostics.swift`
(core-dev, runner/probes) and `Host.swift` `HostCheckSummary` / `Host.lastCheck`
/ `HostStore.recordCheck` (persistence-dev, commit `012a23d`) — both landed, and
my code targets their exact frozen signatures.

## Explicit limitation

The rendered `DiagnosticsView` sheet has **not been seen on a device or in a
simulator**. CI compiling it is not evidence that it renders correctly or that
the copy button behaves; that requires the IPA-on-device step in the change's
workflow follow-up.
