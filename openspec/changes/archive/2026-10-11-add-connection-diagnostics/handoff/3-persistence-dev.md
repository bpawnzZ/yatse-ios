# Handoff — 3.1 + 3.2 persistence (persistence-dev)

## Scope owned
- `YatseRemote/Core/Host.swift`
- `YatseRemoteTests/HostPersistenceTests.swift` (NEW)

## Deliverables

### 3.1 — optional `lastCheck` on `Host` (+ decode guard)
- New value type `HostCheckSummary: Codable, Hashable` with `ok: Bool`,
  `failingLayer: String?`, `date: Date`. `failingLayer` is `ConnectionLayer.rawValue`
  when the run failed, `nil` when it passed — kept `String` on purpose so persisted
  host state stays decoupled from the (non-`Codable`) `ConnectionLayer`.
- `Host` gains `var lastCheck: HostCheckSummary? = nil` as a **stored** property.
  No `CodingKeys`, all existing fields/defaults untouched; synthesized `Codable`
  uses `decodeIfPresent` for the optional, so pre-change JSON still decodes.
- Guard test `testDecodesPreChangeHostsWithoutLastCheck` decodes a verbatim
  pre-change `[Host]` fixture (no `lastCheck` key) — the exact shape
  `HostStore.load()` reads with `try?`. A second test
  `testPreChangeHostRemainsUsable` decodes a single pre-change `Host` and asserts
  its `rpcURL` still builds.

### 3.2 — persist + read back through `HostStore`
- `HostStore.recordCheck(for host: Host, summary: HostCheckSummary)` — matches the
  index by `host.id`, sets `hosts[index].lastCheck = summary`, calls the existing
  `save()`. Unknown id is a no-op (does not append).
- Round-trip tests: `testRecordCheckPersistsAndReloads` (record a failing summary,
  read it back from a *fresh* `HostStore` via `load()`, compare fields + timestamp);
  `testRecordCheckKeepsLatestResultOnly` (second check replaces the first, no host
  appended); `testRecordCheckIgnoresUnknownHost`.

## FROZEN INTERFACE — honoured exactly
```swift
struct HostCheckSummary: Codable, Hashable { var ok: Bool; var failingLayer: String?; var date: Date }
struct Host: Codable, Identifiable, Hashable { /* existing unchanged */ var lastCheck: HostCheckSummary? = nil }
extension HostStore { func recordCheck(for host: Host, summary: HostCheckSummary) }
```
No deviation. `recordCheck` is a `HostStore` method (not an `extension`) but the
call surface is identical.

## Test-environment note
`HostStore` is `@MainActor`; tests that touch it are annotated `@MainActor`
per-method (the class and `setUp`/`tearDown` stay nonisolated to avoid an
actor-isolation override mismatch). Tests clear `UserDefaults` key
`yatse.hosts.v1` in setUp/tearDown so the round-trip is deterministic and does
not leak between runs.

## Commands run (verbatim)
```
$ openspec validate "add-connection-diagnostics" --strict
Change 'add-connection-diagnostics' is valid
```
```
$ which swift swiftc xcodebuild
swift not found
swiftc not found
xcodebuild not found
```
Fixture JSON parsed with python3 (`json.loads`): array = 2 hosts, keys equal
`{id,name,address,port,username,useTLS,macAddress,wolPort}`, `lastCheck` absent.

## Verification status
- **IMPLEMENTED**: both files as above.
- **VERIFIED locally**: `openspec validate --strict`; fixture JSON syntax + key
  shape; OpenSpec task intent matched.
- **UNVERIFIED pending CI**: Swift compilation and all four unit tests. No macOS/
  Xcode on this host — CI `tests.yml` is the compiler. Do not mark 3.1/3.2 `[x]`
  until the `tests.yml` run is green.

## Traps encoded
- `lastCheck` must never become non-optional: `HostStore.load()`'s `try?` would
  swallow the throw and silently empty a user's saved hosts.
- `recordCheck` must match by `id`, not object identity, and must not append.
