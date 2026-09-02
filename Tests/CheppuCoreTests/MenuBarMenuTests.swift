import Testing

@testable import CheppuCore

// The core suite runs with no permissions granted, no Engine downloaded, no
// network and no audio hardware. Any test that needs one of those belongs in the
// word error rate harness, or does not belong at all.
@Suite("Menu bar menu")
struct MenuBarMenuTests {
    @Test("Offers Quit")
    func offersQuit() {
        #expect(MenuBarMenu().items.contains(.quit))
    }

    @Test("Quit is the only item so far")
    func quitIsTheOnlyItem() {
        #expect(MenuBarMenu().items == [.quit])
    }

    @Test("Quit names the app and is reachable with Command-Q")
    func quitIsLabelled() {
        #expect(MenuBarItem.quit.title == "Quit Cheppu")
        #expect(MenuBarItem.quit.shortcutKey == "q")
    }
}
