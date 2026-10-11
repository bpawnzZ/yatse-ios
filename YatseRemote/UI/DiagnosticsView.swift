import SwiftUI
import UIKit

/// Row-level presentation of the last persisted check for one host.
///
/// The mapping from the stored `HostCheckSummary` to a row label lives in this
/// pure value type, so the host row, the sheet, and `DiagnosticsStatusTests`
/// all share exactly one implementation and cannot drift apart.
struct HostCheckStatus: Equatable {
    enum State: Equatable {
        case neverChecked
        case failed
        case reachable
    }

    let state: State
    /// Display title of the layer that failed, e.g. "Credentials".
    let layerTitle: String?
    let date: Date?

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    init(summary: HostCheckSummary?) {
        guard let summary else {
            state = .neverChecked
            layerTitle = nil
            date = nil
            return
        }
        date = summary.date
        if summary.ok {
            state = .reachable
            layerTitle = nil
        } else {
            state = .failed
            // Prefer the human title; fall back to the raw value so a layer
            // added later is still named rather than swallowed.
            layerTitle = summary.failingLayer.map { raw in
                ConnectionLayer(rawValue: raw)?.title ?? raw
            }
        }
    }

    var label: String {
        switch state {
        case .neverChecked: return "Not checked"
        case .reachable: return "Reachable"
        case .failed: return "Failed — \(layerTitle ?? "connection")"
        }
    }

    var timestamp: String? { date.map(HostCheckStatus.timestamp) }

    /// The status line shown under a host row; nil when never checked.
    var rowDetail: String? { timestamp }

    static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}

extension HostCheckStatus {
    /// The single report → persisted-summary mapping. The sheet persists through
    /// this function and the row renders the summary it produced, so the two
    /// surfaces cannot disagree about the outcome.
    static func summary(for report: DiagnosticsReport, date: Date = Date()) -> HostCheckSummary {
        HostCheckSummary(
            ok: report.succeeded,
            failingLayer: report.failingLayer?.rawValue,
            date: date
        )
    }
}

/// The connection self-check sheet. It drives `Diagnostics.run(progress:)` and
/// appends each `ProbeResult` as it lands, so a ~35 s run is visibly advancing
/// instead of sitting on a single spinner.
struct DiagnosticsView: View {
    let host: Host
    let context: DiagnosticsContext
    /// Called once with the finished report; the caller persists it. Kept out of
    /// the view so the same sheet serves both entry points. `@MainActor` because
    /// the callers persist through `HostStore`, which is main-actor isolated.
    var onFinish: (@MainActor (DiagnosticsReport) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var results: [ProbeResult] = []
    @State private var report: DiagnosticsReport?
    @State private var isRunning = false
    @State private var didCopy = false

    init(host: Host, context: DiagnosticsContext,
         onFinish: (@MainActor (DiagnosticsReport) -> Void)? = nil) {
        self.host = host
        self.context = context
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                probesSection
                if let report {
                    reportSection(report)
                }
            }
            .navigationTitle("Connection check")
            .themedScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyReport()
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(report == nil)
                    .accessibilityLabel("Copy report")
                }
            }
            .task { await run() }
        }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.displayName).font(.headline)
                Text("\(host.useTLS ? "https" : "http")://\(host.address):\(host.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Running probes…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let report {
                    Text(report.succeeded ? "All probes passed" : "One or more probes failed")
                        .font(.caption)
                        .foregroundStyle(report.succeeded ? .green : .orange)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var probesSection: some View {
        Section("Probes") {
            ForEach(results) { result in
                probeRow(result)
            }
            if isRunning && results.count < Diagnostics.defaultProbes().count {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("Waiting for next probe…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func probeRow(_ result: ProbeResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol(for: result.state))
                .foregroundStyle(color(for: result.state))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.body)
                Text("\(result.layer.title) · \(result.state.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !result.detail.isEmpty {
                    Text(result.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func reportSection(_ report: DiagnosticsReport) -> some View {
        Section("Report") {
            Text(report.text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @MainActor
    private func run() async {
        isRunning = true
        results = []
        report = nil
        didCopy = false

        let diagnostics = Diagnostics(host: host, context: context)
        let outcome = await diagnostics.run { result in
            results.append(result)
        }

        report = outcome
        isRunning = false
        onFinish?(outcome)
    }

    private func copyReport() {
        guard let report else { return }
        UIPasteboard.general.string = report.text
        didCopy = true
    }

    private func symbol(for state: ProbeState) -> String {
        switch state {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .notRun: return "minus.circle"
        }
    }

    private func color(for state: ProbeState) -> Color {
        switch state {
        case .passed: return .green
        case .failed: return .red
        case .notRun: return .secondary
        }
    }
}
