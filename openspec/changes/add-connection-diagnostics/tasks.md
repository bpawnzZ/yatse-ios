# Tasks

## 1. Probe model and read-only enforcement

- [ ] 1.1 Add `YatseRemote/Core/Diagnostics.swift` with the ordered probe descriptors, the connectivity-layer enum, the result states (`passed` / `failed` / `notRun`), and the read-only JSON-RPC method allowlist; verify the CI "Build unsigned IPA" run for the branch compiles it (Swift is not compilable on the development host).
- [ ] 1.2 Add a unit test asserting every declared probe's method is a member of the allowlist, and that the runner refuses to issue a method outside it; verify both pass in the CI "Unit tests" run.

## 2. Probe execution

- [ ] 2.1 Implement the sequential runner: dependency-aware skipping, per-probe timeouts (4 s reachability, 8 s JSON-RPC, 3 s WebSocket wait), and detail capture; verify tests for all-pass, failure-skips-dependents, and unreachable-marks-not-run pass in CI.
- [ ] 2.2 Implement the reachability probe as an unauthenticated connect where HTTP 401 counts as reachable; verify tests for 401-is-reachable, connection-refused-carries-transport-detail, and timeout-is-a-failure pass in CI.
- [ ] 2.3 Implement the credentials/identity, library-read, and server-compatibility probes on top of existing `KodiClient` calls; verify tests driven by the existing verbatim Kodi fixtures pass in CI.
- [ ] 2.4 Implement the artwork probe on the authenticated image-fetch path; verify a test asserts an empty artwork set reports `notRun` with a reason and never `failed`.
- [ ] 2.5 Implement the WebSocket probe (open, wait up to 3 s for a frame, close); verify tests for frame-received-is-pass and silent-socket-is-pass-with-detail pass in CI.

## 3. Result persistence

- [ ] 3.1 Add an optional `lastCheck` field to `Host` plus a test that decodes a pre-change `Host` JSON fixture and asserts the host still decodes — this is the guard against `HostStore` silently emptying a user's saved hosts; verify the test passes in CI.
- [ ] 3.2 Persist the latest result per host and read it back; verify a round-trip test through `HostStore` passes in CI.

## 4. Report and UI

- [ ] 4.1 Build the plain-text report from a fixed field list (app version, scheme/host/port, server name and version, per-probe outcome and detail); verify a test asserting a host with a known password produces no report containing it passes in CI.
- [ ] 4.2 Add `YatseRemote/UI/DiagnosticsView.swift` showing each probe's state as results land, with copy-to-clipboard of the report; verify it compiles in CI and state plainly that the rendered sheet has not been seen on a device.
- [ ] 4.3 Add entry points from the host list and the remote, and render the persisted status on each host row (not checked / failing layer / reachable + timestamp); verify the status-mapping unit tests pass in CI.

## 5. Live validation of the sequence from a development host

- [ ] 5.1 Add `scripts/check-host.py`, reading host, username and password from environment variables and never storing credentials in the repository, running the same read-only sequence; verify it exits non-zero with a clear message when the environment variables are absent.
- [ ] 5.2 Run `scripts/check-host.py` against the live Kodi 21.3 box and confirm every probe reports passed; record the output as `openspec/changes/add-connection-diagnostics/live-probe-output.txt`.

## 6. Integration

- [ ] 6.1 Push the branch and confirm both `build-ipa.yml` and `tests.yml` are green on the same commit; report both run IDs, the test count, and the IPA SHA-256.
- [ ] 6.2 Update `README.md` (self-check section) and `AGENT.md` (how to run the host check from a development host, and the traps this change encodes); verify every command written in those sections runs as documented.

## Workflow follow-up

- Install the resulting IPA on a device, run the self-check against the real host, and record the on-device result — this is the step no task above can verify.
- Archive the change once the project's review requirements are satisfied.
