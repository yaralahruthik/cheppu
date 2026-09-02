/// One item in Cheppu's menu bar menu.
///
/// The core decides what the menu offers; the app target renders it. Nothing
/// here knows about `NSMenu`, and nothing here performs the item's action —
/// the shell maps an item onto the AppKit call that carries it out.
public enum MenuBarItem: Equatable, Sendable {
    /// Quits Cheppu.
    case quit

    /// The label the user reads in the menu.
    public var title: String {
        switch self {
        case .quit: "Quit Cheppu"
        }
    }

    /// The key that picks the item when held with Command.
    public var shortcutKey: String {
        switch self {
        case .quit: "q"
        }
    }
}

/// The menu behind Cheppu's menu bar icon.
///
/// The skeleton offers Quit and nothing else. History, Settings and Onboarding
/// join it as their own tickets land.
public struct MenuBarMenu: Equatable, Sendable {
    public let items: [MenuBarItem]

    public init() {
        self.items = [.quit]
    }
}
