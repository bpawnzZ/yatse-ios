import XCTest
@testable import YatseRemote

/// Guards the last-host recall contract: a launch goes back to the host the app
/// last activated instead of asking again, and every way the attempt can fail
/// still ends on the host picker.
///
/// There is no Kodi host here, so "does not answer" is a host on a closed
/// loopback port. The connection is refused at once, which is the same failure
/// path a box that is switched off takes.
final class LastHostRecallTests: XCTestCase {

    /// Matches `Session`'s private `lastHostKey`; mirrors what `load()` reads.
    private static let lastHostKey = "yatse.lastHost.v1"

    /// Nothing answers on loopback port 1.
    private static func unreachableHost(name: String = "Off box") -> Host {
        Host(name: name, address: "127.0.0.1", port: 1)
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.lastHostKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.lastHostKey)
        super.tearDown()
    }

    private func rememberedID() -> UUID? {
        UserDefaults.standard.string(forKey: Self.lastHostKey).flatMap(UUID.init(uuidString:))
    }

    // MARK: 1.1 — the last activated host is recorded

    @MainActor
    func testActivatingAHostRecordsItsID() {
        let session = Session()
        let host = Self.unreachableHost()

        session.activate(host: host, password: "")

        XCTAssertEqual(rememberedID(), host.id)
    }

    @MainActor
    func testSwitchingHostsRecordsTheNewest() {
        let session = Session()
        let first = Self.unreachableHost(name: "First")
        let second = Self.unreachableHost(name: "Second")

        session.activate(host: first, password: "")
        session.activate(host: second, password: "")

        XCTAssertEqual(rememberedID(), second.id)
    }

    // MARK: 1.2 / 1.3 — the remembered host is what a launch attempts

    /// A second `Session` stands in for the next launch: same device, new
    /// process, nothing active.
    @MainActor
    func testAFreshSessionAttemptsTheRememberedHost() async {
        let host = Self.unreachableHost(name: "Off box")
        let first = Session()
        first.activate(host: host, password: "")

        let relaunched = Session()
        await relaunched.restoreLastHost(hosts: [host]) { _ in "" }

        let failure = try? XCTUnwrap(relaunched.launchFailure)
        XCTAssertTrue(failure?.contains("Off box") ?? false,
                      "the attempt must have been for the remembered host")
    }

    /// The fallback: a remembered host that will not answer ends on the picker
    /// with the reason, not on an empty shell.
    @MainActor
    func testARememberedHostThatDoesNotAnswerFallsBackToThePicker() async {
        let host = Self.unreachableHost()
        let session = Session()
        UserDefaults.standard.set(host.id.uuidString, forKey: Self.lastHostKey)

        await session.restoreLastHost(hosts: [host]) { _ in "" }

        XCTAssertNil(session.model, "the picker is what shows when model is nil")
        XCTAssertNotNil(session.launchFailure)
    }

    @MainActor
    func testNothingRememberedIsNotAttempted() async {
        let session = Session()

        await session.restoreLastHost(hosts: [Self.unreachableHost()]) { _ in "" }

        XCTAssertNil(session.model)
        XCTAssertNil(session.launchFailure, "nothing failed, so nothing may be reported")
    }

    @MainActor
    func testARememberedHostThatIsNoLongerSavedIsNotAttempted() async {
        let deleted = Self.unreachableHost(name: "Deleted")
        let survivor = Self.unreachableHost(name: "Survivor")
        UserDefaults.standard.set(deleted.id.uuidString, forKey: Self.lastHostKey)

        let session = Session()
        await session.restoreLastHost(hosts: [survivor]) { _ in "" }

        XCTAssertNil(session.model)
        XCTAssertNil(session.launchFailure)
    }

    @MainActor
    func testAnUnusableRememberedHostIsNotAttempted() async {
        let typo = Host(name: "Typo", address: "", port: 8080)
        UserDefaults.standard.set(typo.id.uuidString, forKey: Self.lastHostKey)

        let session = Session()
        await session.restoreLastHost(hosts: [typo]) { _ in "" }

        XCTAssertNil(session.model)
        XCTAssertNil(session.launchFailure)
    }

    /// The attempt is once per launch: a second call must not retry, or a host
    /// that is down would loop against the picker it produces.
    @MainActor
    func testTheLaunchAttemptHappensOnlyOnce() async {
        let first = Self.unreachableHost(name: "First")
        let second = Self.unreachableHost(name: "Second")
        let session = Session()
        UserDefaults.standard.set(second.id.uuidString, forKey: Self.lastHostKey)

        await session.restoreLastHost(hosts: [first, second]) { _ in "" }
        XCTAssertTrue(session.launchFailure?.contains("Second") ?? false)

        // Point the memory at the other host, then call again: a second attempt
        // would report the first one instead.
        UserDefaults.standard.set(first.id.uuidString, forKey: Self.lastHostKey)
        await session.restoreLastHost(hosts: [first, second]) { _ in "" }

        XCTAssertTrue(session.launchFailure?.contains("Second") ?? false,
                      "a second attempt was made in the same launch")
    }

    // MARK: 2.1 / 2.2 — choosing a host by hand

    @MainActor
    func testChoosingAHostClearsTheLaunchFailure() async {
        let dead = Self.unreachableHost()
        let session = Session()
        UserDefaults.standard.set(dead.id.uuidString, forKey: Self.lastHostKey)

        await session.restoreLastHost(hosts: [dead]) { _ in "" }
        XCTAssertNotNil(session.launchFailure)

        let chosen = Self.unreachableHost(name: "Chosen")
        session.activate(host: chosen, password: "")

        XCTAssertNil(session.launchFailure)
    }

    /// A host chosen while the launch attempt is still in flight is the newer
    /// answer, and the failed attempt must not tear it down. Whichever side of
    /// the attempt the choice lands on, the choice stands.
    @MainActor
    func testAFailureDoesNotTearDownAHostChosenDuringTheAttempt() async {
        let dead = Self.unreachableHost(name: "Off box")
        let chosen = Self.unreachableHost(name: "Chosen")
        let session = Session()
        UserDefaults.standard.set(dead.id.uuidString, forKey: Self.lastHostKey)

        let attempt = Task { await session.restoreLastHost(hosts: [dead]) { _ in "" } }
        await Task.yield()
        session.activate(host: chosen, password: "")
        await attempt.value

        XCTAssertEqual(session.host?.id, chosen.id, "the newer choice must stand")
    }
}
