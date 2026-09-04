extension CleanupRule {
    /// The line the user reads next to the switch.
    ///
    /// One line each, and each says what the rule does to their words rather
    /// than what it is called: a setting that needs a paragraph is the wrong
    /// setting or the wrong default (`docs/product-experience.md` §11).
    ///
    /// Here rather than beside the rules themselves, because it is copy on a
    /// screen and not something Cleanup knows: nothing between a Raw Transcript
    /// and Final Text has any business holding a sentence for a user to read.
    public var title: String {
        switch self {
        case .removesFillerWords: "Remove filler words"
        case .capitalisesSentences: "Capitalise sentences"
        case .breaksParagraphs: "Start a new paragraph after a long pause"
        }
    }
}

/// A permission macOS will not let Cheppu take for itself.
///
/// Two, and the app says what each is for in one line at the moment it is
/// needed (`docs/product-experience.md` §9). Settings is the other moment: the
/// user is looking at Cheppu on purpose, and what they want to know is whether
/// the thing they granted last month is still granted.
public enum Permission: CaseIterable, Equatable, Sendable {
    /// To hear the user. Asked for by macOS, inside a prompt, the first time a
    /// Dictation needs it.
    case microphone

    /// To see the Hotkey while another app has focus, and to type the Insertion.
    /// There is no prompt for this one — it is a switch in System Settings.
    case accessibility

    /// What macOS calls it, so that the name on the screen is the name on the
    /// pane the button opens.
    public var name: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        }
    }

    /// Why Cheppu wants it, in the one line it is worth.
    public var reason: String {
        switch self {
        case .microphone: "Cheppu hears you only while you are dictating."
        case .accessibility: "Lets the hotkey work in other apps, and types what you said."
        }
    }
}

/// Whether Cheppu has a permission, as macOS answers it this instant.
///
/// Two answers rather than three. Whether the user refused or was never asked
/// is a difference to macOS and not to them: either way Cheppu cannot do the
/// thing, and either way the way out is the same pane.
public enum PermissionStatus: Equatable, Sendable {
    case granted
    case notGranted

    /// What the row says next to the permission's name.
    public var name: String {
        switch self {
        case .granted: "Granted"
        case .notGranted: "Not granted"
        }
    }
}

/// One row of the Settings window.
///
/// A control is a decision the user has already made or is about to: what it
/// says, whether it is a switch, which way that switch is set, and what its
/// button does. Nothing here draws anything — the app renders these, exactly as
/// it renders `MenuBarItem`.
public enum SettingsControl: Equatable, Sendable {
    /// One Cleanup rule, and which way the user has it. Every rule has one,
    /// because off has to be a real option for each
    /// (`docs/product-experience.md` §8).
    case cleanupRule(CleanupRule, isOn: Bool)

    /// The Cues. The same switch the menu bar carries, because someone walking
    /// into a meeting reaches for the menu and someone setting Cheppu up looks
    /// here (ADR-0007).
    case cues(areOn: Bool)

    /// Whether Cheppu starts itself when the user logs in.
    case launchAtLogin(isOn: Bool)

    /// One permission and whether Cheppu has it, answered without the user
    /// having to start a Dictation to find out.
    case permission(Permission, PermissionStatus)

    /// What History holds, and the one action that empties it (ADR-0009).
    case history

    /// The line the user reads.
    public var title: String {
        switch self {
        case .cleanupRule(let rule, _): rule.title
        // "Sounds" rather than "Cues", as in the menu: the glossary is what the
        // code calls them, and this line is read by someone who has never seen
        // it.
        case .cues: "Play sounds"
        case .launchAtLogin: "Launch Cheppu at login"
        case .permission(let permission, _): permission.name
        case .history: "History"
        }
    }

    /// The second line, where the title alone does not say what moving the
    /// switch will do.
    ///
    /// One sentence, or nothing. A setting that needs a paragraph is the wrong
    /// setting or the wrong default (`docs/product-experience.md` §11), so
    /// there is nowhere here to write one.
    public var explanation: String? {
        switch self {
        case .cleanupRule(.removesFillerWords, _): "Drops “um” and “uh”, and nothing else."
        case .cleanupRule(.capitalisesSentences, _), .cleanupRule(.breaksParagraphs, _): nil
        case .cues: "A short sound when a dictation starts, stops or is cancelled."
        case .launchAtLogin: "Takes effect the next time you log in."
        case .permission(let permission, _): permission.reason
        case .history: "The last \(History.capacity) dictations, kept on this Mac and nowhere else."
        }
    }

    /// Which way the switch is set, or nothing where the control is not a
    /// switch. A row that only reports something — a permission — has no
    /// switch to be on.
    public var isOn: Bool? {
        switch self {
        case .cleanupRule(_, let isOn), .cues(let isOn), .launchAtLogin(let isOn): isOn
        case .permission, .history: nil
        }
    }

    /// What the row's button says, where it has one.
    ///
    /// Every permission has one, whichever way it is answered. The user came
    /// here to check a permission, and the two things they might want to do
    /// about one — grant it, or take it back — are the same switch on the same
    /// pane; a row that only offered the way there while something was wrong
    /// would be a screen that could be read and not acted on.
    public var action: String? {
        switch self {
        case .permission: "Open System Settings…"
        // No ellipsis: nothing is asked first. Somebody reaching for this has
        // had someone walk up behind them (`docs/product-experience.md` §10).
        case .history: "Clear History"
        case .cleanupRule, .cues, .launchAtLogin: nil
        }
    }
}

/// Everything the user can set, on one screen.
///
/// One list of sections, and no notion of a second page anywhere in it: the
/// window this describes has no tabs, because a setting behind a tab is one the
/// user has to go looking for, and the whole of what Cheppu can be set to is
/// eleven lines (`docs/product-experience.md` §11).
///
/// The Hotkey joins it in #16, which is the last of the MVP's settings.
public struct SettingsScreen: Equatable, Sendable {
    /// A heading and the rows under it. A section groups rows on the one
    /// screen; it never hides them.
    public struct Section: Equatable, Sendable {
        public let title: String
        public let controls: [SettingsControl]

        /// Whether a row still has to say its own name, or whether the heading
        /// above it has already said it.
        ///
        /// A section of one row about one thing — History — would otherwise say
        /// "History" twice and tell the user nothing the second time. Decided
        /// here rather than by the window comparing two labels, so that
        /// renaming a heading cannot silently change what a row draws.
        public func saysItsOwnTitle(_ control: SettingsControl) -> Bool {
            control.title != title
        }
    }

    public let sections: [Section]

    /// Every row, in the order it is read, with the headings taken out.
    public var controls: [SettingsControl] {
        sections.flatMap(\.controls)
    }

    /// - Parameters:
    ///   - cleanup: which Cleanup rules the user has on.
    ///   - areCuesOn: whether a Dictation makes a sound.
    ///   - launchesAtLogin: whether macOS starts Cheppu when the user logs in.
    ///     Read from the system rather than remembered here, because the system
    ///     is where the answer actually lives (ADR-0010).
    ///   - permissions: what macOS says about each permission this instant. One
    ///     nobody answered for is shown as not granted: a row that quietly went
    ///     missing would be the one the user came to check.
    public init(
        cleanup: CleanupRules,
        areCuesOn: Bool,
        launchesAtLogin: Bool,
        permissions: [Permission: PermissionStatus]
    ) {
        self.sections = [
            Section(
                title: "Cleanup",
                controls: CleanupRule.allCases.map { .cleanupRule($0, isOn: cleanup[$0]) }
            ),
            Section(title: "Sounds", controls: [.cues(areOn: areCuesOn)]),
            Section(title: "Startup", controls: [.launchAtLogin(isOn: launchesAtLogin)]),
            Section(
                title: "Permissions",
                controls: Permission.allCases.map {
                    .permission($0, permissions[$0] ?? .notGranted)
                }
            ),
            Section(title: "History", controls: [.history]),
        ]
    }
}
