import Testing

@testable import CheppuCore

// The core suite runs with no permissions granted, no Engine downloaded, no
// network and no audio hardware. Any test that needs one of those belongs in the
// word error rate harness, or does not belong at all.
@Suite("Menu bar menu")
struct MenuBarMenuTests {
    @Test("Offers Quit")
    func offersQuit() {
        #expect(MenuBarMenu(canSeeTheHotkey: true).items.contains(.quit))
    }

    @Test("Quit is the only item while the Hotkey is working")
    func quitIsTheOnlyItemWhileTheHotkeyIsWorking() {
        #expect(MenuBarMenu(canSeeTheHotkey: true).items == [.quit])
    }

    @Test("Quit names the app and is reachable with Command-Q")
    func quitIsLabelled() {
        #expect(MenuBarItem.quit.title == "Quit Cheppu")
        #expect(MenuBarItem.quit.shortcutKey == "q")
    }

    @Test("A Hotkey Cheppu cannot see is said out loud, at the top of the menu")
    func aHotkeyCheppuCannotSeeIsSaidOutLoud() {
        // The Hotkey doing nothing is indistinguishable from the app being
        // broken, and the menu is the only place a user can look. So it names
        // the missing permission, and it comes first, because it is the reason
        // they opened the menu.
        #expect(MenuBarMenu(canSeeTheHotkey: false).items == [.allowAccessibility, .quit])
        #expect(MenuBarItem.allowAccessibility.title.contains("Accessibility"))
    }

    @Test("An item with no shortcut claims no key")
    func anItemWithNoShortcutClaimsNoKey() {
        // Said rather than spelled as an empty string, so an item cannot
        // quietly take a shortcut the user needs.
        #expect(MenuBarItem.allowAccessibility.shortcutKey == nil)
    }
}
