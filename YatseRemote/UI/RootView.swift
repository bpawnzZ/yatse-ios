import SwiftUI

/// Before a host is chosen the app is the host picker; once one is active it is
/// the host-centric shell. These are two different apps rather than two screens
/// in one stack, so this is a branch.
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
    }
}
