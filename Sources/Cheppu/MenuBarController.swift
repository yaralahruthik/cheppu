import AppKit
import CheppuCore
import CheppuKeyboard

/// Renders the core's `MenuBarMenu` as a status item, performs the action behind
/// whichever item the user picks, and keeps Cheppu watching for the Hotkey.
///
/// This is glue: it holds no decisions of its own, which is why it is not tested.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyWatch()
    private var statusItem: NSStatusItem?

    /// Whether the Hotkey is being watched. Everything the menu says about
    /// Accessibility hangs off this.
    private var canSeeTheHotkey = false

    /// How long to leave between asking macOS again whether Cheppu may watch
    /// the keyboard. Accessibility is granted by hand in System Settings and
    /// nothing tells an app when that happens, so the alternative to asking
    /// again is a Hotkey that only starts working at the next launch.
    private static let whileWaitingForAccessibility: Duration = .seconds(2)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        self.statusItem = statusItem
        showMenu()

        watchForTheHotkey()
    }

    /// Starts watching for the Hotkey, and says why it cannot if it cannot.
    ///
    /// The reason is given once, when Cheppu first finds it cannot watch; the
    /// menu goes on saying it for as long as it is true, because a user whose
    /// Hotkey does nothing has nowhere else to look.
    private func watchForTheHotkey() {
        Task { [weak self] in
            var hasSaidWhy = false
            while let self, !Task.isCancelled {
                do {
                    // A tap has nowhere to go yet. A Dictation needs an
                    // Insertion to end in, which is #7, and that is the ticket
                    // that hands these gestures to a `DictationCore`. What
                    // watching buys today is the rest of this one: Accessibility
                    // asked for at the moment the Hotkey needs it, and a Hotkey
                    // the app can say is not working.
                    try await hotkey.observe { _ in }
                    canSeeTheHotkey = true
                    showMenu()
                    return
                } catch {
                    canSeeTheHotkey = false
                    showMenu()
                    if !hasSaidWhy {
                        hasSaidWhy = true
                        AccessibilityRequest.ask()
                    }
                    try? await Task.sleep(for: Self.whileWaitingForAccessibility)
                }
            }
        }
    }

    private func showMenu() {
        statusItem?.menu = menu(for: MenuBarMenu(canSeeTheHotkey: canSeeTheHotkey))
    }

    private func menu(for menuBarMenu: MenuBarMenu) -> NSMenu {
        let menu = NSMenu()
        for item in menuBarMenu.items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuBarItemPicked(_:)),
                keyEquivalent: item.shortcutKey ?? ""
            )
            menuItem.target = self
            menuItem.representedObject = item
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func menuBarItemPicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        switch item {
        case .allowAccessibility:
            AccessibilityRequest.ask()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
