import ServiceManagement

/// Whether macOS starts Cheppu when the user logs in.
///
/// The system holds the answer and Cheppu keeps no copy of it. A preference
/// saying "on" beside a login item the user removed in System Settings — or one
/// that never registered — would be a switch that lies about the one thing it
/// is for (ADR-0010).
///
/// It takes effect at the next login, which is the only moment it could: this
/// registers Cheppu as something to launch, and Cheppu is already running.
public struct LaunchAtLogin: Sendable {
    public init() {}

    /// What the system says this instant.
    ///
    /// Only `enabled` is on. `requiresApproval` — the user switched Cheppu off
    /// in System Settings > General > Login Items — is not, because Cheppu will
    /// not be launched, and a switch that showed it as on would be describing
    /// its own request rather than what will happen.
    public var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Turns it on or off, and answers with what the system says afterwards.
    ///
    /// The answer is read back rather than assumed. Registering can fail — an
    /// unsigned build run out of a build directory rather than an installed
    /// app, most often — and a switch that stayed where the user put it would
    /// be telling them Cheppu will launch when it will not.
    @discardableResult
    public func turn(on: Bool) -> Bool {
        // Nothing is done with the failure beyond reading the status back:
        // there is nothing the user could act on in what `SMAppService` throws,
        // and the switch snapping back is the whole of what it means.
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}

        return isOn
    }
}
