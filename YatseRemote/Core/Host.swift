import Foundation

/// The outcome of the most recent connection self-check for one host.
///
/// `failingLayer` is the `ConnectionLayer.rawValue` of the first failed probe,
/// or nil when every probe passed. It is deliberately a `String` rather than a
/// `ConnectionLayer`: it keeps persisted host state decoupled from the
/// diagnostics module, and `ConnectionLayer` is not `Codable`.
struct HostCheckSummary: Codable, Hashable {
    var ok: Bool
    var failingLayer: String?
    var date: Date
}

/// A configured media centre.
///
/// Protocol surface recovered from the Yatse 12.0.0 decompile: JSON-RPC 2.0 over
/// HTTP `POST /jsonrpc`, HTTP Basic auth, default port 8080, plaintext HTTP to
/// arbitrary LAN hosts, optional Wake-on-LAN by MAC address.
struct Host: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var address = ""
    var port = 8080
    var username = ""
    var useTLS = false
    var macAddress = ""
    var wolPort = 9

    /// The most recent self-check result, or nil if this host has never been
    /// checked. This MUST stay optional: `HostStore.load()` decodes with `try?`,
    /// so a non-optional field would make every previously-saved host fail to
    /// decode and silently yield an empty host list. Optional stored properties
    /// use `decodeIfPresent` under synthesized `Codable`, so pre-change JSON
    /// (which has no `lastCheck` key) still decodes.
    var lastCheck: HostCheckSummary? = nil

    var displayName: String { name.isEmpty ? address : name }

    /// `URL(string:)` accepts an empty host (`https://:8080/jsonrpc` is a valid
    /// URL object), so the guard has to be here or `KodiError.invalidHost` never
    /// fires and every request goes to a host-less URL.
    var rpcURL: URL? {
        guard isUsable else { return nil }
        return URL(string: "\(useTLS ? "https" : "http")://\(address):\(port)/jsonrpc")
    }

    var socketURL: URL? {
        guard isUsable else { return nil }
        return URL(string: "\(useTLS ? "wss" : "ws")://\(address):\(port)/jsonrpc")
    }

    var isUsable: Bool { !address.isEmpty && (1...65535).contains(port) }
}

// MARK: - Wake-on-LAN

extension Host {
    enum WakeError: LocalizedError {
        case badMac
        case socket(Int32)

        var errorDescription: String? {
            switch self {
            case .badMac: return "MAC address must be 12 hex digits, e.g. AA:BB:CC:DD:EE:FF"
            case .socket(let code): return "Wake-on-LAN send failed (errno \(code))"
            }
        }
    }

    /// Magic packet: six 0xFF bytes then the MAC repeated 16 times, UDP-broadcast.
    func wake() throws {
        let hex = macAddress.filter(\.isHexDigit)
        guard hex.count == 12 else { throw WakeError.badMac }

        var mac: [UInt8] = []
        var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let byte = UInt8(hex[cursor..<next], radix: 16) else { throw WakeError.badMac }
            mac.append(byte)
            cursor = next
        }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: mac) }

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw WakeError.socket(errno) }
        defer { close(fd) }

        var broadcast: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))

        var to = sockaddr_in()
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = in_port_t(UInt16(wolPort).bigEndian)
        to.sin_addr.s_addr = inet_addr("255.255.255.255")

        let sent: Int = packet.withUnsafeBytes { buffer in
            withUnsafePointer(to: &to) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(fd, buffer.baseAddress, packet.count, 0, address,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else { throw WakeError.socket(errno) }
    }
}

// MARK: - Persistence

/// Hosts live in UserDefaults; passwords live in the Keychain (see `Keychain`).
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [Host] = []

    private let defaultsKey = "yatse.hosts.v1"
    private let passwordPrefix = "host-password-"

    init() { load() }

    func upsert(_ host: Host) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        save()
    }

    /// Records the latest self-check outcome for a saved host, matched by id, and
    /// persists it. The check is recorded for a host the caller already holds, so
    /// an unknown id is a no-op rather than an append.
    func recordCheck(for host: Host, summary: HostCheckSummary) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index].lastCheck = summary
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets { Keychain.delete(account: passwordAccount(hosts[index])) }
        hosts.remove(atOffsets: offsets)
        save()
    }

    func password(for host: Host) -> String {
        Keychain.string(account: passwordAccount(host)) ?? ""
    }

    func setPassword(_ password: String, for host: Host) {
        Keychain.set(password, account: passwordAccount(host))
    }

    private func passwordAccount(_ host: Host) -> String {
        passwordPrefix + host.id.uuidString
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Host].self, from: data) else { return }
        hosts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
