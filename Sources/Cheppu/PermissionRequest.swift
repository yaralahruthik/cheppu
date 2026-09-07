import AppKit
import CheppuCore
import CheppuSettings

/// Asking for a permission the Hotkey cannot work without.
///
/// The Microphone can be granted from inside the prompt macOS shows. The two
/// the Hotkey needs cannot: they are switches in System Settings, and an app
/// that only opens that pane leaves the user looking at a list of apps with no
/// idea why they are there. So Cheppu says why in one line and then puts them
/// in front of the right switch, rather than leaving them to hunt
/// (`docs/product-experience.md` §9).
///
/// This is glue: it holds no decisions of its own, which is why it is not tested.
@MainActor
enum PermissionRequest {
    /// Says why Cheppu needs the permission, and opens the pane if the user
    /// wants to grant it now.
    ///
    /// The Hotkey is named as whatever the user set it to rather than as the
    /// default: somebody who moved it to the Globe key and is being asked for
    /// Input Monitoring needs to read the key they chose.
    static func ask(for permission: Permission, toWatch hotkey: Hotkey) {
        let alert = NSAlert()
        alert.messageText = "Cheppu needs \(permission.name) access"
        alert.informativeText = reason(for: permission, watching: hotkey)
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        // Cheppu has no Dock icon and no window, so without this the alert can
        // open behind whatever the user is working in — which is the one place
        // an explanation is no use.
        NSApp.activate()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // The same pane the Settings window's button opens, from the same
        // place: an app that knew two ways to the one switch would eventually
        // know one of them wrongly.
        SystemSettingsPane.open(permission)
    }

    private static func reason(for permission: Permission, watching hotkey: Hotkey) -> String {
        switch permission {
        case .accessibility:
            "Cheppu watches for your hotkey — \(hotkey.name) — while you are working in "
                + "another app, and macOS calls that Accessibility."
        case .inputMonitoring:
            // The permission is half of it. The other half is a macOS setting
            // nothing else on the machine would send them to, and a user who
            // granted this and still had a key that did nothing would have no
            // way of guessing why.
            "You dictate on the Globe key, and macOS does not hand that one to apps the way "
                + "it hands over every other key. It also needs System Settings › Keyboard › "
                + "“Press 🌐 key to” set to “Do Nothing”, or macOS acts on the press before "
                + "Cheppu sees it."
        case .microphone:
            "Cheppu hears you only while you are dictating."
        }
    }
}
