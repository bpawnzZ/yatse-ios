import Foundation

/// The one active host and its player state, owned above the navigation stack.
///
/// `AppModel` used to be created inside the remote screen as a `@StateObject`,
/// so leaving that screen tore down the model, its WebSocket event stream and
/// its progress ticker. Holding it here is what lets a persistent mini-player
/// and cross-destination playback exist at all.
///
/// It also remembers the host it last activated, so a launch goes straight back
/// to that box instead of asking which one to use.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var host: Host?
    @Published private(set) var model: AppModel?
    /// Why the picker is showing after an automatic attempt failed, or nil when
    /// no attempt failed. Set only by `restoreLastHost`; cleared the moment the
    /// user picks a host.
    @Published private(set) var launchFailure: String?
    private(set) var password = ""

    /// The last activated host's id.
    ///
    /// Deliberately a plain key rather than a field on `Host`: a value that
    /// fails to parse is only ever "nothing remembered", so it cannot take the
    /// saved host list down with it the way a bad `[Host]` payload would.
    private static let lastHostKey = "yatse.lastHost.v1"

    /// Guards the launch attempt. Without it, "attempt failed → the picker
    /// appears → attempt again" is a cycle, because the picker showing is
    /// exactly what a second attempt looks for.
    private var didRestoreLastHost = false

    /// Activates `host`. Re-selecting the current host while connected is a
    /// no-op; re-selecting it after a failed connection retries.
    func activate(host: Host, password: String) {
        if let current = self.host, current.connectionKey == host.connectionKey,
           let model, model.status.isConnected {
            return
        }
        launchFailure = nil
        let model = prepare(host: host, password: password)
        Task { await model.connect() }
    }

    /// Attempts the host this device last activated, once per launch, so its
    /// shell opens without the user selecting it.
    ///
    /// Every way this can fail still ends on the host picker rather than an
    /// empty shell: a host that is no longer saved, or is unusable, is not
    /// attempted at all, and one that does not answer is deactivated again with
    /// the reason recorded.
    func restoreLastHost(hosts: [Host], password: (Host) -> String) async {
        guard !didRestoreLastHost else { return }
        didRestoreLastHost = true

        guard host == nil,
              let id = Self.lastHostID,
              let remembered = hosts.first(where: { $0.id == id }),
              remembered.isUsable else { return }

        let model = prepare(host: remembered, password: password(remembered))
        await model.connect()
        // A host chosen while this attempt was in flight is the newer answer and
        // must not be torn down by a failure that belongs to an older one.
        guard self.model === model, !model.status.isConnected else { return }
        deactivate()
        launchFailure = "Could not reach \(remembered.displayName). Choose a host below."
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
            let model = prepare(host: updated, password: password(updated))
            Task { await model.connect() }
        } else {
            self.host = updated
            self.password = password(updated)
        }
    }

    /// Makes `host` the active one and records it as the last activated host.
    /// Starting the connection is left to the caller: the manual paths let it
    /// run in the background, while the launch attempt awaits it so it can fall
    /// back to the picker.
    private func prepare(host: Host, password: String) -> AppModel {
        model?.disconnect()
        self.host = host
        self.password = password
        UserDefaults.standard.set(host.id.uuidString, forKey: Self.lastHostKey)
        let model = AppModel(host: host, password: password)
        self.model = model
        return model
    }

    /// The remembered host's id, or nil when nothing is remembered or the
    /// stored value is not a UUID.
    private static var lastHostID: UUID? {
        UserDefaults.standard.string(forKey: lastHostKey).flatMap(UUID.init(uuidString:))
    }
}
