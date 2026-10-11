import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: AppModel
    let section: LibrarySection
    var onOpenDrawer: (() -> Void)? = nil

    @State private var items: [MediaItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var error: String?

    private let pageSize = 60

    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(for: item)
                    .onAppear {
                        if index >= items.count - 5 {
                            Task { await loadMore() }
                        }
                    }
            }

            if isLoading && !items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? section.emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onOpenDrawer {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Open menu")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .task { await reload() }
    }

    @ViewBuilder
    private func row(for item: MediaItem) -> some View {
        if let child = section.childRequest(for: item) {
            NavigationLink {
                ChildrenView(model: model, request: child, heading: item.heading)
            } label: {
                MediaRow(item: item, username: model.host.username, password: model.password, showsChevron: true)
            }
        } else {
            Button {
                Task { await play(item) }
            } label: {
                MediaRow(item: item, username: model.host.username, password: model.password)
            }
            .buttonStyle(.plain)
        }
    }

    private func play(_ item: MediaItem) async {
        guard let payload = item.playableItem else { return }
        await model.play(item: payload)
    }

    private func reload() async {
        items = []
        total = 0
        error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading else { return }
        guard items.isEmpty || items.count < total else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.libraryPage(section, offset: items.count, pageSize: pageSize)
            items.append(contentsOf: page.items)
            total = page.total
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Episodes of a show, or albums of an artist.
struct ChildrenView: View {
    @ObservedObject var model: AppModel
    let request: ChildrenRequest
    let heading: String

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    Task {
                        if let payload = item.playableItem { await model.play(item: payload) }
                    }
                } label: {
                    MediaRow(item: item, username: model.host.username, password: model.password)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? "Nothing to show.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.children(of: request)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
