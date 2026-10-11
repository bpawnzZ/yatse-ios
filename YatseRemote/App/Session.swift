import Foundation

/// The one active host and its player state, owned above the navigation stack.
///
/// `AppModel` used to be created inside the remote screen as a `@StateObject`,
/// so leaving that screen tore down the model, its WebSocket event stream and
/// its progress ticker. Holding it here is what lets a persistent mini-player
/// and cross-destination playback exist at all.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var host: Host?
    @Published private(set) var model: AppModel?
    private(set) var password = ""

    /// Activates `host`. Re-selecting the current host while connected is a
    /// no-op; re-selecting it after a failed connection retries.
    func activate(host: Host, password: String) {
        if let current = self.host, current.connectionKey == host.connectionKey,
           let model, model.status.isConnected {
            return
        }
        start(host: host, password: password)
    }

    func deactivate() {
        model?.disconnect()
        model = nil
        host = nil
        password = ""
    }

    /// Keeps the session consistent with the saved hosts: returns to the picker
    /// when the active host is deleted, reconnects when its connection details
    /// change, and otherwise just refreshes the stored copy (a rename or a new
    /// self-check result) without bouncing the connection.
    func reconcile(with hosts: [Host], password: (Host) -> String) {
        guard let current = host else { return }
        guard let updated = hosts.first(where: { $0.id == current.id }) else {
            deactivate()
            return
        }
        if updated.connectionKey != current.connectionKey {
            start(host: updated, password: password(updated))
        } else {
            self.host = updated
            self.password = password(updated)
        }
    }

    private func start(host: Host, password: String) {
        model?.disconnect()
        self.host = host
        self.password = password
        let model = AppModel(host: host, password: password)
        self.model = model
        Task { await model.connect() }
    }
}
