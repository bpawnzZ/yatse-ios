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
    private var context: DiagnosticsContext

    private var scheme: String { host.useTLS ? "https" : "http" }

    init(host: Host, context: DiagnosticsContext, probes: [Probe]? = nil) {
        self.host = host
        self.context = context
        self.probes = probes ?? Diagnostics.defaultProbes()
    }

    func run(progress: (@MainActor (ProbeResult) -> Void)? = nil) async -> DiagnosticsReport {
        var serverName = ""
        var serverVersion = ""

        // The credentials probe already asks for the server identity; observe
        // that same read-only call to fill the report rather than re-issuing it.
        let base = context.callRaw
        context.callRaw = { method, params in
            let data = try await base(method, params)
            if method == "Application.GetProperties",
               let envelope = try? JSONDecoder().decode(RPCEnvelope<ApplicationProperties>.self, from: data),
               let properties = envelope.result {
                serverName = properties.name
                serverVersion = properties.versionLabel
            }
            return data
        }

        var results: [ProbeResult] = []
        var states: [String: ProbeState] = [:]

        for probe in probes {
            var outcome: ProbeOutcome
            if let dependency = probe.dependsOn, states[dependency] != .passed {
                let dependencyState = states[dependency] ?? .notRun
                outcome = .notRun("Skipped: \(dependency) did not pass (\(dependencyState.label.lowercased())).")
            } else if let method = probe.method, !Diagnostics.readOnlyMethods.contains(method) {
                outcome = .failed(Diagnostics.describe(
                    DiagnosticsError.methodNotAllowlisted(method), method: nil, layer: probe.layer
                ))
            } else {
                do {
                    outcome = try await Diagnostics.withTimeout(probe.timeout, probe: probe.name) {
                        try await probe.run(self.context)
                    }
                } catch {
                    outcome = .failed(Diagnostics.describe(
                        error, method: requestDescription(for: probe), layer: probe.layer
                    ))
                }
            }

            states[probe.id] = outcome.state
            let result = ProbeResult(
                id: probe.id, name: probe.name, layer: probe.layer,
                state: outcome.state, detail: outcome.detail
            )
            results.append(result)
            if let progress {
                await MainActor.run { progress(result) }
            }
        }

        return DiagnosticsReport(
            appVersion: Diagnostics.appVersion,
            scheme: scheme,
            address: host.address,
            port: host.port,
            serverName: serverName,
            serverVersion: serverVersion,
            results: results
        )
    }

    static func defaultProbes() -> [Probe] {
        [
            Probe(
                id: "reachability",
                name: "Host reachability",
                layer: .reachability,
                method: nil,
                dependsOn: nil,
                timeout: reachabilityTimeout,
                run: { context in .passed(try await context.reachability()) }
            ),
            Probe(
                id: "credentials",
                name: "Credentials and identity",
                layer: .credentials,
                method: "Application.GetProperties",
                dependsOn: "reachability",
                timeout: rpcTimeout,
                run: { context in
                    let properties = try await context.call(
                        "Application.GetProperties",
                        params: ["properties": ["volume", "muted", "name", "version"]],
                        as: ApplicationProperties.self
                    )
                    let identity = [properties.name, properties.versionLabel]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return .passed(identity.isEmpty ? "credentials accepted" : identity)
                }
            ),
            Probe(
                id: "library",
                name: "Library read permission",
                layer: .library,
                method: "VideoLibrary.GetMovies",
                dependsOn: "credentials",
                timeout: rpcTimeout,
                run: { context in
                    let payload = try await context.call(
                        "VideoLibrary.GetMovies",
                        params: ["properties": ["title"], "limits": ["start": 0, "end": 1]],
                        as: ListPayload.self
                    )
                    let total = payload.limits?.total ?? (payload.movies?.count ?? 0)
                    return .passed("read access — \(total) movies available")
                }
            ),
            Probe(
                id: "artwork",
                name: "Artwork fetch",
                layer: .artwork,
                method: nil,
                dependsOn: "library",
                timeout: rpcTimeout,
                run: { context in
                    guard let url = try await Diagnostics.artworkURL(context) else {
                        return .notRun("No artwork available for the playing or first library item.")
                    }
                    do {
                        let bytes = try await context.imageFetch(url)
                        return .passed("fetched \(bytes) bytes from \(url.absoluteString)")
                    } catch {
                        return .failed(Diagnostics.describe(error, method: url.absoluteString, layer: .artwork))
                    }
                }
            ),
            Probe(
                id: "notifications",
                name: "Notification channel",
                layer: .notifications,
                method: nil,
                dependsOn: "credentials",
                timeout: socketTimeout,
                run: { context in .passed(try await context.notificationChannel(Diagnostics.socketTimeout)) }
            ),
            Probe(
                id: "compatibility",
                name: "Server compatibility",
                layer: .compatibility,
                method: "JSONRPC.Version",
                dependsOn: "credentials",
                timeout: rpcTimeout,
                run: { context in
                    let version = try await context.call("JSONRPC.Version", as: RPCVersion.self)
                    return Diagnostics.compatibilityOutcome(version)
                }
            ),
        ]
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
        let request = method.map { "\($0): " } ?? ""
        return "\(request)\(message(for: error))\n\(layer.remediation)"
    }

    static func message(for error: Error) -> String {
        guard let kodi = error as? KodiError else { return error.localizedDescription }
        switch kodi {
        case .invalidHost: return "host address is not usable"
        case .http(let code): return "HTTP \(code)"
        case .rpc(let code, let message): return "JSON-RPC error \(code): \(message)"
        case .malformedResponse: return "response could not be parsed"
        case .transport(let detail): return detail
        }
    }

    static func reachabilityDetail(forStatusCode statusCode: Int) -> String {
        statusCode == 401
            ? "host answered (HTTP 401) — reachable"
            : "host answered (HTTP \(statusCode)) — reachable"
    }

    static func notificationOutcome(connected: Bool, frame: String?, error: Error?) -> ProbeOutcome {
        if let error { return .failed(error.localizedDescription) }
        guard connected else { return .failed("notification socket did not connect") }
        if let frame { return .passed("connected — received \(frame)") }
        return .passed("connected, no frame within \(Int(Diagnostics.socketTimeout)) s")
    }

    static func compatibilityOutcome(_ version: RPCVersion) -> ProbeOutcome {
        guard version.major > 0 else {
            return .passed("JSON-RPC responded; server did not report a version")
        }
        return .passed("JSON-RPC \(version.major).\(version.minor).\(version.patch)")
    }

    /// Poster of the playing item, else of the first library movie; nil when no
    /// artwork exists anywhere (the caller reports that as `notRun`, never failed).
    static func artworkURL(_ context: DiagnosticsContext) async throws -> URL? {
        let players = (try? await context.call("Player.GetActivePlayers", as: [ActivePlayer].self)) ?? []
        if let player = players.first(where: { $0.isVideo }) ?? players.first,
           let item = (try? await context.call(
               "Player.GetItem",
               params: ["playerid": player.playerid, "properties": ["art", "thumbnail"]],
               as: ItemPayload.self
           ))?.item,
           let url = Artwork.poster(for: item.art, thumbnail: item.thumbnail) {
            return url
        }

        let payload = try await context.call(
            "VideoLibrary.GetMovies",
            params: ["properties": ["art", "thumbnail"], "limits": ["start": 0, "end": 1]],
            as: ListPayload.self
        )
        if let movie = payload.movies?.first,
           let url = Artwork.poster(for: movie.art, thumbnail: movie.thumbnail) {
            return url
        }
        return nil
    }

    private func requestDescription(for probe: Probe) -> String {
        if let method = probe.method { return method }
        switch probe.id {
        case "reachability":
            return "connect \(scheme)://\(host.address):\(host.port)/jsonrpc"
        case "notifications":
            return "socket \(host.useTLS ? "wss" : "ws")://\(host.address):\(host.port)/jsonrpc"
        default:
            return probe.name
        }
    }
}

/// `JSONRPC.Version` result; Kodi may nest it under `version` or return it flat.
struct RPCVersion: Decodable {
    var major = 0
    var minor = 0
    var patch = 0

    private enum Keys: String, CodingKey { case version, major, minor, patch }

    init(major: Int = 0, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if let nested = (try? container.decodeIfPresent(RPCVersion.self, forKey: .version)) ?? nil {
            self = nested
            return
        }
        major = lenient(container, .major, 0)
        minor = lenient(container, .minor, 0)
        patch = lenient(container, .patch, 0)
    }
}
