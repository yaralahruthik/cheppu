import Testing

@testable import CheppuCore

// The core suite runs with no permissions granted, no Engine downloaded, no
// network and no audio hardware. Any test that needs one of those belongs in the
// word error rate harness, or does not belong at all.
@Suite("Menu bar menu")
struct MenuBarMenuTests {
    @Test("Offers Quit")
    func offersQuit() {
        #expect(MenuBarMenu(canSeeTheHotkey: true, areCuesOn: true).items.contains(.quit))
    }

    @Test("With the Hotkey working, the menu is History, the Cues and Quit")
    func withTheHotkeyWorkingTheMenuIsHistoryTheCuesAndQuit() {
        #expect(
            MenuBarMenu(canSeeTheHotkey: true, areCuesOn: true).items
                == [.history, .cues(areOn: true), .quit]
        )
    }

    @Test("History is opened from the menu bar")
    func historyIsOpenedFromTheMenuBar() {
        // The menu is the only way into History, because it is the only part of
        // Cheppu the user can reach: there is no Dock icon and no window until
        // one is asked for. Its title says it opens something rather than doing
        // something, which is what the ellipsis means everywhere else on the
        // machine.
        #expect(MenuBarItem.history.title == "History\u{2026}")
    }

    @Test("The menu says which way the Cue switch is set")
    func theMenuSaysWhichWayTheCueSwitchIsSet() {
        // Turning the sounds off is something someone does on their way into a
        // meeting, with one hand, in the two seconds before they start talking.
        // That is a menu bar item rather than a settings window (#15), and it
        // has to say which way it is set without being clicked.
        #expect(MenuBarItem.cues(areOn: true).isTicked)
        #expect(!MenuBarItem.cues(areOn: false).isTicked)
        #expect(MenuBarItem.cues(areOn: true).title == MenuBarItem.cues(areOn: false).title)
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
        #expect(
            MenuBarMenu(canSeeTheHotkey: false, areCuesOn: true).items
                == [.allowAccessibility, .history, .cues(areOn: true), .quit]
        )
        #expect(MenuBarItem.allowAccessibility.title.contains("Accessibility"))
    }

    @Test("An item that does something rather than switches something is never ticked")
    func anItemThatDoesSomethingIsNeverTicked() {
        // A tick means "this is on", so an item that is an action rather than a
        // switch must not carry one.
        #expect(!MenuBarItem.quit.isTicked)
        #expect(!MenuBarItem.allowAccessibility.isTicked)
        #expect(!MenuBarItem.history.isTicked)
    }

    @Test("An item with no shortcut claims no key")
    func anItemWithNoShortcutClaimsNoKey() {
        // Said rather than spelled as an empty string, so an item cannot
        // quietly take a shortcut the user needs.
        #expect(MenuBarItem.allowAccessibility.shortcutKey == nil)
        #expect(MenuBarItem.history.shortcutKey == nil)
    }
}
