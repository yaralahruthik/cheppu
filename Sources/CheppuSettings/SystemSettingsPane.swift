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
}
