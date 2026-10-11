# Clean-room notes

## Source of the specification

Everything this app does was specified from static analysis of the shipped
Yatse 12.0.0 APK, plus the public Kodi JSON-RPC API documentation. The report is
kept with the artifact:

```
~/reverseEngineer/yatse/REPORT.md
```

What was extracted from the APK, and nothing more:

- **Protocol surface** — the set of literal JSON-RPC method names present in the
  DEX, the item/property names passed in `properties` arrays, the
  `Input.ExecuteAction` action names used by the remote, and the default ports.
- **Declarations** — `AndroidManifest.xml` package/component/permission data.
- **User-facing strings** — used only to enumerate *which features exist* for
  the scope decision in `REPORT.md` §"Feature inventory". No string table is
  reproduced here.
- **Discovery records** — the Bonjour service types and the SSDP `M-SEARCH`
  shape.
- **Network policy** — that the app permits cleartext HTTP to arbitrary LAN
  hosts and only pins `yatse.tv` to TLS.

## What is not in this repository

- No decompiled Java or Kotlin source, in whole or in part.
- No Yatse resources: no drawables, no layouts, no icons, no sounds, no
  translations.
- No Yatse code paths transcribed. The Swift files were written from the
  interface description above and from Kodi's own published API schema.
- No Yatse trademarks, package names, or branding.

The bundle identifier is `com.bpawnzz.yatseremote`, the icon is an empty asset
slot, and the accent colour is a stock asset — there is nothing to confuse with
the original app.

## Where the interface knowledge actually came from

Kodi's JSON-RPC API is public and documented; Yatse's choice of *which* methods
to call, *which* properties to request, and *which* action names to send is the
part that took analysis. That analysis is recorded as evidence in `REPORT.md`,
including the live validation run against a Kodi 21.3 box
(`probe-evidence.txt`, 11 of 12 payload shapes accepted) which also disproved
one method the APK still references.

## Verifying parity

Behavioural parity means: point the app at a Kodi box, and every button does what
Yatse's equivalent button does. The remote action names in
`AppModel.key(_:)` are the exact literals recovered from the APK, so the mapping
is checkable one button at a time.
