# Spec-conformance review — add-connection-diagnostics

Reviewer: `reviewer` (independent, read-only, `worktree: false`). It wrote none of
the code.
Base `main` = `ccea706`; reviewed HEAD = `diag/check-host`.
Method: static review of the combined diff + `spec.md`. No Swift toolchain exists
on the host, so **nothing here is CI-verified** — this is a diff review only.

> Recorded by the lead because the reviewer session had no write tool.

## Verdict

All 5 spec requirements are implemented. All 6 mission constraints pass. Four
scenarios initially had **code but no covering test**; all four were closed by
`core-dev` in commit `13384ca` (test-only).

## Per-requirement conformance (all OBSERVED)

| Req | Status | Evidence |
|---|---|---|
| R1 Host Connection Self-Check | satisfied | ordered `defaultProbes()`; runner reports every probe incl. `notRun`; `succeeded` flag |
| R2 Layer-Attributed Failure Reporting | satisfied | layer + request + verbatim error + remediation in `describe(...)` / `ConnectionLayer.remediation` |
| R3 Read-Only Probing | satisfied | `readOnlyMethods` set; runner refuses a non-allowlisted method *before* invoking it |
| R4 Portable, Redacted Report | satisfied | fixed field list in `DiagnosticsReport.text`; no password path; copy via `UIPasteboard` |
| R5 Persisted Host Check Status | satisfied | optional `Host.lastCheck`; never-checked vs failed (named layer) vs reachable (+ timestamp) |

No requirement lacked an implementation.

## Gaps found → closed (`core-dev` `13384ca`)

1. **Redaction test was VACUOUS** — the known password was never wired into the
   host/context, so the assertion passed trivially. Rewritten: the password now
   rides the reachability closure, the real `Diagnostics.run` executes, the
   header is asserted to carry only the fixed labels, and a **sensitivity
   control** proves the guard *can* fail if the builder leaked a credential.
2. No test for the **JSON-RPC-error** scenario → added, using the verbatim
   `-32601 "Method not found."` fixture (`testJSONRPCErrorIsAttributedWithVerbatimCodeAndMessage`).
3. No test for the **failed-run report text** → added (`testReportAfterAFailedRunStillNamesTheLayerAndError`).
4. No test for **active-playback-undisturbed** → added a mechanical proxy
   (`testReadOnlyAllowlistExcludesEveryMutatingMethod`). The live
   player/item/position invariance assertion remains **device-only: UNKNOWN**.

## Constraint checks

1. Read-only mechanical — **PASS**
2. Report redaction — **PASS** (after the gap fix)
3. Back-compat optional `lastCheck` — **PASS** (pre-change decode-guard test)
4. Scope discipline — **PASS** (no new dependency/entitlement/Info.plist/`project.yml`/workflow change; no planning-artifact content edits)
5. No credentials in the diff — **PASS**
6. Ownership — **PASS** (linear history, single author)

## Pre-existing issue — reported, not introduced, out of scope

`Host.socketURL` builds `ws://<host>:8080/jsonrpc`, but the WebSocket upgrade on
this Kodi 21.3 box only answers on port **9090** (lead-confirmed with `curl`:
`:8080` → HTTP 200, `:9090` → HTTP 101). The change does **not** alter
`Host.socketURL`; `scripts/check-host.py` documents and uses a 8080→9090
fallback. Latent app bug, outside `add-connection-diagnostics`.
