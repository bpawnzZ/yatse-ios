import XCTest
@testable import YatseRemote

/// Guards the host-persistence contract added for connection diagnostics.
///
/// The highest-consequence risk in this change is a required new field on
/// `Host`: `HostStore.load()` decodes `[Host]` with `try?`, so a non-optional
/// field would make every previously-saved host fail to decode and silently
/// empty the user's host list. The pre-change fixture tests below are the guard
/// for that, not a formality.
final class HostPersistenceTests: XCTestCase {

    /// Matches `HostStore`'s private `defaultsKey`; mirrors what `load()` reads.
    private static let hostsKey = "yatse.hosts.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.hostsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.hostsKey)
        super.tearDown()
    }

    // MARK: 3.1 — pre-change hosts must still decode

    /// Verbatim `Host` JSON as persisted before `lastCheck` existed: no
    /// `lastCheck` key. This is the array shape `HostStore.load()` reads.
    private static let preChangeHosts = #"""
    [{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Living room","address":"10.13.13.7","port":8080,"username":"kodi","useTLS":false,"macAddress":"AA:BB:CC:DD:EE:FF","wolPort":9},{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","name":"","address":"10.0.0.20","port":9090,"username":"","useTLS":true,"macAddress":"","wolPort":9}]
    """#

    func testDecodesPreChangeHostsWithoutLastCheck() throws {
        let hosts = try JSONDecoder().decode([Host].self, from: Data(Self.preChangeHosts.utf8))

        XCTAssertEqual(hosts.count, 2)
        XCTAssertNil(hosts[0].lastCheck)
        XCTAssertNil(hosts[1].lastCheck)
        XCTAssertEqual(hosts[0].id, UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        XCTAssertEqual(hosts[0].name, "Living room")
        XCTAssertEqual(hosts[0].address, "10.13.13.7")
        XCTAssertEqual(hosts[0].port, 8080)
        XCTAssertEqual(hosts[0].username, "kodi")
        XCTAssertFalse(hosts[0].useTLS)
        XCTAssertEqual(hosts[0].macAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(hosts[0].wolPort, 9)
        XCTAssertTrue(hosts[1].useTLS)
        XCTAssertEqual(hosts[1].port, 9090)
    }

    /// A single pre-change host decodes and is still usable afterwards.
    func testPreChangeHostRemainsUsable() throws {
        let host = try JSONDecoder().decode(Host.self, from: Data(#"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Living room","address":"10.13.13.7","port":8080,"username":"kodi","useTLS":false,"macAddress":"","wolPort":9}
        """#.utf8))

        XCTAssertNil(host.lastCheck)
        XCTAssertEqual(host.rpcURL?.absoluteString, "http://10.13.13.7:8080/jsonrpc")
    }

    // MARK: 3.2 — record a check and read it back through HostStore

    @MainActor
    func testRecordCheckPersistsAndReloads() throws {
        let host = Host(name: "Kitchen", address: "10.0.0.5", port: 8080)
        let store = HostStore()
        store.upsert(host)

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordCheck(for: host,
                          summary: HostCheckSummary(ok: false,
                                                    failingLayer: ConnectionLayer.credentials.rawValue,
                                                    date: when))

        let saved = try XCTUnwrap(store.hosts.first { $0.id == host.id })
        XCTAssertEqual(saved.lastCheck?.ok, false)
        XCTAssertEqual(saved.lastCheck?.failingLayer, ConnectionLayer.credentials.rawValue)

        // A fresh store reads it back through `load()`.
        let reloaded = HostStore()
        let persisted = try XCTUnwrap(reloaded.hosts.first { $0.id == host.id })
        XCTAssertEqual(persisted.lastCheck?.ok, false)
        XCTAssertEqual(persisted.lastCheck?.failingLayer, ConnectionLayer.credentials.rawValue)
        XCTAssertEqual(try XCTUnwrap(persisted.lastCheck).date.timeIntervalSince1970,
                       when.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testRecordCheckKeepsLatestResultOnly() throws {
        let host = Host(name: "Study", address: "10.0.0.9", port: 8080)
        let store = HostStore()
        store.upsert(host)

        store.recordCheck(for: host,
                          summary: HostCheckSummary(ok: false,
                                                    failingLayer: ConnectionLayer.reachability.rawValue,
                                                    date: Date(timeIntervalSince1970: 1_600_000_000)))
        store.recordCheck(for: host,
                          summary: HostCheckSummary(ok: true,
                                                    failingLayer: nil,
                                                    date: Date(timeIntervalSince1970: 1_600_000_100)))

        let saved = try XCTUnwrap(store.hosts.first { $0.id == host.id })
        XCTAssertEqual(saved.lastCheck?.ok, true)
        XCTAssertNil(saved.lastCheck?.failingLayer)
        XCTAssertEqual(store.hosts.count, 1, "recording a check must not append a host")
    }

    @MainActor
    func testRecordCheckIgnoresUnknownHost() {
        let store = HostStore()
        store.recordCheck(for: Host(name: "Ghost", address: "10.0.0.1", port: 8080),
                          summary: HostCheckSummary(ok: true, failingLayer: nil, date: Date()))

        XCTAssertTrue(store.hosts.isEmpty)
    }
}
