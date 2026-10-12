import SwiftUI

/// The Addons destination: every installed add-on, grouped by kind.
///
/// A plugin add-on opens like a folder — tapping it browses the content Kodi
/// exposes at `plugin://<addonid>/`, drill-down and playback work exactly as in
/// the Files browser, because it is the same `DirectoryView`. Add-ons with no
/// browsable tree (skins, scrapers, fonts) are plain rows.
///
/// Enabling and disabling moved to a swipe action: the row's tap now means
/// "open", which is the thing you reach for, and a switch on every row made the
/// list unreadable and the browse action invisible.
struct AddonsScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void

    @Environment(\.remoteTheme) private var theme

    @State private var addons: [Addon] = []
    @State private var isLoading = true
    @State private var error: String?

    /// Groups in the order Kodi lists them, alphabetical inside each group.
    /// A named struct rather than a tuple because `ForEach` needs a key path and
    /// key paths cannot address tuple elements.
    private struct AddonGroup: Identifiable {
        let label: String
        let addons: [Addon]
        var id: String { label }
    }

    private var groups: [AddonGroup] {
        Dictionary(grouping: addons, by: \.typeLabel)
            .map { AddonGroup(label: $0.key, addons: $0.value.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.addons) { addon in
                        row(addon)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if addons.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? "No add-ons installed on this host.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .navigationTitle("Addons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .themedScreen()
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ addon: Addon) -> some View {
        if addon.isBrowsable {
            NavigationLink {
                DirectoryView(model: model, path: addon.browsePath, title: addon.displayName)
            } label: {
                label(addon)
            }
            .swipeActions(edge: .trailing) { toggleAction(addon) }
        } else {
            label(addon)
                .swipeActions(edge: .trailing) { toggleAction(addon) }
        }
    }

    private func label(_ addon: Addon) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(addon.displayName)
                .lineLimit(1)
            if !addon.summary.isEmpty {
                Text(addon.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                if !addon.version.isEmpty {
                    Text(addon.version)
                }
                if !addon.enabled {
                    Text("Disabled")
                }
                if addon.broken {
                    Label("Broken", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func toggleAction(_ addon: Addon) -> some View {
        let target = !addon.enabled
        return Button {
            // Flip the local copy first so the row follows the finger, then let
            // the reload correct it if Kodi refuses.
            update(addon, enabled: target)
            Task {
                await model.setAddonEnabled(addon, enabled: target)
                await load()
            }
        } label: {
            Label(target ? "Enable" : "Disable",
                  systemImage: target ? "checkmark.circle" : "xmark.circle")
        }
        .tint(target ? theme.accent : .red)
    }

    private func update(_ addon: Addon, enabled: Bool) {
        guard let index = addons.firstIndex(where: { $0.addonid == addon.addonid }) else { return }
        addons[index].enabled = enabled
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            addons = try await model.addons()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
