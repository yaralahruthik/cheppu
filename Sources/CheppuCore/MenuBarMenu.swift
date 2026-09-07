/// One item in Cheppu's menu bar menu.
///
/// The core decides what the menu offers; the app target renders it. Nothing
/// here knows about `NSMenu`, and nothing here performs the item's action —
/// the shell maps an item onto the AppKit call that carries it out.
public enum MenuBarItem: Equatable, Sendable {
    /// Asks for a permission Cheppu does not have, with the reason and the way
    /// to the right System Settings pane. Offered only while it is missing, and
    /// it names which one: three permissions, three panes, three sentences, and
    /// a user sent to the wrong one grants something they already had and comes
    /// back to the same nothing.
    case allowPermission(Permission)

    /// Opens History, so that a Dictation that went into the wrong window can
    /// be got back.
    ///
    /// It is here because the menu is the only part of Cheppu the user can
    /// reach: there is no Dock icon and no window until one is asked for. A
    /// Dictation that is kept somewhere nobody can open is not kept
    /// (`docs/product-experience.md` §4).
    case history

    /// Opens Settings, where everything Cheppu can be set to is on one screen.
    ///
    /// Near the bottom, next to Quit, because it is the item a user reaches for
    /// twice: once when they install Cheppu, and once when something about it
    /// is not the way they want it. History and the Cues are above it because
    /// they are what the menu is opened for the rest of the time.
    case settings

    /// Turns the Cues on or off, and says which way they are.
    ///
    /// In the menu as well as in Settings because of when it is
    /// used: someone sits down in a meeting, and has two seconds and one hand
    /// to stop their laptop chirping twice a sentence. A switch that needed a
    /// window opened would be one they used once and then left off.
    case cues(areOn: Bool)

    /// Quits Cheppu.
    case quit

    /// The label the user reads in the menu.
    public var title: String {
        switch self {
        // Named for what the user has lost rather than for the permission
        // itself. Accessibility and Input Monitoring are what the Hotkey needs,
        // and somebody whose key does nothing is looking for exactly that
        // sentence; the Microphone is what a Dictation needs once the key has
        // arrived, and "The Hotkey Needs Microphone" would send them off to look
        // at their keyboard.
        case .allowPermission(.microphone): "Cheppu Needs Microphone…"
        case .allowPermission(let permission): "The Hotkey Needs \(permission.name)…"
        // The ellipsis is what says it opens a window rather than doing
        // something the moment it is let go of.
        case .history: "History…"
        case .settings: "Settings…"
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
        case .allowPermission: nil
        case .history: nil
        case .cues: nil
        // The comma, as everywhere else on the machine. It reaches Cheppu only
        // while the menu is open — an app with no windows has no menu bar of
        // its own to press it in — which is exactly where the user is when they
        // want it.
        case .settings: ","
        case .quit: "q"
        }
    }

    /// Whether the item is a switch that is currently on. An item that is an
    /// action rather than a switch is never ticked.
    public var isTicked: Bool {
        switch self {
        case .cues(let areOn): areOn
        case .allowPermission, .history, .settings, .quit: false
        }
    }
}

/// The menu behind Cheppu's menu bar icon.
///
/// It offers History, the Cue switch, Settings and Quit, and — for every
/// permission Cheppu does not have — says so at the top. Onboarding joins it
/// when its own ticket lands.
public struct MenuBarMenu: Equatable, Sendable {
    public let items: [MenuBarItem]

    /// - Parameters:
    ///   - missing: every permission Cheppu does not have this instant, in the
    ///     order Settings reads them. Each gets an item of its own saying so and
    ///     offering the way to fix it, because a user whose Hotkey or microphone
    ///     does nothing has nowhere else to look — and one who is missing two of
    ///     them and is offered only one would grant it, press the key again, and
    ///     meet the same nothing. They come first, because they are the reason
    ///     the menu was opened.
    ///   - areCuesOn: whether a Dictation makes a sound.
    public init(missing: [Permission], areCuesOn: Bool) {
        self.items =
            missing.map(MenuBarItem.allowPermission)
            + [.history, .cues(areOn: areCuesOn), .settings, .quit]
    }
}
