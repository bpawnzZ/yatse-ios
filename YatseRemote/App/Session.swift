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

    var isActive: Bool { model != nil }

    /// Makes `host` the active host and connects. Re-activating the same host
    /// is a no-op, so selecting the current host in the drawer does not bounce
    /// the connection.
    func activate(host: Host, password: String) {
        if self.host?.id == host.id, model != nil { return }
        model?.disconnect()
        self.host = host
        self.password = password
        let model = AppModel(host: host, password: password)
        self.model = model
        Task { await model.connect() }
    }

    func deactivate() {
        model?.disconnect()
        model = nil
        host = nil
        password = ""
    }

    /// Drops the session when the active host is no longer saved, so deleting a
    /// host returns the app to the picker instead of leaving a shell pointed at
    /// something that no longer exists.
    func reconcile(with hosts: [Host]) {
        guard let host, !hosts.contains(where: { $0.id == host.id }) else { return }
        deactivate()
    }
}
