import SwiftUI

/// The Addons destination: every installed add-on, grouped by kind, with a
/// switch to enable or disable each one. Disabling is what the drawer entry was
/// missing — it used to be a placeholder that said the feature did not exist.
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

    private func row(_ addon: Addon) -> some View {
        Toggle(isOn: Binding(
            get: { addon.enabled },
            set: { newValue in
                // Flip the local copy first so the switch follows the finger,
                // then let the reload correct it if Kodi refuses.
                update(addon, enabled: newValue)
                Task {
                    await model.setAddonEnabled(addon, enabled: newValue)
                    await load()
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(addon.displayName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !addon.version.isEmpty {
                        Text(addon.version)
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
        .tint(theme.accent)
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
