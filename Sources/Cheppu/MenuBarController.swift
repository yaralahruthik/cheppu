import AppKit
import CheppuCore

/// Renders the core's `MenuBarMenu` as a status item, and performs the action
/// behind whichever item the user picks.
///
/// This is glue: it holds no decisions of its own, which is why it is not tested.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Cheppu"
        )
        statusItem.menu = menu(for: MenuBarMenu())
        self.statusItem = statusItem
    }

    private func menu(for menuBarMenu: MenuBarMenu) -> NSMenu {
        let menu = NSMenu()
        for item in menuBarMenu.items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuBarItemPicked(_:)),
                keyEquivalent: item.shortcutKey
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
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
