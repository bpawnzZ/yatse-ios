You are implementing an approved OpenSpec change. Work in `/home/insomnia/git/yatse-ios`.

## What to do

1. `cd /home/insomnia/git/yatse-ios`
2. `openspec instructions apply --change "add-connection-diagnostics" --json`
3. Read **every** file that returns under `contextFiles`, from disk, before writing any code — `proposal.md`, `specs/connection-diagnostics/spec.md`, `design.md`, `tasks.md`. The design records decisions that are already settled; do not re-litigate them.
4. Implement the tasks in order. After finishing a task, flip its checkbox `- [ ]` → `- [x]` at the exact `sourcePath` and `line` the CLI reported, then re-run step 2 and confirm progress advanced before starting the next one.
5. Work on a branch: `git checkout -b add-connection-diagnostics`. Push it and open a PR once both workflows are green. Do not merge, and do not push to `main`.

## Hard constraints — these override anything you might otherwise assume

- **You cannot compile or run Swift on this host.** There is no macOS and no Xcode. Pushing a branch and reading the GitHub Actions run is the *only* way to verify code. `build-ipa.yml` is the compiler check; `tests.yml` runs the unit tests. Never mark a task complete on the strength of having read your own code — get the run IDs and quote the result.
- **A green check does not mean the feature works.** A passing build proves it compiles; a passing test proves what that test asserts. `DiagnosticsView` has never been rendered on a device — describe it as untested, not as working. Unknowns stay labelled as unknowns.
- **No credentials in the repository, ever.** Task 5.2 needs the live Kodi host; the host, username and password already in use are in `/home/insomnia/reverseEngineer/yatse/probe_jsonrpc.py`. Read them from there into environment variables (`KODI_HOST`, `KODI_USER`, `KODI_PASS`) for that one command. `scripts/check-host.py` must read them from the environment only, must have no default value, and must exit non-zero with a clear message when they are missing. If you cannot obtain them, ask — never invent placeholders and never commit them.
- **Stay read-only against the live box.** It may be playing something. Only the allowlisted methods; no `Input.*`, no playlist mutation, no settings writes, no volume or mute changes.
- **Commit nothing derived from the Yatse APK.** This is a clean-room build: no decompiled Java, no Yatse resources, artwork or string tables. The reverse-engineering evidence stays outside the repository.
- **Add no license gate, trial, in-app purchase or ad surface.** None exist in this app by design.
- **Scope is fixed.** If a task needs work beyond what the spec describes — or you are tempted to defer, narrow or simplify specified behavior to make it fit — stop and ask. Do not absorb new scope silently, and do not edit the planning artifacts to match the code.
- Keep the diff proportional to the tasks: no new dependencies, no new entitlements, no CI workflow changes.

## Done means all of these

- `openspec validate "add-connection-diagnostics" --strict` passes.
- Every task is `- [x]`, meaning its specified behavior is implemented *and* verified — not partially done, not deferred.
- `openspec/changes/add-connection-diagnostics/live-probe-output.txt` exists and contains the real output of `scripts/check-host.py` run against the live host.
- Both workflows are green on the branch head. Report the two run IDs, the `Executed N tests, with 0 failures` line, and the IPA SHA-256.
- The PR description lists the tasks completed, the run IDs, and an explicit list of what remains unverified (everything requiring a physical device).
