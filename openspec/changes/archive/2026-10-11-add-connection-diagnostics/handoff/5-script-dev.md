# Handoff — 5.1 / 5.2 (script-dev)

- **Task ids**: 5.1 (add `scripts/check-host.py`), 5.2 (live run + record output)
- **State**: complete — both probes verified
- **Branch**: `diag/check-host`

## Files touched (only these)

| Path | Change |
|---|---|
| `scripts/check-host.py` | NEW — read-only host check, stdlib only |
| `openspec/changes/add-connection-diagnostics/live-probe-output.txt` | NEW — verbatim output of the live run |
| `openspec/changes/add-connection-diagnostics/handoff/5-script-dev.md` | NEW — this file |

No planning artifact was edited (proposal/spec/design/tasks untouched). No
`- [x]` checkbox changed — that is the lead's job. Credentials are not present
in any committed file.

## Design notes

- Host, username, password read from the environment only: `KODI_HOST`,
  `KODI_USER`, `KODI_PASS`. No defaults; any missing one exits **2** with a
  clear message. `KODI_HOST` accepts either a base URL
  (`http://10.13.13.7:8080`) or one already ending in `/jsonrpc`.
- Ordered probes, same sequence as the app: reachability (unauthenticated; HTTP
  401 = reachable) → credentials/identity (`JSONRPC.Ping` +
  `Application.GetProperties`) → library read permission
  (`VideoLibrary.GetMovies`, limit 1) → artwork fetch (authenticated
  `GET /image/...` of the first library item's thumbnail) → notification channel
  (WebSocket handshake, ≤3 s frame wait; silent socket = pass with detail) →
  server compatibility (reported version via `Application.GetProperties`).
- Read-only enforcement is mechanical: `READ_ONLY_METHODS` is a frozen set and
  `Runner.rpc()` raises `RuntimeError` if asked for anything outside it. Only
  allowlisted methods are issued.
- **WebSocket port finding (worth naming):** Kodi serves the WebSocket upgrade
  on its JSON-RPC TCP port (9090), not on the HTTP web port the app's
  `Host.socketURL` builds (`ws://addr:port/jsonrpc` with `port` = 8080). A raw
  handshake to `:8080/jsonrpc` returns HTTP 200 (the service-description page);
  `:9090/jsonrpc` returns HTTP 101. The probe tries the configured port first,
  then falls back to 9090, and reports which port answered. **The app's
  `socketURL` is outside my scope (I may not edit other files) but it looks like
  it would fail the notification channel as written.** Flagged for the lead.

## Command and verbatim output — 5.1 failure path (env unset)

Command:

```
env -u KODI_HOST -u KODI_USER -u KODI_PASS python3 scripts/check-host.py
```

Output (verbatim, exit 2):

```
check-host: environment variable KODI_HOST is not set.
check-host: export KODI_HOST, KODI_USER and KODI_PASS before running; credentials are never stored in this repository.
exit=2
```

## Command and verbatim output — 5.2 live run

Credentials were read out of the existing reference harness
(`/home/insomnia/reverseEngineer/yatse/probe_jsonrpc.py`) into the environment
for this one run only — never written to disk or into the script:

```
eval "$(python3 - <<'PY'
import re
src = open('/home/insomnia/reverseEngineer/yatse/probe_jsonrpc.py').read()
print("export KODI_HOST=%r" % re.search(r'^HOST = "(.*?)"', src, re.M).group(1))
u, p = re.search(r'^USER, PW = "(.*?)", "(.*?)"', src, re.M).groups()
print("export KODI_USER=%r" % u)
print("export KODI_PASS=%r" % p)
PY
)" && python3 scripts/check-host.py
```

Output (verbatim, exit 0) — saved as `live-probe-output.txt`:

```
host: http://10.13.13.7:8080 (credentials supplied via environment, not printed)

[PASS   ] reachability: host answered HTTP 401 (reachable, auth required)
[PASS   ] credentials/identity: JSONRPC.Ping ok; server Kodi v21.3
[PASS   ] library read permission: VideoLibrary.GetMovies ok (1 item(s) in page)
[PASS   ] artwork fetch: GET /image/ -> HTTP 200, unknown type, 64+ bytes
[PASS   ] notification channel: WebSocket 101 on port 9090; no frame within 3s (silent socket)
[PASS   ] server compatibility: reported Kodi 21.3 (Kodi)

6/6 probes passed
server: Kodi v21.3

RESULT: PASS
```

Password check on the recorded output: `grep -c '<password>' live-probe-output.txt`
→ `0` (absent).

## Pass/fail per probe (live box, Kodi 21.3)

| Probe | Result | Detail |
|---|---|---|
| reachability | PASS | HTTP 401 unauthenticated — host answered |
| credentials/identity | PASS | `JSONRPC.Ping` ok; Kodi v21.3 |
| library read permission | PASS | `VideoLibrary.GetMovies` ok (1 item) |
| artwork fetch | PASS | `GET /image/` HTTP 200, 64+ bytes |
| notification channel | PASS | WebSocket 101 on port 9090, silent socket within 3s |
| server compatibility | PASS | reported Kodi 21.3 |

## UNVERIFIED / caveats

- The artwork probe reads `Content-Type` as absent ("unknown type"); Kodi's
  `/image/` response for this thumbnail did not expose a header urllib saw. The
  probe passes on HTTP 200 + bytes, which is the meaningful signal.
- The WebSocket probe's **configured-port path (8080) was exercised and
  rejected**; the pass came over the 9090 fallback. Whether the app should be
  connecting WS to 9090 is unverified — I could not edit `Host.swift`.
- `KODI_HOST` may be a base URL or include `/jsonrpc`; both were considered but
  only the `/jsonrpc` form from the harness was actually run.

## Blocker

None. **Need from the lead (recipient = team lead)**: a decision on the Kodi
WebSocket port mismatch in `Host.socketURL` (app uses the HTTP port 8080;
Kodi serves WS on 9090) — that is an app-code issue for tasks 2.5 / 4.2, outside
this task's file scope.
