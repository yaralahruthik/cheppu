import Testing

@testable import CheppuCore

// The core suite runs with no permissions granted, no Engine downloaded, no
// network and no audio hardware. Any test that needs one of those belongs in the
// word error rate harness, or does not belong at all.
@Suite("Menu bar menu")
struct MenuBarMenuTests {
    @Test("Offers Quit")
    func offersQuit() {
        #expect(MenuBarMenu(missing: [], areCuesOn: true).items.contains(.quit))
    }

    @Test("With the Hotkey working, the menu is History, the Cues, Settings and Quit")
    func withTheHotkeyWorkingTheMenuIsHistoryTheCuesSettingsAndQuit() {
        #expect(
            MenuBarMenu(missing: [], areCuesOn: true).items
                == [.history, .cues(areOn: true), .settings, .quit]
        )
    }

    @Test("Settings is opened from the menu bar, and by the key every other app uses")
    func settingsIsOpenedFromTheMenuBar() {
        // The menu is the only part of Cheppu the user can reach — no Dock
        // icon, and no window until one is asked for — so a settings window
        // that could not be opened from it could not be opened at all. Its
        // title says it opens something, and Command-comma is what every other
        // app on the machine has taught the user to press.
        #expect(MenuBarItem.settings.title == "Settings\u{2026}")
        #expect(MenuBarItem.settings.shortcutKey == ",")
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
        // That is a menu bar item as well as a line in Settings, and it has to
        // say which way it is set without being clicked.
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
            MenuBarMenu(missing: [.accessibility], areCuesOn: true).items
                == [
                    .allowPermission(.accessibility), .history, .cues(areOn: true), .settings,
                    .quit,
                ]
        )
        #expect(MenuBarItem.allowPermission(.accessibility).title.contains("Accessibility"))
    }

    @Test("The menu names the permission that is missing, not the usual one")
    func theMenuNamesThePermissionThatIsMissing() {
        // A user who chose the Globe key and was sent to the Accessibility pane
        // would grant something they already had and come back to a Hotkey that
        // still does nothing. Two permissions, two panes, two sentences.
        #expect(
            MenuBarItem.allowPermission(.inputMonitoring).title.contains("Input Monitoring")
        )
    }

    @Test("Every permission Cheppu is missing gets its own way out, in the order Settings reads them")
    func everyPermissionCheppuIsMissingGetsItsOwnWayOut() {
        // A user whose Microphone and Accessibility are both off and who was
        // offered only one of them would grant it, press the key again, and
        // meet the same nothing. The menu is the only part of Cheppu they can
        // reach, so it names every permission that is in the way.
        #expect(
            MenuBarMenu(missing: [.microphone, .accessibility], areCuesOn: false).items == [
                .allowPermission(.microphone), .allowPermission(.accessibility),
                .history, .cues(areOn: false), .settings, .quit,
            ])
    }

    @Test("A Microphone that is off is said in its own words, not the Hotkey's")
    func aMicrophoneThatIsOffIsSaidInItsOwnWords() {
        // Accessibility and Input Monitoring are what the Hotkey needs; the
        // Microphone is what a Dictation needs once the key has arrived. A
        // Microphone row that said "The Hotkey Needs Microphone" would send
        // somebody to look at their keyboard.
        #expect(MenuBarItem.allowPermission(.microphone).title.contains("Microphone"))
        #expect(!MenuBarItem.allowPermission(.microphone).title.contains("Hotkey"))
        #expect(MenuBarItem.allowPermission(.accessibility).title.contains("Hotkey"))
    }

    @Test("An item that does something rather than switches something is never ticked")
    func anItemThatDoesSomethingIsNeverTicked() {
        // A tick means "this is on", so an item that is an action rather than a
        // switch must not carry one.
        #expect(!MenuBarItem.quit.isTicked)
        #expect(!MenuBarItem.allowPermission(.accessibility).isTicked)
        #expect(!MenuBarItem.history.isTicked)
        #expect(!MenuBarItem.settings.isTicked)
    }

    @Test("An item with no shortcut claims no key")
    func anItemWithNoShortcutClaimsNoKey() {
        // Said rather than spelled as an empty string, so an item cannot
        // quietly take a shortcut the user needs.
        #expect(MenuBarItem.allowPermission(.accessibility).shortcutKey == nil)
        #expect(MenuBarItem.history.shortcutKey == nil)
    }
}
