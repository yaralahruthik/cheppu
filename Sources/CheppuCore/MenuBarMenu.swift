/// One item in Cheppu's menu bar menu.
///
/// The core decides what the menu offers; the app target renders it. Nothing
/// here knows about `NSMenu`, and nothing here performs the item's action —
/// the shell maps an item onto the AppKit call that carries it out.
public enum MenuBarItem: Equatable, Sendable {
    /// Asks for Accessibility again, with the reason and the way to the right
    /// System Settings pane. Offered only while Cheppu cannot see the Hotkey.
    case allowAccessibility

    /// Opens History, so that a Dictation that went into the wrong window can
    /// be got back.
    ///
    /// It is here because the menu is the only part of Cheppu the user can
    /// reach: there is no Dock icon and no window until one is asked for. A
    /// Dictation that is kept somewhere nobody can open is not kept
    /// (`docs/product-experience.md` §4).
    case history

    /// Turns the Cues on or off, and says which way they are.
    ///
    /// In the menu rather than only in Settings (#15) because of when it is
    /// used: someone sits down in a meeting, and has two seconds and one hand
    /// to stop their laptop chirping twice a sentence. A switch that needed a
    /// window opened would be one they used once and then left off.
    case cues(areOn: Bool)

    /// Quits Cheppu.
    case quit

    /// The label the user reads in the menu.
    public var title: String {
        switch self {
        case .allowAccessibility: "The Hotkey Needs Accessibility…"
        // The ellipsis is what says it opens a window rather than doing
        // something the moment it is let go of.
        case .history: "History…"
        // "Sounds" rather than "Cues": the glossary is what the code calls
        // them, and this line is read by someone who has never seen it.
        case .cues: "Play Sounds"
        case .quit: "Quit Cheppu"
        }
    }

    /// The key that picks the item when held with Command, where the item has
    /// one.
    public var shortcutKey: String? {
        switch self {
        case .allowAccessibility: nil
        case .history: nil
        case .cues: nil
        case .quit: "q"
        }
    }

    /// Whether the item is a switch that is currently on. An item that is an
    /// action rather than a switch is never ticked.
    public var isTicked: Bool {
        switch self {
        case .cues(let areOn): areOn
        case .allowAccessibility, .history, .quit: false
        }
    }
}

/// The menu behind Cheppu's menu bar icon.
///
/// It offers History, the Cue switch and Quit, and — while Cheppu cannot see
/// the Hotkey — says so at the top. Settings and Onboarding join it as their
/// own tickets land.
public struct MenuBarMenu: Equatable, Sendable {
    public let items: [MenuBarItem]

    /// - Parameters:
    ///   - canSeeTheHotkey: whether Cheppu is watching for Activations. When it
    ///     is not — Accessibility has not been granted — the menu says so and
    ///     offers the way to fix it, because a user whose Hotkey does nothing
    ///     has nowhere else to look. It comes first, because it is the reason
    ///     they opened the menu.
    ///   - areCuesOn: whether a Dictation makes a sound.
    public init(canSeeTheHotkey: Bool, areCuesOn: Bool) {
        self.items =
            (canSeeTheHotkey ? [] : [.allowAccessibility])
            + [.history, .cues(areOn: areCuesOn), .quit]
    }
}
