import AppKit
import CheppuCore

/// The pane in System Settings where a permission is granted.
///
/// Cheppu never leaves the user at System Settings' front door. A permission
/// they cannot grant from inside the app is one they are put in front of
/// (`docs/product-experience.md` §9), and the `x-apple.systempreferences`
/// scheme is what opens the pane itself rather than the app that holds it.
public enum SystemSettingsPane {
    public static func open(_ permission: Permission) {
        guard let pane = URL(string: address(of: permission)) else { return }
        NSWorkspace.shared.open(pane)
    }

    static func address(of permission: Permission) -> String {
        switch permission {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        // What macOS calls Input Monitoring in its own address for the pane.
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}

/// What macOS says about each permission this instant.
///
/// A seam rather than a call, because the two answers come from two different
/// frameworks owned by two different targets — the microphone's and the
/// keyboard's — and because a window that asked for them itself would be one
/// the suite could not open without the machine running it being asked for
/// Accessibility.
public protocol Permissions: Sendable {
    /// Whether Cheppu has this permission, answered from the decision already
    /// on record and without prompting for anything.
    func status(of permission: Permission) -> PermissionStatus

    /// Asks macOS for a permission that has a prompt of its own, at the moment
    /// the user's own choice has made it necessary and at no other.
    ///
    /// Only Input Monitoring is ever asked for this way, and only by somebody
    /// who has just chosen the Globe key. The Microphone is asked for by the
    /// first Dictation that needs it, and Accessibility has no prompt at all —
    /// it is a switch in System Settings, which is what the button beside it is
    /// for.
    func ask(for permission: Permission)
}
