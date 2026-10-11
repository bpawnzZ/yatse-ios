import Foundation

/// Bonjour discovery.
///
/// Yatse advertises `_xbmc-jsonrpc-h._tcp` (and SSDP `M-SEARCH` for UPnP). SSDP
/// is deliberately not implemented here: iOS gates multicast to
/// 239.255.255.250:1900 behind `com.apple.developer.networking.multicast`, which
/// a free-signed sideload build cannot carry. Bonjour needs no entitlement, only
/// the `NSBonjourServices` Info.plist keys.
struct DiscoveredHost: Identifiable, Hashable {
    let name: String
    let hostName: String
    let port: Int

    var id: String { "\(name)@\(hostName):\(port)" }

    var address: String {
        var value = hostName
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }

    var host: Host {
        Host(name: name.isEmpty ? address : name, address: address, port: port)
    }
}

final class KodiDiscovery: NSObject, ObservableObject {
    @Published private(set) var results: [DiscoveredHost] = []
    @Published private(set) var isSearching = false

    /// One browser per service type — a single `NetServiceBrowser` only tracks
    /// one search at a time, so reusing it silently cancels the first type.
    private let serviceTypes = ["_xbmc-jsonrpc-h._tcp.", "_xbmc-jsonrpc._tcp."]
    private var browsers: [NetServiceBrowser] = []
    private var resolving: [NetService] = []

    func start() {
        stop()
        results = []
        isSearching = true
        browsers = serviceTypes.map { type in
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.schedule(in: .main, forMode: .common)
            browser.searchForServices(ofType: type, inDomain: "local.")
            return browser
        }
    }

    func stop() {
        browsers.forEach { $0.stop() }
        browsers = []
        resolving.forEach { $0.stop() }
        resolving = []
        isSearching = false
    }

    fileprivate func add(_ service: NetService) {
        guard service.port > 0 else { return }
        let found = DiscoveredHost(name: service.name, hostName: service.hostName ?? "", port: service.port)
        guard !found.address.isEmpty, !results.contains(where: { $0.id == found.id }) else { return }
        results.append(found)
    }

    fileprivate func finish(_ service: NetService) {
        resolving.removeAll { $0 === service }
    }
}

extension KodiDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // Bonjour is unavailable (no local-network permission, or nothing to search).
        if browsers.allSatisfy({ $0 === browser }) { isSearching = false }
    }
}

extension KodiDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        add(sender)
        finish(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(sender)
    }
}
