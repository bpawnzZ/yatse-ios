import SwiftUI

@main
struct YatseRemoteApp: App {
    @StateObject private var store = HostStore()

    var body: some Scene {
        WindowGroup {
            HostsView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct HostsView: View {
    @EnvironmentObject private var store: HostStore
    @StateObject private var discovery = KodiDiscovery()
    @State private var isAdding = false
    @State private var editingHost: Host?

    var body: some View {
        NavigationStack {
            List {
                if !store.hosts.isEmpty {
                    Section("Saved hosts") {
                        ForEach(store.hosts) { host in
                            NavigationLink(value: host) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.displayName).font(.headline)
                                    Text("\(host.address):\(host.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingHost = host
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete { store.remove(at: $0) }
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
            .navigationTitle("Yatse Remote")
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
            .navigationDestination(for: Host.self) { host in
                RemoteView(host: host, password: store.password(for: host))
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
            .task { discovery.start() }
            .onDisappear { discovery.stop() }
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
                    TextField("Port", value: $host.port, format: .number)
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
                    TextField("Wake-on-LAN port", value: $host.wolPort, format: .number)
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
