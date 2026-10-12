import SwiftUI

/// The shell's Settings destination: the active host, a way into host
/// management, and the app version.
struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @AppStorage(ThemeName.storageKey) private var theme: ThemeName = .blue
    let onOpenDrawer: () -> Void

    var body: some View {
        List {
            Section("Active host") {
                if let host = session.host {
                    LabeledContent("Name", value: host.displayName)
                    LabeledContent("Address", value: "\(host.address):\(host.port)")
                    LabeledContent("Connected", value: (session.model?.status.isConnected ?? false) ? "Yes" : "No")
                    Button("Disconnect", role: .destructive) { session.deactivate() }
                } else {
                    Text("No active host").foregroundStyle(.secondary)
                }
            }

            Section("Hosts") {
                NavigationLink("Manage hosts") { HostsView(mode: .manage) }
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeName.allCases) { name in
                        Text(name.title).tag(name)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Settings")
        .themedScreen()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
        }
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}

/// The About / Help destination.
struct AboutScreen: View {
    let onOpenDrawer: () -> Void

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: "Yatse Remote (unofficial)")
                LabeledContent("Version", value: SettingsView.version)
            }
            Section("Help") {
                Text("Yatse Remote controls a Kodi media centre over the local network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Kept in the app, not just the README: this installs from a sideloaded
            // IPA on someone's own device, and it should say what it is without them
            // having to find the repository first.
            Section("Unofficial build") {
                Text("A personal project — not an official app, and not an official build of anything. Not affiliated with, authorised by or endorsed by Team Kodi / the XBMC Foundation, by Yatse or its author, or by Apple.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Kodi and Yatse are named only to say what this talks to and what it was written against. No code, strings or artwork from either is included, and no developer account sits behind it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About / Help")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
        }
    }
}
