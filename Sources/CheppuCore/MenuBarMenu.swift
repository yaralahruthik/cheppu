/// One item in Cheppu's menu bar menu.
///
/// The core decides what the menu offers; the app target renders it. Nothing
/// here knows about `NSMenu`, and nothing here performs the item's action —
/// the shell maps an item onto the AppKit call that carries it out.
public enum MenuBarItem: Equatable, Sendable {
    /// Asks for Accessibility again, with the reason and the way to the right
    /// System Settings pane. Offered only while Cheppu cannot see the Hotkey.
    case allowAccessibility

    /// Quits Cheppu.
    case quit

    /// The label the user reads in the menu.
    public var title: String {
        switch self {
        case .allowAccessibility: "The Hotkey Needs Accessibility…"
        case .quit: "Quit Cheppu"
        }
    }

    /// The key that picks the item when held with Command, where the item has
    /// one.
    public var shortcutKey: String? {
        switch self {
        case .allowAccessibility: nil
        case .quit: "q"
        }
    }
}

/// The menu behind Cheppu's menu bar icon.
///
/// The skeleton offers Quit, and says so when the Hotkey cannot be seen.
/// History, Settings and Onboarding join it as their own tickets land.
public struct MenuBarMenu: Equatable, Sendable {
    public let items: [MenuBarItem]

    /// - Parameter canSeeTheHotkey: whether Cheppu is watching for Activations.
    ///   When it is not — Accessibility has not been granted — the menu says so
    ///   and offers the way to fix it, because a user whose Hotkey does nothing
    ///   has nowhere else to look.
    public init(canSeeTheHotkey: Bool) {
        self.items = canSeeTheHotkey ? [.quit] : [.allowAccessibility, .quit]
    }
}
