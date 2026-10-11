import Foundation

/// The six independent layers between the app and a Kodi box. Each failed probe
/// is attributed to exactly one of these, so the report names the layer that
/// broke instead of a symptom.
enum ConnectionLayer: String, CaseIterable, Hashable {
    case reachability
    case credentials
    case library
    case artwork
    case notifications
    case compatibility

    var title: String {
        switch self {
        case .reachability: return "Reachability"
        case .credentials: return "Credentials"
        case .library: return "Library"
        case .artwork: return "Artwork"
        case .notifications: return "Notifications"
        case .compatibility: return "Server compatibility"
        }
    }

    var remediation: String {
        switch self {
        case .reachability:
            return "Check the host IP, port and TLS setting, that Kodi's webserver is enabled, and that the device is on the same network."
        case .credentials:
            return "Check the username and password fields in the host settings."
        case .library:
            return "Check the host user's permissions in Kodi and that a media source is configured."
        case .artwork:
            return "Check that Kodi can reach the artwork source and that the host user may read images."
        case .notifications:
            return "Check that Kodi's webserver is reachable; live updates use the same webserver as JSON-RPC."
        case .compatibility:
            return "Update Kodi to a build that speaks JSON-RPC v13 (Kodi 19 or newer)."
        }
    }
}

enum ProbeState: String, Equatable {
    case passed
    case failed
    case notRun

    var label: String {
        switch self {
        case .passed: return "Passed"
        case .failed: return "Failed"
        case .notRun: return "Not run"
        }
    }
}

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

    static func passed(_ detail: String) -> ProbeOutcome {
        ProbeOutcome(state: .passed, detail: detail)
    }

    static func failed(_ detail: String) -> ProbeOutcome {
        ProbeOutcome(state: .failed, detail: detail)
    }

    static func notRun(_ detail: String) -> ProbeOutcome {
        ProbeOutcome(state: .notRun, detail: detail)
    }
}

/// Everything a probe may do to a host. The production value wraps `KodiClient`
/// and is the single place the read-only allowlist is enforced; tests build one
/// from closures so the runner and probes are exercised without a network.
struct DiagnosticsContext {
    var callRaw: (_ method: String, _ params: [String: Any]) async throws -> Data
    var reachability: () async throws -> String
    var imageFetch: (_ url: URL) async throws -> Int
    var notificationChannel: (_ timeout: TimeInterval) async throws -> String

    func call<T: Decodable>(_ method: String, params: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await callRaw(method, params)
        let envelope: RPCEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(RPCEnvelope<T>.self, from: data)
        } catch {
            throw KodiError.malformedResponse
        }
        if let failure = envelope.error {
            throw KodiError.rpc(failure.code, failure.message)
        }
        guard let result = envelope.result else { throw KodiError.malformedResponse }
        return result
    }

    static func kodi(_ client: KodiClient) -> DiagnosticsContext {
        DiagnosticsContext(
            callRaw: { method, params in
                try Diagnostics.ensureReadOnly(method)
                return try await client.rawCall(method: method, params: params)
            },
            reachability: { try await client.probeReachability() },
            imageFetch: { url in try await client.fetchImage(url) },
            notificationChannel: { timeout in
                try await client.probeNotificationChannel(timeout: timeout)
            }
        )
    }
}

enum DiagnosticsError: LocalizedError, Equatable {
    case methodNotAllowlisted(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .methodNotAllowlisted(let method):
            return "Refused to issue \(method): it is not on the read-only allowlist."
        case .timedOut(let probe):
            return "\(probe) did not finish in time."
        }
    }
}

struct Probe {
    let id: String
    let name: String
    let layer: ConnectionLayer
    /// The read-only JSON-RPC method this probe issues, or nil for the probes
    /// that are not JSON-RPC calls (reachability, artwork, notification channel).
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

    var succeeded: Bool { results.allSatisfy { $0.state == .passed } }
    var failingLayer: ConnectionLayer? { results.first { $0.state == .failed }?.layer }

    /// Assembled from a fixed field list; the host password is not a field and
    /// no probe places it here, so the report cannot carry it.
    var text: String {
        let server = [serverName, serverVersion].filter { !$0.isEmpty }.joined(separator: " ")
        var lines = [
            "Yatse Remote connection self-check",
            "App version: \(appVersion)",
            "Host: \(scheme)://\(address):\(port)",
            "Server: \(server.isEmpty ? "unknown" : server)",
            "Result: \(succeeded ? "all probes passed" : "failed")",
            "",
        ]
        for result in results {
            lines.append("[\(result.state.label)] \(result.name) (\(result.layer.title))")
            if !result.detail.isEmpty { lines.append("    \(result.detail)") }
        }
        return lines.joined(separator: "\n")
    }
}

final class Diagnostics {
    static let readOnlyMethods: Set<String> = [
        "JSONRPC.Ping",
        "JSONRPC.Version",
        "Application.GetProperties",
        "Player.GetActivePlayers",
        "Player.GetItem",
        "Player.GetProperties",
        "Playlist.GetItems",
        "VideoLibrary.GetMovies",
        "AudioLibrary.GetArtists",
    ]

    static let reachabilityTimeout: TimeInterval = 4
    static let rpcTimeout: TimeInterval = 8
    static let socketTimeout: TimeInterval = 3

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    let host: Host
    let probes: [Probe]
    private let context: DiagnosticsContext

    private var scheme: String { host.useTLS ? "https" : "http" }

    init(host: Host, context: DiagnosticsContext, probes: [Probe]? = nil) {
        self.host = host
        self.context = context
        self.probes = probes ?? Diagnostics.defaultProbes()
    }

    func run(progress: (@MainActor (ProbeResult) -> Void)? = nil) async -> DiagnosticsReport {
        _ = progress
        return DiagnosticsReport(
            appVersion: Diagnostics.appVersion,
            scheme: scheme,
            address: host.address,
            port: host.port,
            serverName: "",
            serverVersion: "",
            results: []
        )
    }

    static func defaultProbes() -> [Probe] {
        []
    }

    static func ensureReadOnly(_ method: String) throws {
        guard readOnlyMethods.contains(method) else {
            throw DiagnosticsError.methodNotAllowlisted(method)
        }
    }

    static func withTimeout<T>(
        _ seconds: TimeInterval, probe: String, operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw DiagnosticsError.timedOut(probe)
            }
            guard let result = try await group.next() else {
                throw DiagnosticsError.timedOut(probe)
            }
            group.cancelAll()
            return result
        }
    }

    static func describe(_ error: Error, method: String?, layer: ConnectionLayer) -> String {
        ""
    }

    static func reachabilityDetail(forStatusCode statusCode: Int) -> String {
        ""
    }

    static func notificationOutcome(connected: Bool, frame: String?, error: Error?) -> ProbeOutcome {
        .notRun("stub")
    }
}
