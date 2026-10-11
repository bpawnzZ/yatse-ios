import XCTest
@testable import YatseRemote

/// Covers the host-row status mapping (task 4.3): never checked, failed with a
/// named layer, and reachable, plus the report → persisted-summary mapping that
/// the sheet uses so the sheet and the row cannot disagree.
final class DiagnosticsStatusTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 0)

    // MARK: Never checked

    func testNeverCheckedHasNoLayerAndNoTimestamp() {
        let status = HostCheckStatus(summary: nil)

        XCTAssertEqual(status.state, .neverChecked)
        XCTAssertNil(status.layerTitle)
        XCTAssertNil(status.timestamp)
        XCTAssertNil(status.rowDetail)
        XCTAssertEqual(status.label, "Not checked")
    }

    // MARK: Failed

    func testFailedNamesTheLayerAndShowsTheTimestamp() {
        let summary = HostCheckSummary(ok: false, failingLayer: "credentials", date: epoch)
        let status = HostCheckStatus(summary: summary)

        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.layerTitle, "Credentials")
        XCTAssertEqual(status.label, "Failed — Credentials")
        XCTAssertEqual(status.rowDetail, "1970-01-01 00:00")
    }

    func testFailedWithUnknownLayerFallsBackToTheRawValue() {
        let summary = HostCheckSummary(ok: false, failingLayer: "future-layer", date: epoch)
        let status = HostCheckStatus(summary: summary)

        XCTAssertEqual(status.state, .failed)
        XCTAssertEqual(status.layerTitle, "future-layer")
        XCTAssertEqual(status.label, "Failed — future-layer")
    }

    // MARK: Reachable

    func testReachableShowsTheTimestamp() {
        let summary = HostCheckSummary(ok: true, failingLayer: nil, date: epoch)
        let status = HostCheckStatus(summary: summary)

        XCTAssertEqual(status.state, .reachable)
        XCTAssertNil(status.layerTitle)
        XCTAssertEqual(status.label, "Reachable")
        XCTAssertEqual(status.rowDetail, "1970-01-01 00:00")
    }

    // MARK: Timestamp formatting

    func testTimestampFormattingIsDeterministicUTC() {
        XCTAssertEqual(HostCheckStatus.timestamp(epoch), "1970-01-01 00:00")
        XCTAssertEqual(
            HostCheckStatus.timestamp(Date(timeIntervalSince1970: 86_400)),
            "1970-01-02 00:00"
        )
    }

    // MARK: Report → persisted summary (the shared mapping)

    func testReportMappingPersistsAFailedLayer() {
        let report = makeReport(failing: .credentials)
        let summary = HostCheckStatus.summary(for: report, date: epoch)

        XCTAssertFalse(summary.ok)
        XCTAssertEqual(summary.failingLayer, "credentials")
        XCTAssertEqual(summary.date, epoch)

        // The row renders the same summary the sheet persisted.
        XCTAssertEqual(HostCheckStatus(summary: summary).label, "Failed — Credentials")
    }

    func testReportMappingPersistsSuccess() {
        let report = makeReport(failing: nil)
        let summary = HostCheckStatus.summary(for: report, date: epoch)

        XCTAssertTrue(summary.ok)
        XCTAssertNil(summary.failingLayer)
        XCTAssertEqual(HostCheckStatus(summary: summary).state, .reachable)
    }

    // MARK: Helpers

    private func makeReport(failing: ConnectionLayer?) -> DiagnosticsReport {
        var results = [
            ProbeResult(id: "reachability", name: "Host reachability",
                        layer: .reachability, state: .passed, detail: "host answered"),
        ]
        if let failing {
            results.append(
                ProbeResult(id: "credentials", name: "Credentials and identity",
                            layer: failing, state: .failed, detail: "HTTP 401")
            )
        }
        return DiagnosticsReport(
            appVersion: "1.0.0",
            scheme: "http",
            address: "10.0.0.1",
            port: 8080,
            serverName: "Kodi",
            serverVersion: "21.3",
            results: results
        )
    }
}
