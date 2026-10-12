import SwiftUI

/// Before a host is chosen the app is the host picker; once one is active it is
/// the host-centric shell. These are two different apps rather than two screens
/// in one stack, so this is a branch.
///
/// This is also the only view holding both the saved hosts and the session, so
/// it is where the launch attempt at the last used host is made.
struct RootView: View {
    @EnvironmentObject private var store: HostStore
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            if session.model == nil {
                NavigationStack {
                    HostsView(mode: .connect)
                }
            } else {
                ShellView()
            }
        }
        .onChange(of: store.hosts) { _, hosts in
            session.reconcile(with: hosts) { store.password(for: $0) }
        }
        // Runs once per launch: the session ignores a second attempt, and a
        // failure falls back to the picker rather than leaving an empty shell.
        .task {
            await session.restoreLastHost(hosts: store.hosts) { store.password(for: $0) }
        }
    }
}
