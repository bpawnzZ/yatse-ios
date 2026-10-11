import SwiftUI

/// Shown for a destination the app does not implement, naming it and saying so,
/// so the drawer is never a dead end.
struct PlaceholderScreen: View {
    let destination: ShellDestination
    let onOpenDrawer: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: destination.systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(destination.title)
                .font(.title2.weight(.semibold))
            Text("\(destination.title) is not available in this build.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(destination.title)
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

/// A small modal used for honest "not available yet" messages.
struct PlaceholderSheet: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
