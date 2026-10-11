#!/usr/bin/env python3
"""Print "<name>|<udid>|<runtime>" for the newest available iPhone simulator.

Runtime identifiers look like `com.apple.CoreSimulator.SimRuntime.iOS-26-5`.
Splitting on "." and taking the last component yields "5", which would rank
iOS 18 above iOS 26 — parse the full version instead.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys


def newest_iphone(devices: dict) -> tuple[str, str, str] | None:
    ranked = []
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        usable = [d for d in entries if d.get("isAvailable") and "iPhone" in d.get("name", "")]
        if not usable:
            continue
        match = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
        version = (int(match.group(1)), int(match.group(2) or 0)) if match else (0, 0)
        ranked.append((version, runtime, usable[0]))

    if not ranked:
        return None
    ranked.sort(key=lambda entry: entry[0])
    _, runtime, device = ranked[-1]
    return device["name"], device["udid"], runtime


def main() -> int:
    if len(sys.argv) > 2 and sys.argv[1] == "--fixture":
        payload = json.load(open(sys.argv[2]))
    else:
        raw = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            capture_output=True, text=True, check=True,
        ).stdout
        payload = json.loads(raw)

    found = newest_iphone(payload["devices"])
    if found is None:
        print("no available iPhone simulator", file=sys.stderr)
        return 1

    print("|".join(found))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
