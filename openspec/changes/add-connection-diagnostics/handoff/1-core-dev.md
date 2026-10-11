# handoff 1 — core-dev — FROZEN type surface

- **task:** 1.1 (probe model, layers, result states, allowlist) + shared surface for 1.2 / 2.1–2.5 / 4.1
- **state:** type surface written, committed, compiler-UNVERIFIED (no Swift toolchain locally); FROZEN pending CI
- **files touched:** `YatseRemote/Core/Diagnostics.swift` (new), `YatseRemote/Core/KodiClient.swift` (added `rawCall`, `probeReachability`, `fetchImage`, `probeNotificationChannel`; refactored `call` to decode via `rawCall` behaviourally unchanged)
- **command run:** `git commit -q -m "diagnostics: type surface (probe model, runner entry, KodiClient probe ops)"`
- **verbatim output:** `c981f0c diagnostics: type surface (probe model, runner entry, KodiClient probe ops)`
- **blocker:** none
- **needed from:** `persistence-dev` (3.1/3.2 Host.lastCheck) and `ui-dev` (4.2/4.3 DiagnosticsView, entry points) code against this frozen surface. Do NOT rename or re-parent any declaration below without messaging the lead first.

## FROZEN surface (verbatim declarations from Diagnostics.swift)

```swift
enum ConnectionLayer: String, CaseIterable, Hashable {
    case reachability, credentials, library, artwork, notifications, compatibility
    var title: String
    var remediation: String
}

enum ProbeState: String, Equatable { case passed, failed, notRun; var label: String }

struct ProbeResult: Identifiable, Equatable {
    let id: String
    let name: String
    let layer: ConnectionLayer
    let state: ProbeState
    let detail: String
}

struct ProbeOutcome: Equatable {
    let state: ProbeState
    let detail: String
    static func passed(_ detail: String) -> ProbeOutcome
    static func failed(_ detail: String) -> ProbeOutcome
    static func notRun(_ detail: String) -> ProbeOutcome
}

struct DiagnosticsContext {
    var callRaw: (_ method: String, _ params: [String: Any]) async throws -> Data
    var reachability: () async throws -> String
    var imageFetch: (_ url: URL) async throws -> Int
    var notificationChannel: (_ timeout: TimeInterval) async throws -> String
    func call<T: Decodable>(_ method: String, params: [String: Any], as: T.Type) async throws -> T
    static func kodi(_ client: KodiClient) -> DiagnosticsContext
}

enum DiagnosticsError: LocalizedError, Equatable {
    case methodNotAllowlisted(String)
    case timedOut(String)
}

struct Probe {
    let id: String
    let name: String
    let layer: ConnectionLayer
    let method: String?
    let dependsOn: String?
    let timeout: TimeInterval
    let run: (DiagnosticsContext) async throws -> ProbeOutcome
}

struct DiagnosticsReport: Equatable {
    let appVersion: String
    let scheme: String
    let address: String
    let port: Int
    let serverName: String
    let serverVersion: String
    let results: [ProbeResult]
    var succeeded: Bool
    var failingLayer: ConnectionLayer?
    var text: String
}

final class Diagnostics {
    static let readOnlyMethods: Set<String>
    static let reachabilityTimeout: TimeInterval = 4
    static let rpcTimeout: TimeInterval = 8
    static let socketTimeout: TimeInterval = 3
    static var appVersion: String
    let host: Host
    let probes: [Probe]
    init(host: Host, context: DiagnosticsContext, probes: [Probe]? = nil)
    func run(progress: (@MainActor (ProbeResult) -> Void)? = nil) async -> DiagnosticsReport
    static func defaultProbes() -> [Probe]
    static func ensureReadOnly(_ method: String) throws
    static func withTimeout<T>(_ seconds: TimeInterval, probe: String,
                               operation: @escaping () async throws -> T) async throws -> T
    static func describe(_ error: Error, method: String?, layer: ConnectionLayer) -> String
    static func reachabilityDetail(forStatusCode statusCode: Int) -> String
    static func notificationOutcome(connected: Bool, frame: String?, error: Error?) -> ProbeOutcome
}
```

## KodiClient additions (frozen)

```swift
func rawCall(method: String, params: [String: Any]) async throws -> Data
func probeReachability() async throws -> String
@discardableResult func fetchImage(_ url: URL) async throws -> Int
func probeNotificationChannel(timeout: TimeInterval) async throws -> String
```

## Allowlist
`JSONRPC.Ping`, `JSONRPC.Version`, `Application.GetProperties`, `Player.GetActivePlayers`, `Player.GetItem`, `Player.GetProperties`, `Playlist.GetItems`, `VideoLibrary.GetMovies`, `AudioLibrary.GetArtists`

## defaultProbes() order (id / method / dependsOn / timeout)
1 `reachability` / nil / nil / 4 · 2 `credentials` / `Application.GetProperties` / reachability / 8 · 3 `library` / `VideoLibrary.GetMovies` / credentials / 8 · 4 `artwork` / nil / library / 8 · 5 `notifications` / nil / credentials / 3 · 6 `compatibility` / `JSONRPC.Version` / credentials / 8
