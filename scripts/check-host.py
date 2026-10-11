#!/usr/bin/env python3
"""Live read-only connection check for a Kodi host.

Runs the same ordered probe sequence the app implements (see
`openspec/changes/add-connection-diagnostics/design.md`):

    reachability -> credentials/identity -> library read permission ->
    artwork fetch -> notification channel -> server compatibility

Every probe is read-only. This script MUST NOT be able to alter playback,
input focus, the playlist, volume, mute state or any host setting. The only
JSON-RPC methods it may issue are members of ``READ_ONLY_METHODS`` below.

Credentials are read from the environment only and are never stored here:

    KODI_HOST   host base URL, e.g. http://10.13.13.7:8080
                (a URL already ending in /jsonrpc is accepted too)
    KODI_USER   HTTP Basic auth username
    KODI_PASS   HTTP Basic auth password

There is no default for any of them; a missing value is a hard error.
Python standard library only.
"""

from __future__ import annotations

import base64
import json
import os
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request

# ---------------------------------------------------------------------------
# Read-only enforcement. A probe that needs a method outside this set is a bug
# in this script, not a runtime condition; _rpc() refuses to send it.
# ---------------------------------------------------------------------------
READ_ONLY_METHODS = frozenset(
    {
        "JSONRPC.Ping",
        "Application.GetProperties",
        "Player.GetActivePlayers",
        "Player.GetProperties",
        "Player.GetItem",
        "Playlist.GetItems",
        "VideoLibrary.GetMovies",
        "VideoLibrary.GetTVShows",
        "AudioLibrary.GetArtists",
        "AudioLibrary.GetAlbums",
        "Files.GetSources",
    }
)

REACHABILITY_TIMEOUT = 4.0  # reachability probe
RPC_TIMEOUT = 8.0  # JSON-RPC probes
WEBSOCKET_WAIT = 3.0  # WebSocket frame wait
WS_FALLBACK_PORT = 9090  # Kodi's JSON-RPC TCP/WebSocket port


class ProbeError(Exception):
    """A probe failed. `layer` is the connectivity layer it covers."""

    def __init__(self, layer: str, message: str) -> None:
        super().__init__(message)
        self.layer = layer
        self.message = message


def _fail_env(name: str) -> None:
    sys.stderr.write(
        f"check-host: environment variable {name} is not set.\n"
        f"check-host: export KODI_HOST, KODI_USER and KODI_PASS before running; "
        f"credentials are never stored in this repository.\n"
    )
    sys.exit(2)


def split_host(host: str) -> tuple[str, str, str]:
    """Return (base_url, jsonrpc_url, ws_path)."""
    host = host.strip().rstrip("/")
    base, _, path = host.partition("/jsonrpc")
    base = base.rstrip("/")
    jsonrpc_url = base + "/jsonrpc"
    return base, jsonrpc_url, "/jsonrpc"


def _auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    return "Basic " + token


class Runner:
    def __init__(self, base: str, jsonrpc: str, user: str, password: str) -> None:
        self.base = base
        self.jsonrpc = jsonrpc
        self.auth = _auth_header(user, password)
        self._id = 0
        self.results: list[tuple[str, str, str, str]] = []  # name, layer, state, detail
        self.identity: dict = {}

    # -- JSON-RPC (read-only enforced) --------------------------------------
    def rpc(self, method: str, params: dict, layer: str) -> dict:
        if method not in READ_ONLY_METHODS:
            raise RuntimeError(f"refusing to issue non-read-only method {method!r}")
        self._id += 1
        body = json.dumps(
            {"jsonrpc": "2.0", "method": method, "params": params, "id": self._id}
        ).encode()
        req = urllib.request.Request(
            self.jsonrpc,
            data=body,
            headers={"Content-Type": "application/json", "Authorization": self.auth},
        )
        try:
            with urllib.request.urlopen(req, timeout=RPC_TIMEOUT) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            raise ProbeError(layer, f"HTTP {e.code} from {method}") from e
        except Exception as e:  # noqa: BLE001 - transport failures are the layer detail
            raise ProbeError(layer, f"{type(e).__name__}: {e}") from e
        try:
            payload = json.loads(raw)
        except ValueError as e:
            raise ProbeError(layer, f"malformed JSON from {method}: {e}") from e
        if "error" in payload:
            err = payload["error"]
            raise ProbeError(
                layer,
                f"{method} JSON-RPC error {err.get('code')}: {err.get('message')}",
            )
        return payload.get("result", {})

    # -- WebSocket (stdlib only) -------------------------------------------
    def _ws_handshake(self, host: str, port: int) -> str:
        # Kodi serves the WebSocket upgrade on its JSON-RPC TCP port (9090 by
        # default), which is distinct from the HTTP web port the app's
        # `socketURL` assumes. Try the configured port first, then the standard
        # one, and report which answered. Plain ws:// only.
        key = base64.b64encode(os.urandom(16)).decode()
        handshake = (
            "GET /jsonrpc HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "Sec-WebSocket-Protocol: jsonrpc\r\n"
            f"Authorization: {self.auth}\r\n"
            "\r\n"
        ).encode()
        try:
            sock = socket.create_connection((host, port), timeout=REACHABILITY_TIMEOUT)
        except OSError as e:
            raise ProbeError(
                "notification channel", f"port {port}: {type(e).__name__}: {e}"
            ) from e
        try:
            sock.sendall(handshake)
            header = b""
            sock.settimeout(REACHABILITY_TIMEOUT)
            while b"\r\n\r\n" not in header:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                header += chunk
                if len(header) > 65536:
                    break
            status_line = header.split(b"\r\n", 1)[0].decode(errors="replace")
            if "101" not in status_line:
                raise ProbeError(
                    "notification channel",
                    f"port {port}: handshake rejected: {status_line or 'no response'}",
                )
            sock.settimeout(WEBSOCKET_WAIT)
            try:
                frame = sock.recv(4096)
            except socket.timeout:
                return (
                    f"WebSocket 101 on port {port}; no frame within 3s (silent socket)"
                )
            if frame:
                return (
                    f"WebSocket 101 on port {port}; frame received ({len(frame)} bytes)"
                )
            return f"WebSocket 101 on port {port}; socket closed with no frame"
        except ProbeError:
            raise
        except OSError as e:
            raise ProbeError(
                "notification channel", f"port {port}: {type(e).__name__}: {e}"
            ) from e
        finally:
            sock.close()

    def websocket(self) -> str:
        parts = urllib.parse.urlsplit(self.base)
        host = parts.hostname
        if parts.scheme == "https":
            raise ProbeError(
                "notification channel",
                "script speaks plain ws:// only; host is https",
            )
        configured = parts.port or 80
        candidates = [configured]
        if WS_FALLBACK_PORT not in candidates:
            candidates.append(WS_FALLBACK_PORT)
        errors = []
        for port in candidates:
            try:
                return self._ws_handshake(host, port)
            except ProbeError as e:
                errors.append(e.message)
        raise ProbeError("notification channel", "; ".join(errors))

    # -- probes -------------------------------------------------------------
    def probe_reachability(self) -> str:
        req = urllib.request.Request(self.jsonrpc, method="GET")  # no credentials
        try:
            with urllib.request.urlopen(req, timeout=REACHABILITY_TIMEOUT) as r:
                return f"host answered HTTP {r.status} (no credentials)"
        except urllib.error.HTTPError as e:
            if e.code == 401:
                return "host answered HTTP 401 (reachable, auth required)"
            return f"host answered HTTP {e.code}"
        except Exception as e:  # noqa: BLE001
            raise ProbeError("reachability", f"{type(e).__name__}: {e}") from e

    def probe_credentials(self) -> str:
        self.rpc("JSONRPC.Ping", {}, "credentials")
        props = self.rpc(
            "Application.GetProperties",
            {"properties": ["volume", "muted", "version", "name"]},
            "credentials",
        )
        version = props.get("version", {})
        self.identity = {
            "name": props.get("name", "?"),
            "version": f"{version.get('major', '?')}.{version.get('minor', '?')}",
        }
        return (
            f"JSONRPC.Ping ok; server {self.identity['name']} "
            f"v{self.identity['version']}"
        )

    def probe_library(self) -> str:
        res = self.rpc(
            "VideoLibrary.GetMovies",
            {
                "properties": ["title", "thumbnail", "art"],
                "limits": {"start": 0, "end": 1},
            },
            "library read",
        )
        movies = res.get("movies", [])
        self._movies = movies
        return f"VideoLibrary.GetMovies ok ({len(movies)} item(s) in page)"

    def probe_artwork(self) -> str:
        movies = getattr(self, "_movies", [])
        thumb = ""
        if movies:
            m = movies[0]
            thumb = m.get("thumbnail") or (m.get("art") or {}).get("poster", "")
        if not thumb:
            raise ProbeError("artwork", "no library artwork available to fetch")
        url = self.base + "/image/" + urllib.parse.quote(thumb, safe="")
        req = urllib.request.Request(url, headers={"Authorization": self.auth})
        try:
            with urllib.request.urlopen(req, timeout=RPC_TIMEOUT) as r:
                data = r.read(64)
                ctype = r.headers.get("Content-Type") or "unknown type"
                return f"GET /image/ -> HTTP {r.status}, {ctype}, {len(data)}+ bytes"
        except urllib.error.HTTPError as e:
            raise ProbeError("artwork", f"GET /image/ -> HTTP {e.code}") from e
        except Exception as e:  # noqa: BLE001
            raise ProbeError("artwork", f"{type(e).__name__}: {e}") from e

    def probe_notification(self) -> str:
        return self.websocket()

    def probe_compatibility(self) -> str:
        props = self.rpc(
            "Application.GetProperties",
            {"properties": ["version", "name"]},
            "server compatibility",
        )
        version = props.get("version", {})
        reported = f"{version.get('major', '?')}.{version.get('minor', '?')}"
        if version.get("major") != 21:
            raise ProbeError(
                "server compatibility",
                f"reported Kodi {reported}: outside the verified 21.x baseline",
            )
        return f"reported Kodi {reported} ({props.get('name', '?')})"

    # -- run ----------------------------------------------------------------
    def run(self) -> bool:
        sequence = [
            ("reachability", "reachability", self.probe_reachability),
            ("credentials/identity", "credentials", self.probe_credentials),
            ("library read permission", "library read", self.probe_library),
            ("artwork fetch", "artwork", self.probe_artwork),
            ("notification channel", "notification channel", self.probe_notification),
            ("server compatibility", "server compatibility", self.probe_compatibility),
        ]
        failed = False
        for name, _layer, fn in sequence:
            if failed:
                self.results.append(
                    (name, _layer, "notRun", "skipped: an earlier probe failed")
                )
                print(f"[NOT RUN] {name}: skipped (an earlier probe failed)")
                continue
            try:
                detail = fn()
            except ProbeError as e:
                failed = True
                self.results.append((name, e.layer, "failed", e.message))
                print(f"[FAIL   ] {name}: {e.message}  (layer: {e.layer})")
            else:
                self.results.append((name, _layer, "passed", detail))
                print(f"[PASS   ] {name}: {detail}")
        print()
        passed = sum(1 for *_, state, _ in self.results if state == "passed")
        print(f"{passed}/{len(self.results)} probes passed")
        if self.identity:
            print(f"server: {self.identity['name']} v{self.identity['version']}")
        return not failed


def main() -> int:
    host = os.environ.get("KODI_HOST")
    user = os.environ.get("KODI_USER")
    password = os.environ.get("KODI_PASS")
    for name, value in (
        ("KODI_HOST", host),
        ("KODI_USER", user),
        ("KODI_PASS", password),
    ):
        if not value:
            _fail_env(name)

    base, jsonrpc, _ = split_host(host)
    print(f"host: {base} (credentials supplied via environment, not printed)")
    print()
    runner = Runner(base, jsonrpc, user, password)
    ok = runner.run()
    print()
    print("RESULT: PASS" if ok else "RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
