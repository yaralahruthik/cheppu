import CheppuCore
import CheppuSettings

/// The Permission port: what Cheppu does about a permission it does not have.
///
/// It says which one and puts the user in front of the switch, and then it stops
/// saying it. The Pill answers every attempt, because every attempt is a
/// Dictation that did not happen; an alert on every attempt would be the app
/// shouting at somebody who has already been told
/// (`docs/product-experience.md` §9). Granting it back and losing it again is
/// worth saying twice, so what has been said is forgotten the moment macOS says
/// the permission is there.
///
/// This is glue: the one decision in it is that one, which is why it is not
/// tested.
@MainActor
final class SayingWhatIsMissing: PermissionPort {
    private let preferences: Preferences
    private let permissions: any Permissions

    /// The permissions Cheppu has already said are missing and has not seen come
    /// back since.
    private var alreadySaid: Set<Permission> = []

    init(setting preferences: Preferences, asking permissions: any Permissions) {
        self.preferences = preferences
        self.permissions = permissions
    }

    func askFor(_ permission: Permission) async {
        // Anything granted since it was last said is something Cheppu is
        // entitled to say again if it goes a second time.
        alreadySaid = alreadySaid.filter { permissions.status(of: $0) == .notGranted }
        guard alreadySaid.insert(permission).inserted else { return }

        // On the next turn of the run loop rather than here. The alert is modal,
        // and whoever asked for it is a Dictation: reading it must not be what
        // stops the next press of the Hotkey arriving.
        Task { PermissionRequest.ask(for: permission, toWatch: preferences.hotkey()) }
    }
}
