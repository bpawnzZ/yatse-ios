import SwiftUI

@main
struct YatseRemoteApp: App {
    @StateObject private var store = HostStore()
    @StateObject private var session = Session()
    @StateObject private var favorites = FavoriteStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(session)
                .environmentObject(favorites)
                .themedRoot()
                .preferredColorScheme(.dark)
        }
    }
}

/// How the host list behaves: the picker connects to a host; the manager (used
/// under Settings) only edits hosts.
enum HostsMode { case connect, manage }

/// The host picker (first run, or after disconnect) and the host manager. It
/// owns no navigation stack — the root or the shell supplies one.
struct HostsView: View {
    var mode: HostsMode = .connect

    @EnvironmentObject private var store: HostStore
    @EnvironmentObject private var session: Session
    @StateObject private var discovery = KodiDiscovery()
    @State private var isAdding = false
    @State private var editingHost: Host?
    @State private var checkingHost: Host?

    var body: some View {
        List {
            if !store.hosts.isEmpty {
                Section("Saved hosts") {
                    ForEach(store.hosts) { host in
                        row(for: host)
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingHost = host
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    checkingHost = host
                                } label: {
                                    Label("Check", systemImage: "stethoscope")
                                }
                                .tint(.green)
                            }
                    }
                    .onDelete { store.remove(at: $0) }
                }
            } else if mode == .connect {
                Section {
                    Text("No hosts yet. Add one, or pick a discovered server below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Discovered on this network") {
                if discovery.results.isEmpty {
                    Text(discovery.isSearching ? "Searching…" : "Nothing advertised found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(discovery.results) { found in
                    Button {
                        store.upsert(found.host)
                    } label: {
                        Label(found.name.isEmpty ? found.address : found.name,
                              systemImage: "plus.circle")
                    }
                }
            }
        }
        .navigationTitle(mode == .connect ? "Yatse Remote" : "Hosts")
        .themedScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    discovery.isSearching ? discovery.stop() : discovery.start()
                } label: {
                    Image(systemName: "wifi")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            HostEditor(host: nil) { host, password in
                store.upsert(host)
                store.setPassword(password, for: host)
            }
        }
        .sheet(item: $editingHost) { host in
            HostEditor(host: host, password: store.password(for: host)) { updated, password in
                store.upsert(updated)
                store.setPassword(password, for: updated)
            }
        }
        .sheet(item: $checkingHost) { host in
            DiagnosticsView(
                host: host,
                context: DiagnosticsContext.kodi(
                    KodiClient(host: host,
                               username: host.username,
                               password: store.password(for: host))
                )
            ) { report in
                store.recordCheck(for: host, summary: HostCheckStatus.summary(for: report))
            }
        }
        .task { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    @ViewBuilder
    private func row(for host: Host) -> some View {
        if mode == .connect {
            Button {
                session.activate(host: host, password: store.password(for: host))
            } label: {
                HostRow(host: host)
            }
            .buttonStyle(.plain)
        } else {
            HostRow(host: host)
                .contentShape(Rectangle())
                .onTapGesture { editingHost = host }
        }
    }
}

/// One saved host: name, address, and the last self-check line.
struct HostRow: View {
    let host: Host

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.displayName).font(.headline)
            Text("\(host.address):\(host.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HostCheckRow(status: HostCheckStatus(summary: host.lastCheck))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The persisted last-check line shown under a host row: "Not checked" on a
/// host with no recorded run, otherwise the outcome and its timestamp.
struct HostCheckRow: View {
    let status: HostCheckStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(status.label)
            if let detail = status.rowDetail {
                Text("· \(detail)")
            }
        }
        .font(.caption2)
        .foregroundStyle(tint)
    }

    private var symbol: String {
        switch status.state {
        case .neverChecked: return "circle.dashed"
        case .reachable: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status.state {
        case .neverChecked: return .secondary
        case .reachable: return .green
        case .failed: return .orange
        }
    }
}

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: Host
    @State private var password: String
    private let onSave: (Host, String) -> Void

    init(host: Host?, password: String = "", onSave: @escaping (Host, String) -> Void) {
        _host = State(initialValue: host ?? Host())
        _password = State(initialValue: password)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $host.name)
                    TextField("Address", text: $host.address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $host.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }

                Section("Authentication") {
                    TextField("Username", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                Section("Power") {
                    TextField("MAC address", text: $host.macAddress)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Wake-on-LAN port", value: $host.wolPort, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }

                Section {
                    Toggle("Use HTTPS / WSS", isOn: $host.useTLS)
                } footer: {
                    Text("Kodi serves plain HTTP on port 8080 by default. "
                         + "Turn this on only if the webserver is configured for TLS.")
                }
            }
            .navigationTitle(host.name.isEmpty ? "New host" : host.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var value = host
                        value.port = (1...65535).contains(value.port) ? value.port : 8080
                        value.wolPort = (1...65535).contains(value.wolPort) ? value.wolPort : 9
                        onSave(value, password)
                        dismiss()
                    }
                    .disabled(!host.isUsable)
                }
            }
        }
    }
}
