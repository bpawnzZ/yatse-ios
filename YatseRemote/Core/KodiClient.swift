import Foundation

enum KodiError: LocalizedError {
    case invalidHost
    case http(Int)
    case rpc(Int, String)
    case malformedResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Host address is not usable — check the IP and port."
        case .http(401):
            return "Kodi rejected those credentials (HTTP 401)."
        case .http(let code):
            return "Kodi returned HTTP \(code)."
        case .rpc(_, let message):
            return message
        case .malformedResponse:
            return "Kodi returned a response this app could not parse."
        case .transport(let detail):
            return detail
        }
    }
}

/// Kodi JSON-RPC 2.0 client: `POST /jsonrpc` over HTTP with Basic auth, plus the
/// same endpoint upgraded to a WebSocket for `Player.OnPlay`-style notifications.
///
/// `System.FriendlyName` is deliberately absent: it was in the Yatse
/// 12.0.0 method table but Kodi 21.3 answers `-32601 Method not found`, so the
/// name comes from `Application.GetProperties` instead.
final class KodiClient {
    /// Emitted on the event stream when the socket drops.
    static let streamClosedEvent = "__stream_closed__"

    let host: Host
    private let username: String
    private let password: String
    private let session: URLSession
    private let idLock = NSLock()
    private var nextID = 0
    private var socket: URLSessionWebSocketTask?

    init(host: Host, username: String, password: String) {
        self.host = host
        self.username = username
        self.password = password

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    deinit { socket?.cancel(with: .goingAway, reason: nil) }

    // MARK: Request plumbing

    private func takeID() -> Int {
        idLock.lock()
        defer { idLock.unlock() }
        nextID += 1
        return nextID
    }

    private func authorizationHeader() -> String? {
        guard !username.isEmpty || !password.isEmpty else { return nil }
        return "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    private func makeRequest(method: String, params: [String: Any]) throws -> URLRequest {
        guard let url = host.rpcURL else { throw KodiError.invalidHost }

        var body: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": takeID()]
        if !params.isEmpty { body["params"] = params }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let header = authorizationHeader() {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Transport + HTTP status, without decoding. The diagnostics layer is the
    /// only caller with a reason to see raw bytes.
    func rawCall(method: String, params: [String: Any]) async throws -> Data {
        let request = try makeRequest(method: method, params: params)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw KodiError.transport(error.localizedDescription)
        }

        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KodiError.http(http.statusCode)
        }
        return result.0
    }

    @discardableResult
    func call<T: Decodable>(_ method: String, params: [String: Any] = [:], as type: T.Type) async throws -> T {
        let data = try await rawCall(method: method, params: params)

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

    /// One type covers every list-returning method; the caller picks the key.
    func list(method: String, params: [String: Any] = [:]) async throws -> ListPayload {
        try await call(method, params: params, as: ListPayload.self)
    }

    // MARK: Typed helpers

    func ping() async throws {
        _ = try await call("JSONRPC.Ping", as: String.self)
    }

    func applicationProperties() async throws -> ApplicationProperties {
        try await call(
            "Application.GetProperties",
            params: ["properties": ["volume", "muted", "name", "version"]],
            as: ApplicationProperties.self
        )
    }

    func activePlayers() async throws -> [ActivePlayer] {
        try await call("Player.GetActivePlayers", as: [ActivePlayer].self)
    }

    func playerProperties(playerid: Int) async throws -> PlayerProperties {
        try await call(
            "Player.GetProperties",
            params: [
                "playerid": playerid,
                "properties": [
                    "time", "totaltime", "percentage", "speed", "position", "playlistid",
                    "repeat", "shuffled", "partymode", "audiostreams", "currentaudiostream",
                    "subtitles", "currentsubtitle",
                ],
            ],
            as: PlayerProperties.self
        )
    }

    func currentItem(playerid: Int) async throws -> PlayerItem {
        // Kodi wraps this one: `result` is `{"item": {...}}`, not the item itself.
        let payload = try await call(
            "Player.GetItem",
            params: [
                "playerid": playerid,
                "properties": [
                    "title", "artist", "album", "thumbnail", "fanart", "showtitle",
                    "season", "episode", "runtime", "file", "art",
                    "plot", "year", "genre",
                ],
            ],
            as: ItemPayload.self
        )
        return payload.item
    }

    /// Fetches the entire queue. Yatse shows every entry, so no truncation here.
    func playlistItems(playlistid: Int, pageSize: Int = 200) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var total = Int.max

        while items.count < total {
            let page = try await list(
                method: "Playlist.GetItems",
                params: [
                    "playlistid": playlistid,
                    "properties": ["title", "artist", "album", "thumbnail", "runtime", "showtitle"],
                    "limits": ["start": items.count, "end": items.count + pageSize],
                ]
            )
            let batch = page.items ?? []
            items.append(contentsOf: batch)
            total = page.limits?.total ?? batch.count
            if batch.isEmpty { break }
        }

        return items
    }

    // MARK: Add-ons and files

    /// Every installed add-on, enabled or not. `enabled` comes back as a real
    /// boolean on Kodi 19+ (verified live on 21.3), so no filter is needed here
    /// to see disabled ones.
    func addons() async throws -> [Addon] {
        let payload = try await list(
            method: "Addons.GetAddons",
            params: [
                "properties": ["name", "version", "enabled", "summary", "description",
                               "thumbnail", "author", "broken"],
            ]
        )
        return payload.addons ?? []
    }

    func setAddonEnabled(addonid: String, enabled: Bool) async throws {
        _ = try await call(
            "Addons.SetAddonEnabled",
            params: ["addonid": addonid, "enabled": enabled],
            as: IgnoreResult.self
        )
    }

    /// The configured media sources — the roots a directory browser starts from.
    func sources(media: String) async throws -> [MediaItem] {
        let payload = try await list(method: "Files.GetSources", params: ["media": media])
        return payload.sources ?? []
    }

    func directory(_ path: String, media: String) async throws -> [MediaItem] {
        let payload = try await list(
            method: "Files.GetDirectory",
            params: [
                "directory": path,
                "media": media,
                "properties": ["title", "thumbnail", "art", "file", "filetype", "runtime"],
            ]
        )
        return payload.files ?? []
    }

    // MARK: Diagnostics probes

    /// Unauthenticated connect: any HTTP response — including 401 — proves the
    /// host answered. Transport failures are preserved verbatim.
    func probeReachability() async throws -> String {
        guard let url = host.rpcURL else { throw KodiError.invalidHost }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Diagnostics.reachabilityTimeout

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw KodiError.transport(error.localizedDescription)
        }

        guard let http = result.1 as? HTTPURLResponse else { return "host answered" }
        return Diagnostics.reachabilityDetail(forStatusCode: http.statusCode)
    }

    /// Authenticated fetch of a Kodi `/image/` URL — the same path `ArtworkImage`
    /// uses. Returns the number of bytes received.
    @discardableResult
    func fetchImage(_ url: URL) async throws -> Int {
        var request = URLRequest(url: url)
        if let header = authorizationHeader() {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw KodiError.transport(error.localizedDescription)
        }

        if let http = result.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KodiError.http(http.statusCode)
        }
        return result.0.count
    }

    /// Opens the notification socket and waits up to `timeout` for a frame. A
    /// connected socket that stays silent is not an error — Kodi sends nothing
    /// while idle — so only a socket error fails.
    func probeNotificationChannel(timeout: TimeInterval) async throws -> String {
        guard let url = host.socketURL else { throw KodiError.invalidHost }

        var request = URLRequest(url: url)
        if let header = authorizationHeader() {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        do {
            let message = try await Diagnostics.withTimeout(timeout, probe: "Notification channel") {
                try await task.receive()
            }
            let text: String
            switch message {
            case .string(let value): text = value
            case .data(let value): text = String(decoding: value, as: UTF8.self)
            @unknown default: text = ""
            }
            return Diagnostics.notificationOutcome(connected: true, frame: notificationName(in: text), error: nil).detail
        } catch let error as DiagnosticsError {
            if case .timedOut = error {
                return Diagnostics.notificationOutcome(connected: true, frame: nil, error: nil).detail
            }
            throw error
        } catch {
            throw KodiError.transport(error.localizedDescription)
        }
    }

    // MARK: Notifications

    /// Subscribes to Kodi's notification stream. `onEvent` receives the
    /// notification method name, or `streamClosedEvent` when the socket dies.
    func startEventStream(onEvent: @escaping (String) -> Void) {
        stopEventStream()
        guard let url = host.socketURL else { return }

        var request = URLRequest(url: url)
        if let header = authorizationHeader() {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()

        Task.detached { [weak self] in
            while true {
                do {
                    let message = try await task.receive()
                    guard let self else { return }
                    let text: String
                    switch message {
                    case .string(let value): text = value
                    case .data(let value): text = String(decoding: value, as: UTF8.self)
                    @unknown default: continue
                    }
                    if let name = self.notificationName(in: text) { onEvent(name) }
                } catch {
                    onEvent(Self.streamClosedEvent)
                    return
                }
            }
        }
    }

    func stopEventStream() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    /// Kodi interleaves responses with notifications on the same socket; only
    /// notifications carry a `method` field, and responses must be matched by `id`.
    func notificationName(in text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else { return nil }
        return method
    }
}

// MARK: - Application properties

struct ApplicationProperties: Decodable {
    var volume = 0
    var muted = false
    var name = ""
    var versionLabel = ""

    enum CodingKeys: String, CodingKey { case volume, muted, name, version }
}

extension ApplicationProperties {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = lenient(container, .volume, 0)
        muted = lenient(container, .muted, false)
        name = lenient(container, .name, "")
        versionLabel = lenient(container, .version, VersionLabel(text: "")).text
    }
}

/// `version` is an object on Kodi 19+ and a bare string on older builds.
struct VersionLabel: Decodable {
    var text: String

    init(text: String) { self.text = text }

    enum Key: String, CodingKey { case major, minor, revision, tag }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let plain = try? container.decode(String.self) {
            text = plain
            return
        }
        let container = try decoder.container(keyedBy: Key.self)
        let major = lenient(container, .major, 0)
        let minor = lenient(container, .minor, 0)
        let revision = lenient(container, .revision, "")
        text = revision.isEmpty ? "\(major).\(minor)" : revision
    }
}
