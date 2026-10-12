import SwiftUI

/// The Addons destination: the installed video add-ons as a two-column poster
/// grid.
///
/// **Only video add-ons are listed.** `Addon.isVideoAddon` carries the measured
/// rule and why the obvious one draws an empty screen — see its comment.
///
/// Tapping an add-on browses the content Kodi exposes at `plugin://<addonid>/`
/// as a poster grid, because that is the same `DirectoryView` the library grid
/// and add-on content both come from.
///
/// Enabling, disabling and saving a favourite all live in the long-press menu.
/// Enable/disable used to be a swipe action, and a grid has no swipe actions —
/// moving it here is what keeps the only way to re-enable an add-on reachable.
struct AddonsScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void

    @State private var addons: [Addon] = []
    @State private var isLoading = true
    @State private var error: String?

    /// Video add-ons only, alphabetical. A disabled one stays listed — dropping
    /// it would put the menu's Enable out of reach.
    private var videoAddons: [Addon] {
        addons
            .filter(\.isVideoAddon)
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 16
            ) {
                ForEach(videoAddons) { addon in
                    cell(addon)
                }
            }
            .padding()
        }
        .overlay { emptyState }
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
    private var emptyState: some View {
        if videoAddons.isEmpty {
            if isLoading {
                ProgressView()
            } else {
                Text(error ?? "No video add-ons installed on this host.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private func cell(_ addon: Addon) -> some View {
        NavigationLink {
            DirectoryView(model: model, path: addon.browsePath, title: addon.displayName,
                          onOpenDrawer: onOpenDrawer)
        } label: {
            tile(addon)
        }
        .contextMenu {
            FavoriteMenuItem(favorite: Favorite(addon: addon))
            toggleAction(addon)
        }
    }

    private func tile(_ addon: Addon) -> some View {
        PosterTile(url: Artwork.url(addon.thumbnail, host: model.host),
                   title: addon.displayName,
                   detail: detail(for: addon),
                   username: model.host.username,
                   password: model.password)
    }

    /// Version and state, in the single line a tile has room for.
    private func detail(for addon: Addon) -> String {
        var parts: [String] = []
        if !addon.version.isEmpty { parts.append(addon.version) }
        if !addon.enabled { parts.append("Disabled") }
        if addon.broken { parts.append("Broken") }
        return parts.joined(separator: " · ")
    }

    private func toggleAction(_ addon: Addon) -> some View {
        let target = !addon.enabled
        return Button(target ? "Enable" : "Disable",
                      systemImage: target ? "checkmark.circle" : "xmark.circle") {
            // Flip the local copy first so the tile follows the finger, then let
            // the reload correct it if Kodi refuses.
            update(addon, enabled: target)
            Task {
                await model.setAddonEnabled(addon, enabled: target)
                await load()
            }
        }
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
