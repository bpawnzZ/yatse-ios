# Mission

Implement the approved OpenSpec change `add-connection-diagnostics` in `/home/insomnia/git/yatse-ios` using an ensemble. Planning is finished and approved — your job is execution, verification, and honest reporting.

This brief works with any number of teammates. With one agent, do the waves in order yourself. Do not spawn a scout to rediscover anything in "Codebase facts" below; that section exists so you do not pay for it twice.

## Read first

```
openspec/changes/add-connection-diagnostics/proposal.md
openspec/changes/add-connection-diagnostics/specs/connection-diagnostics/spec.md
openspec/changes/add-connection-diagnostics/design.md
openspec/changes/add-connection-diagnostics/tasks.md
```

Read them from disk. `design.md` records decisions that are already settled, with the rejected alternatives — do not re-litigate them, and do not edit any planning artifact. Then:

```
openspec instructions apply --change "add-connection-diagnostics" --json
```

## Codebase facts — do not re-derive these

- `YatseRemote/Core/KodiClient.swift` already owns request construction, Basic auth, an ephemeral `URLSession` (12 s request timeout) and the WebSocket task. It throws a typed `KodiError` whose cases already separate transport / HTTP status / JSON-RPC error / malformed response. The layers this change reports are already modelled there; they are simply not surfaced per-probe.
- `YatseRemote/UI/ArtworkImage.swift` fetches authenticated artwork **outside** `KodiClient`. That is the artwork layer, and the probe must go through the same authenticated path.
- `YatseRemote/Core/Host.swift` contains both `Host` and `HostStore`. `Host` is persisted to `UserDefaults` as JSON through synthesized `Codable`, and `HostStore.load()` decodes with `try?`.
- `YatseRemote/App/AppModel.swift` holds the only host connection and a single-slot `lastError` — the mechanism that cannot distinguish layers today. State mutation is `@MainActor`; everything else is `async`/`await`.
- `YatseRemoteTests/KodiModelTests.swift` holds verbatim live-Kodi fixtures. New tests go in new files; do not edit that file.
- `project.yml` is the source of truth for the Xcode project and Info.plist; `YatseRemote.xcodeproj` is generated and gitignored. Never edit the generated project.
- There is **no macOS and no Xcode on this host**. Swift cannot be compiled, run, or tested locally. Pushing to GitHub and reading the Actions run is the only verification that exists.

## Team shape and exclusive file ownership

No two build teammates may edit the same file. If a task seems to need a file another teammate owns, message the lead instead of editing it.

| Teammate | Role | Owns (exclusively) | Tasks |
|---|---|---|---|
| **core-dev** | build, `plan_approval: true` | `Core/Diagnostics.swift` (new), `Core/KodiClient.swift`, `Tests/DiagnosticsTests.swift` (new) | 1.1, 1.2, 2.1–2.5, 4.1 |
| **persistence-dev** | build | `Core/Host.swift`, `Tests/HostPersistenceTests.swift` (new) | 3.1, 3.2 (storage half) |
| **ui-dev** | build | `UI/DiagnosticsView.swift` (new), `UI/HostsView.swift`, `UI/RemoteView.swift`, `App/AppModel.swift` | 4.2, 4.3, 3.2 (wiring half) |
| **script-dev** | build | `scripts/check-host.py` (new) | 5.1, 5.2 |
| **reviewer** | explore, read-only, no worktree | nothing | spec-conformance review |
| **lead** | you | git, CI, `README.md`, `AGENT.md` | 6.1, 6.2 |

`core-dev` is the foundation and carries the real risk: give it the strongest model. `script-dev` is mechanical plumbing and can take a cheap one. Put `plan_approval: true` on `core-dev` and approve or reject its plan over `team_message` before it edits anything.

The report builder (task 4.1) lives with the results it formats, in `Core/Diagnostics.swift`, so its test sits in `DiagnosticsTests.swift`. Only the sheet and its entry points belong to `ui-dev`.

## Task board

Create these, then add the dependent ones using the **real returned ids**:

1. `Core probe model, runner, and probes` — high
2. `Standalone host-check script (Python)` — high
3. `Host lastCheck persistence + back-compat decode test` — high, `depends_on: [1]`
4. `Diagnostics sheet, entry points, host-row status` — high, `depends_on: [1]`
5. `Spec-conformance review of the combined diff` — medium, `depends_on: [1,3,4]`
6. `Integration: CI green, artifact verified, docs updated` — medium, `depends_on: [2,5]`

## Waves

**Wave 1 — parallel, disjoint.** `core-dev` and `script-dev` start together; they share no file and no dependency.

`core-dev`'s **first deliverable is the type surface only** — the layer enum, the result state, the probe descriptor, the runner entry point, and the report builder signature, with probe bodies stubbed. It must post those exact declarations to you before writing any bodies. Broadcast them to `persistence-dev` and `ui-dev`. This is the mechanism that makes the parallelism real: teammates sit in separate worktrees and cannot read each other's files, so the interface has to travel as text. Then `core-dev` fills in the probes.

**Wave 2 — parallel, disjoint.** Once the type surface is broadcast, `persistence-dev` and `ui-dev` start, coding against the posted signatures rather than against files they cannot see.

**Wave 3.** `reviewer` reads the combined diff and the spec and reports per-requirement conformance: which requirement each new piece of behavior satisfies, and any requirement with no implementation. It must not be an agent that wrote any of the code.

**Wave 4 — you only.** Merge worktrees, resolve, and do all git and CI work.

## How to verify, and what counts as done

CI is the compiler. A teammate may not mark a task complete because the code "looks right" — on a host with no Swift toolchain that is not verification of anything.

- `build-ipa.yml` is the compile check. `tests.yml` runs the unit tests.
- **Batch before pushing.** GitHub macOS runner minutes bill at 10× on this private repo. Do not push per task or per teammate; merge and push once per wave at most.
- Only the lead pushes, opens the PR and reads CI. Parallel pushes to one branch cancel each other's runs.
- A task is `- [x]` when its specified behavior is implemented *and* verified by a CI run — flip the checkbox at the exact `sourcePath` and `line` that `openspec instructions apply` reports, then re-run it and confirm progress advanced.
- **A green check does not mean the feature works.** A passing build proves it compiles. A passing test proves what that test asserts. `DiagnosticsView` has never been rendered on a device: describe it as untested, not as working. Every unknown stays labelled as an unknown.
- Keep the diff proportional. No new dependencies, no new entitlements, no CI workflow changes, no edits to planning artifacts.

## Hard constraints

- **Credentials never enter the repository.** Task 5.2 needs the live Kodi host. The host, username and password already in use are in `/home/insomnia/reverseEngineer/yatse/probe_jsonrpc.py`; read them into `KODI_HOST`, `KODI_USER`, `KODI_PASS` for that one command. `scripts/check-host.py` must read those from the environment only, must define no default for them, and must exit non-zero with a clear message when they are missing. If they are unavailable, ask — never invent placeholders, never commit them.
- **Stay read-only against the live box.** It may be playing media. Only the methods in the allowlist: no `Input.*`, no playlist mutation, no settings writes, no volume or mute changes.
- **Commit nothing derived from the Yatse APK.** Clean-room build: no decompiled Java, no Yatse resources, artwork or string tables. The reverse-engineering evidence stays outside the repo.
- **No license gate, trial, IAP or ad code.** None exists in this app by design.
- **Scope is fixed.** If a task needs work beyond what the spec describes — or you are tempted to defer, narrow or simplify specified behavior to make it fit — stop and ask the lead. Do not absorb new scope silently, and do not edit artifacts to match the code.
- Highest-consequence risk in this change: `HostStore.load()` uses `try?`, so a **non-optional** field added to `Host` would make every saved host fail to decode and silently produce an empty list. `lastCheck` must be optional, and the back-compat decode test (3.1) is not optional.

## Definition of done

- `openspec validate "add-connection-diagnostics" --strict` passes.
- Every task is `- [x]` — implemented and verified, not partially done or deferred.
- `openspec/changes/add-connection-diagnostics/live-probe-output.txt` contains the real output of `scripts/check-host.py` against the live host.
- Both workflows green on the same commit.
- Branch pushed, PR opened, **not merged**, nothing pushed to `main`.

## Report back in exactly this shape

```
Change: add-connection-diagnostics   Tasks: N/16 complete
CI: build-ipa.yml run <id> — <result>
    tests.yml    run <id> — <result> ("Executed N tests, with 0 failures")
IPA: sha256 <hash>   Artifact: <path or run link>
Live probe: <pass/fail per probe, from live-probe-output.txt>
Reviewer findings: <per-requirement conformance, or "none blocking">
Unverified: <explicit list — everything requiring a physical device>
```
