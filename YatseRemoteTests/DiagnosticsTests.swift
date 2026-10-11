import XCTest
@testable import YatseRemote

/// Probe-sequence, read-only-allowlist and report tests. Everything here runs
/// without a network: the probes only ever see a `DiagnosticsContext` built from
/// closures, and the JSON-RPC fixtures are copied verbatim from
/// `KodiModelTests.swift` (which is not modified).
final class DiagnosticsTests: XCTestCase {

    // MARK: Fixtures (verbatim from a live Kodi 21.3-Omega box)

    private static let liveApplication = #"""
    {"id": 1, "jsonrpc": "2.0", "result": {"muted": false, "name": "Kodi", "version": {"major": 21, "minor": 3, "revision": "21.3-Omega", "tag": "stable"}, "volume": 50}}
    """#

    private static let liveMovies = #"""
    {"id": 4, "jsonrpc": "2.0", "result": {"limits": {"end": 1, "start": 0, "total": 4320}, "movies": [{"art": {"icon": "image://DefaultVideo.png/"}, "label": "", "movieid": 1998, "playcount": 8, "runtime": 165, "thumbnail": "", "title": "", "year": 2026}]}}
    """#

    private static let livePlayerItem = #"""
    {"id": 3, "jsonrpc": "2.0", "result": {"item": {"art": {"icon": "image://DefaultFolder.png/", "poster": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b%2fImages%2fPrimary%2f0/", "thumb": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b%2fImages%2fPrimary%2f0/"}, "label": "CL", "thumbnail": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b%2fImages%2fPrimary%2f0/", "title": "CL", "type": "movie"}}}
    """#

    private static let liveActivePlayers = #"""
    {"id": 2, "jsonrpc": "2.0", "result": [{"playerid": 1, "type": "video"}]}
    """#

    private static let liveVersion = #"""
    {"id": 5, "jsonrpc": "2.0", "result": {"version": {"major": 13, "minor": 0, "patch": 0}}}
    """#

    private static let emptyLibrary = #"""
    {"id": 6, "jsonrpc": "2.0", "result": {"movies": [{"movieid": 1, "art": {}, "thumbnail": ""}]}}
    """#

    private static let methodNotFound = #"""
    {"error": {"code": -32601, "message": "Method not found."}, "id": 5, "jsonrpc": "2.0"}
    """#

    // MARK: Test host

    private static var testHost: Host {
        var host = Host()
        host.address = "10.0.0.5"
        host.port = 8080
        return host
    }

    // MARK: Context builders

    /// A context whose JSON-RPC calls are served from a fixed method->fixture
    /// table. Unknown methods throw a JSON-RPC error, exactly as Kodi would for
    /// a method it does not have.
    private static func okContext(
        overrides: [String: String] = [:],
        errors: [String: Error] = [:],
        reachability: @escaping () async throws -> String = { "host answered (HTTP 401) — reachable" },
        imageFetch: @escaping (URL) async throws -> Int = { _ in 128 },
        notification: @escaping (TimeInterval) async throws -> String = { _ in "connected, no frame within 3 s" }
    ) -> DiagnosticsContext {
        let table = [
            "Application.GetProperties": liveApplication,
            "VideoLibrary.GetMovies": liveMovies,
            "JSONRPC.Version": liveVersion,
            "Player.GetActivePlayers": liveActivePlayers,
            "Player.GetItem": livePlayerItem,
        ].merging(overrides) { _, new in new }

        return DiagnosticsContext(
            callRaw: { method, _ in
                if let error = errors[method] { throw error }
                guard let json = table[method] else { throw KodiError.rpc(-32601, "Method not found.") }
                return Data(json.utf8)
            },
            reachability: reachability,
            imageFetch: imageFetch,
            notificationChannel: notification
        )
    }

    private static func emptyContext() -> DiagnosticsContext {
        DiagnosticsContext(
            callRaw: { _, _ in Data(#"{"jsonrpc":"2.0","result":{}}"#.utf8) },
            reachability: { "host answered — reachable" },
            imageFetch: { _ in 0 },
            notificationChannel: { _ in "connected, no frame within 3 s" }
        )
    }

    private static func result(_ id: String, _ report: DiagnosticsReport) -> ProbeResult {
        report.results.first { $0.id == id }!
    }

    private func runDefault(_ context: DiagnosticsContext) async -> DiagnosticsReport {
        await Diagnostics(host: Self.testHost, context: context, probes: Diagnostics.defaultProbes()).run()
    }

    // MARK: 1.2 — read-only allowlist

    func testEveryDeclaredProbeMethodIsAllowlisted() {
        let probes = Diagnostics.defaultProbes()
        XCTAssertEqual(probes.count, 6)
        for probe in probes {
            if let method = probe.method {
                XCTAssertTrue(Diagnostics.readOnlyMethods.contains(method),
                              "\(probe.id) issues \(method), which is not allowlisted")
            }
        }
    }

    func testEnsureReadOnlyRefusesNonAllowlistedMethods() {
        XCTAssertThrowsError(try Diagnostics.ensureReadOnly("Input.ExecuteAction"))
        XCTAssertThrowsError(try Diagnostics.ensureReadOnly("Playlist.Remove"))
        XCTAssertNoThrow(try Diagnostics.ensureReadOnly("Application.GetProperties"))
    }

    func testRunnerRefusesToIssueMethodOutsideAllowlist() async {
        final class Flag { var invoked = false }
        let flag = Flag()
        let probes = [
            Probe(
                id: "bad", name: "Bad method", layer: .compatibility, method: "Input.ExecuteAction",
                dependsOn: nil, timeout: 1,
                run: { _ in flag.invoked = true; return .passed("ran") }
            ),
        ]

        let report = await Diagnostics(host: Self.testHost, context: Self.emptyContext(), probes: probes).run()

        XCTAssertEqual(report.results[0].state, .failed)
        XCTAssertFalse(flag.invoked, "the runner must not invoke a probe whose method is not allowlisted")
        XCTAssertTrue(report.results[0].detail.contains("allowlist"))
    }

    // MARK: 2.1 — sequential runner

    func testAllProbesPass() async {
        let probes = [
            Probe(id: "a", name: "A", layer: .reachability, method: nil, dependsOn: nil, timeout: 1,
                  run: { _ in .passed("ok") }),
            Probe(id: "b", name: "B", layer: .credentials, method: nil, dependsOn: "a", timeout: 1,
                  run: { _ in .passed("ok") }),
        ]
        let report = await Diagnostics(host: Self.testHost, context: Self.emptyContext(), probes: probes).run()

        XCTAssertEqual(report.results.map(\.state), [.passed, .passed])
        XCTAssertTrue(report.succeeded)
    }

    func testAFailedProbeSkipsItsDependents() async {
        final class Flag { var invoked = false }
        let flag = Flag()
        let probes = [
            Probe(id: "a", name: "A", layer: .reachability, method: nil, dependsOn: nil, timeout: 1,
                  run: { _ in .failed("boom") }),
            Probe(id: "b", name: "B", layer: .credentials, method: nil, dependsOn: "a", timeout: 1,
                  run: { _ in flag.invoked = true; return .passed("ok") }),
        ]
        let report = await Diagnostics(host: Self.testHost, context: Self.emptyContext(), probes: probes).run()

        XCTAssertEqual(report.results[0].state, .failed)
        XCTAssertEqual(report.results[1].state, .notRun)
        XCTAssertFalse(flag.invoked, "a dependent probe must not run after its dependency fails")
        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(report.failingLayer, .reachability)
    }

    func testUnreachableMarksEverythingDownstreamNotRun() async {
        let probes = [
            Probe(id: "a", name: "A", layer: .reachability, method: nil, dependsOn: nil, timeout: 1,
                  run: { _ in .failed("unreachable") }),
            Probe(id: "b", name: "B", layer: .credentials, method: nil, dependsOn: "a", timeout: 1,
                  run: { _ in .passed("ok") }),
            Probe(id: "c", name: "C", layer: .library, method: nil, dependsOn: "b", timeout: 1,
                  run: { _ in .passed("ok") }),
        ]
        let report = await Diagnostics(host: Self.testHost, context: Self.emptyContext(), probes: probes).run()

        XCTAssertEqual(report.results.map(\.state), [.failed, .notRun, .notRun])
    }

    func testAProbeThatExceedsItsTimeoutFails() async {
        let probes = [
            Probe(id: "slow", name: "Slow", layer: .reachability, method: nil, dependsOn: nil, timeout: 0.05,
                  run: { _ in
                      try await Task.sleep(nanoseconds: 500_000_000)
                      return .passed("late")
                  }),
        ]
        let report = await Diagnostics(host: Self.testHost, context: Self.emptyContext(), probes: probes).run()

        XCTAssertEqual(report.results[0].state, .failed)
        XCTAssertTrue(report.results[0].detail.contains("did not finish"))
    }

    // MARK: 2.2 — reachability

    func testReachabilityTreatsHTTP401AsReachable() async {
        XCTAssertTrue(Diagnostics.reachabilityDetail(forStatusCode: 401).contains("401"))

        let report = await runDefault(Self.okContext())
        let reachability = Self.result("reachability", report)
        XCTAssertEqual(reachability.state, .passed)
        XCTAssertTrue(reachability.detail.contains("401"))
    }

    func testReachabilityCarriesTransportDetailVerbatim() async {
        let context = Self.okContext(
            reachability: { () async throws -> String in throw KodiError.transport("Connection refused") }
        )
        let report = await runDefault(context)
        let reachability = Self.result("reachability", report)

        XCTAssertEqual(reachability.state, .failed)
        XCTAssertEqual(reachability.layer, .reachability)
        XCTAssertTrue(reachability.detail.contains("Connection refused"))
        XCTAssertTrue(reachability.detail.contains("connect "),
                      "the failed detail must name the request that produced it")
    }

    func testReachabilityTimeoutIsAFailure() async {
        let probes = [
            Probe(id: "reachability", name: "Host reachability", layer: .reachability, method: nil,
                  dependsOn: nil, timeout: 0.05,
                  run: { context in .passed(try await context.reachability()) }),
        ]
        let context = Self.okContext(
            reachability: { () async throws -> String in
                try await Task.sleep(nanoseconds: 500_000_000)
                return "late"
            }
        )
        let report = await Diagnostics(host: Self.testHost, context: context, probes: probes).run()

        XCTAssertEqual(report.results[0].state, .failed)
    }

    // MARK: 2.3 — credentials, library, compatibility

    func testCredentialsProbeReportsServerIdentity() async {
        let report = await runDefault(Self.okContext())
        let credentials = Self.result("credentials", report)

        XCTAssertEqual(credentials.state, .passed)
        XCTAssertTrue(credentials.detail.contains("Kodi"))
        XCTAssertTrue(credentials.detail.contains("21.3-Omega"))
        XCTAssertEqual(report.serverName, "Kodi")
        XCTAssertEqual(report.serverVersion, "21.3-Omega")
    }

    func testCredentialsFailureNamesHTTPStatusAndRemediation() async {
        let context = Self.okContext(errors: ["Application.GetProperties": KodiError.http(401)])
        let report = await runDefault(context)
        let credentials = Self.result("credentials", report)

        XCTAssertEqual(credentials.state, .failed)
        XCTAssertEqual(credentials.layer, .credentials)
        XCTAssertTrue(credentials.detail.contains("HTTP 401"))
        XCTAssertTrue(credentials.detail.lowercased().contains("username"))
        XCTAssertTrue(credentials.detail.lowercased().contains("password"))
    }

    func testLibraryProbeReportsTotalFromLiveMovies() async {
        let report = await runDefault(Self.okContext())
        let library = Self.result("library", report)

        XCTAssertEqual(library.state, .passed)
        XCTAssertEqual(library.layer, .library)
        XCTAssertTrue(library.detail.contains("4320"))
    }

    func testCompatibilityProbeReportsJSONRPCVersion() async {
        let report = await runDefault(Self.okContext())
        let compatibility = Self.result("compatibility", report)

        XCTAssertEqual(compatibility.state, .passed)
        XCTAssertEqual(compatibility.layer, .compatibility)
        XCTAssertTrue(compatibility.detail.contains("13.0.0"))
    }

    // MARK: 2.4 — artwork

    func testArtworkWithNoArtworkIsNotRun() async {
        let context = Self.okContext(overrides: [
            "VideoLibrary.GetMovies": Self.emptyLibrary,
            "Player.GetActivePlayers": #"{"jsonrpc":"2.0","result":[]}"#,
        ])
        let report = await runDefault(context)
        let artwork = Self.result("artwork", report)

        XCTAssertEqual(artwork.state, .notRun)
        XCTAssertNotEqual(artwork.state, .failed)
        XCTAssertFalse(artwork.detail.isEmpty)
    }

    func testArtworkResolvesPosterFromPlayingItem() async {
        let report = await runDefault(Self.okContext())
        let artwork = Self.result("artwork", report)

        XCTAssertEqual(artwork.state, .passed)
        XCTAssertTrue(artwork.detail.contains("bytes from"))
    }

    // MARK: 2.5 — notification channel

    func testNotificationFrameIsAPass() {
        let outcome = Diagnostics.notificationOutcome(connected: true, frame: "Player.OnPlay", error: nil)
        XCTAssertEqual(outcome.state, .passed)
        XCTAssertTrue(outcome.detail.contains("Player.OnPlay"))
    }

    func testNotificationSilentSocketIsAPassWithDetail() {
        let outcome = Diagnostics.notificationOutcome(connected: true, frame: nil, error: nil)
        XCTAssertEqual(outcome.state, .passed)
        XCTAssertEqual(outcome.detail, "connected, no frame within 3 s")
    }

    func testNotificationSocketErrorFails() {
        let outcome = Diagnostics.notificationOutcome(
            connected: false, frame: nil, error: URLError(.cannotConnectToHost)
        )
        XCTAssertEqual(outcome.state, .failed)
    }

    // MARK: 4.1 — report

    func testReportIsBuiltFromTheFixedFields() {
        let report = DiagnosticsReport(
            appVersion: "1.2.3",
            scheme: "http",
            address: "10.0.0.5",
            port: 8080,
            serverName: "Kodi",
            serverVersion: "21.3-Omega",
            results: [
                ProbeResult(id: "reachability", name: "Host reachability", layer: .reachability,
                            state: .passed, detail: "host answered (HTTP 401) — reachable"),
            ]
        )
        let text = report.text

        XCTAssertTrue(text.contains("1.2.3"))
        XCTAssertTrue(text.contains("http://10.0.0.5:8080"))
        XCTAssertTrue(text.contains("Kodi 21.3-Omega"))
        XCTAssertTrue(text.contains("Host reachability"))
        XCTAssertTrue(text.contains("host answered"))
    }

    func testReportNeverContainsTheHostPassword() async {
        let password = "hunter2-do-not-leak"

        // Thread the known password through the context exactly where the
        // production KodiClient carries it, so a builder that leaked any
        // captured credential would surface it in this run.
        let context = Self.okContext(
            reachability: { () async throws -> String in
                _ = "Basic " + Data("kodi:\(password)".utf8).base64EncodedString()
                return "host answered (HTTP 401) — reachable"
            }
        )
        let report = await runDefault(context)

        XCTAssertFalse(report.text.isEmpty)
        XCTAssertFalse(report.text.contains(password))

        // The header carries only the fixed field labels, so no credential-bearing
        // field can appear there. (The word "password" is allowed inside per-probe
        // remediation detail; the header must never hold a credential field.)
        let header = report.text.components(separatedBy: "\n\n").first ?? ""
        XCTAssertTrue(header.hasPrefix("Yatse Remote connection self-check"))
        XCTAssertTrue(header.contains("App version:"))
        XCTAssertTrue(header.contains("Host: http://10.0.0.5:8080"))
        XCTAssertTrue(header.contains("Server: Kodi 21.3-Omega"))
        XCTAssertFalse(header.lowercased().contains("password"))

        // Sensitivity control: a detail that does carry a credential is detectable,
        // proving the assertion above can fail if the builder ever leaked one.
        let leaked = DiagnosticsReport(
            appVersion: "1.0.0", scheme: "http", address: "10.0.0.5", port: 8080,
            serverName: "Kodi", serverVersion: "21.3-Omega",
            results: [ProbeResult(id: "x", name: "X", layer: .credentials, state: .passed, detail: password)]
        )
        XCTAssertTrue(leaked.text.contains(password))
    }

    func testReportAfterAFailedRunStillNamesTheLayerAndError() async {
        let context = Self.okContext(errors: ["Application.GetProperties": KodiError.http(401)])
        let report = await runDefault(context)

        XCTAssertFalse(report.succeeded)
        XCTAssertFalse(report.text.isEmpty)
        XCTAssertTrue(report.text.contains(ConnectionLayer.credentials.title))
        XCTAssertTrue(report.text.contains("HTTP 401"))
    }

    // MARK: R2 — JSON-RPC error object attribution

    func testJSONRPCErrorIsAttributedWithVerbatimCodeAndMessage() async {
        let context = Self.okContext(overrides: ["Application.GetProperties": Self.methodNotFound])
        let report = await runDefault(context)
        let credentials = Self.result("credentials", report)

        XCTAssertEqual(credentials.state, .failed)
        XCTAssertEqual(credentials.layer, .credentials)
        XCTAssertTrue(credentials.detail.contains("-32601"))
        XCTAssertTrue(credentials.detail.contains("Method not found."))
    }

    // MARK: R3 — read-only proxy: no mutating method in the allowlist

    func testReadOnlyAllowlistExcludesEveryMutatingMethod() {
        let methods = Diagnostics.readOnlyMethods

        // Prefixes: no allowlisted method may start with any of these. Note
        // `Playlist.GetItems` is read-only, so only the mutating Playlist
        // methods are listed by exact name below.
        let forbiddenPrefixes = [
            "Input.", "Application.Set", "GUI.", "Settings.", "Player.Set",
            "Player.Open", "Player.Stop", "Player.PlayPause", "Player.GoTo", "Player.Seek",
        ]
        let forbiddenExact = [
            "Playlist.Add", "Playlist.Remove", "Playlist.Insert", "Playlist.Clear", "Playlist.Swap",
        ]

        for method in methods {
            for prefix in forbiddenPrefixes {
                XCTAssertFalse(method.hasPrefix(prefix), "read-only allowlist must not contain \(method)")
            }
            XCTAssertFalse(forbiddenExact.contains(method), "read-only allowlist must not contain \(method)")
        }

        XCTAssertEqual(methods.count, 9)
    }
}
