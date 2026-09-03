import AppKit

/// Asking for Accessibility access.
///
/// The Microphone can be granted from inside the prompt macOS shows. Accessibility
/// cannot: it is a switch in System Settings, and an app that only opens that
/// pane leaves the user looking at a list of apps with no idea why they are
/// there. So Cheppu says why in one line and then puts them in front of the
/// right switch, rather than leaving them to hunt
/// (`docs/product-experience.md` §9).
///
/// This is glue: it holds no decisions of its own, which is why it is not tested.
@MainActor
enum AccessibilityRequest {
    /// The pane the switch is on. The `x-apple.systempreferences` scheme opens
    /// System Settings at exactly this pane rather than at its front door.
    private static let accessibilityPane =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Says why Cheppu needs Accessibility, and opens the pane if the user
    /// wants to grant it now.
    static func ask() {
        let alert = NSAlert()
        alert.messageText = "Cheppu needs Accessibility access"
        alert.informativeText =
            "Cheppu watches for your Hotkey — the right Option key — while you are working in "
            + "another app, and macOS calls that Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        // Cheppu has no Dock icon and no window, so without this the alert can
        // open behind whatever the user is working in — which is the one place
        // an explanation is no use.
        NSApp.activate()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let pane = URL(string: accessibilityPane) else { return }
        NSWorkspace.shared.open(pane)
    }
}
