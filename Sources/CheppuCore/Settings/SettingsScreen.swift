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
/// Three at most, and never more than the chosen Hotkey actually needs: the app
/// says what each is for in one line at the moment it is needed
/// (`docs/product-experience.md` §9). Settings is the other moment: the user is
/// looking at Cheppu on purpose, and what they want to know is whether the
/// thing they granted last month is still granted.
public enum Permission: CaseIterable, Equatable, Hashable, Sendable {
    /// To hear the user. Asked for by macOS, inside a prompt: by Onboarding, on
    /// the first launch, and by the first Dictation that needs it on a machine
    /// that never saw one.
    case microphone

    /// To see the Hotkey while another app has focus, and to type the Insertion.
    /// There is no prompt for this one — it is a switch in System Settings.
    case accessibility

    /// To see the Globe key, which macOS does not hand to apps the way it hands
    /// over every other key. Asked for only by a Hotkey that uses it, and by no
    /// other: a permission Cheppu does not need is one it does not ask for.
    case inputMonitoring

    /// The permissions a Hotkey costs the user, in the order they are read.
    ///
    /// Here rather than `allCases` because the answer depends on the key they
    /// chose. Somebody dictating on the right Option key has no reason ever to
    /// see Input Monitoring, and a row offering the way to a pane they do not
    /// need is the screen asking for something on Cheppu's behalf.
    public static func neededBy(_ hotkey: Hotkey) -> [Permission] {
        [.microphone] + neededToWatch(hotkey)
    }

    /// The permissions Cheppu cannot watch the Hotkey without.
    ///
    /// The Microphone is not one of them, which is the whole of why this is a
    /// list of its own: it is what a Dictation needs once the key has arrived,
    /// and a microphone switched off must never be the reason Cheppu stops
    /// watching for the key. Nothing tells an app when a grant is taken away
    /// (#17), so this is what it keeps asking about while it is watching.
    public static func neededToWatch(_ hotkey: Hotkey) -> [Permission] {
        [.accessibility] + (hotkey.needsInputMonitoring ? [.inputMonitoring] : [])
    }

    /// What macOS calls it, so that the name on the screen is the name on the
    /// pane the button opens.
    public var name: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    /// Why Cheppu wants it, said at the moment the Hotkey does not work
    /// without it — which is longer than the line Settings has room for,
    /// because the user is being asked to leave the app and go and grant
    /// something (`docs/product-experience.md` §9).
    ///
    /// It names the key they actually chose. Somebody who moved their Hotkey to
    /// the Globe key and is being asked for Input Monitoring needs to read the
    /// key they picked, not the one Cheppu ships with.
    public func whyItIsNeeded(toWatch hotkey: Hotkey) -> String {
        switch self {
        case .accessibility:
            "Cheppu watches for your hotkey — \(hotkey.name) — while you are working in "
                + "another app, and macOS calls that Accessibility."
        case .inputMonitoring:
            // The permission is half of it. The other half is a macOS setting
            // nothing else on the machine would send them to, and a user who
            // granted this and still had a key that did nothing would have no
            // way of guessing why.
            "You dictate on the Globe key, and macOS does not hand that one to apps the way "
                + "it hands over every other key. It also needs System Settings › Keyboard › "
                + "“Press 🌐 key to” set to “Do Nothing”, or macOS acts on the press before "
                + "Cheppu sees it."
        // Never asked for this way: the Microphone is asked for by the first
        // Dictation that needs it, inside a prompt of its own.
        case .microphone: reason
        }
    }

    /// Why Cheppu wants it, in the one line it is worth.
    public var reason: String {
        switch self {
        case .microphone: "Cheppu hears you only while you are dictating."
        case .accessibility: "Lets the hotkey work in other apps, and types what you said."
        case .inputMonitoring: "Lets Cheppu see the Globe key, which macOS hides from apps."
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
    /// The key the user dictates with, and the way to choose another
    /// (`docs/product-experience.md` §6).
    ///
    /// It says whether the window is waiting for a key this instant, because a
    /// row that looked the same while it was listening would be one that took
    /// the user's next keystroke without warning.
    case hotkey(Hotkey, isBeingChosen: Bool)

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

    /// The Spellings a Correction left behind: whether the Engine reads them,
    /// how many there are, and the one action that forgets them all — or, while
    /// the part of the Engine they need is missing, that it is and the offer to
    /// fetch it (ADR-0014).
    ///
    /// It carries the row rather than restating it, because the History window
    /// shows the same thing and the two must say it the same way.
    case spellings(SpellingsRow)

    /// The line the user reads.
    public var title: String {
        switch self {
        case .hotkey: "Hotkey"
        case .cleanupRule(let rule, _): rule.title
        // "Sounds" rather than "Cues", as in the menu: the glossary is what the
        // code calls them, and this line is read by someone who has never seen
        // it.
        case .cues: "Play sounds"
        case .launchAtLogin: "Launch Cheppu at login"
        case .permission(let permission, _): permission.name
        case .history: "History"
        case .spellings(let row): row.title
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
        // Both gestures in one line, because the second one is the half nobody
        // discovers on their own (`docs/product-experience.md` §6).
        case .hotkey(_, isBeingChosen: false):
            "Tap it to start and stop, or hold it down to dictate while held."
        // What the user may press, said while they are deciding what to press.
        case .hotkey(_, isBeingChosen: true):
            "Hold one modifier on its own, or strike a key with modifiers held."
        case .cleanupRule(.removesFillerWords, _): "Drops “um” and “uh”, and nothing else."
        case .cleanupRule(.capitalisesSentences, _), .cleanupRule(.breaksParagraphs, _): nil
        case .cues: "A short sound when a dictation starts, stops or is cancelled."
        case .launchAtLogin: "Takes effect the next time you log in."
        case .permission(let permission, _): permission.reason
        case .history: "The last \(History.capacity) dictations, kept on this Mac and nowhere else."
        case .spellings(let row): row.explanation
        }
    }

    /// Which way the switch is set, or nothing where the control is not a
    /// switch. A row that only reports something — a permission — has no
    /// switch to be on.
    public var isOn: Bool? {
        switch self {
        case .cleanupRule(_, let isOn), .cues(let isOn), .launchAtLogin(let isOn): isOn
        case .spellings(let row): row.isOn
        case .hotkey, .permission, .history: nil
        }
    }

    /// What the row reads this instant, where it reports something as well as
    /// offering to change it: the key the user chose, and whether macOS still
    /// says Cheppu has a permission.
    ///
    /// Decided here rather than by the window, so that what a row says and what
    /// it is are the same answer.
    public var reading: String? {
        switch self {
        // Not "Listening", which is what a Dictation does
        // (`docs/product-experience.md` §3). This row is waiting for one key.
        case .hotkey(_, isBeingChosen: true): "Press a key…"
        case .hotkey(let hotkey, _): hotkey.name
        case .permission(_, let status): status.name
        case .cleanupRule, .cues, .launchAtLogin, .history, .spellings: nil
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
        // The ellipsis says it asks for something: the window waits for the key
        // the user presses next rather than doing anything the moment it is let
        // go of. While it is waiting, the same button is the way out of it.
        case .hotkey(_, isBeingChosen: false): "Change…"
        case .hotkey(_, isBeingChosen: true): "Cancel"
        case .permission: "Open System Settings…"
        // No ellipsis: nothing is asked first. Somebody reaching for this has
        // had someone walk up behind them (`docs/product-experience.md` §10).
        case .history: "Clear History"
        // Emptying History leaves the Spellings, and this leaves History: they
        // are two things the user asked Cheppu to keep and two things they can
        // ask it to forget, and one action doing both would be one of them
        // forgotten by accident (ADR-0014).
        case .spellings(let row): row.action
        case .cleanupRule, .cues, .launchAtLogin: nil
        }
    }
}

/// Everything the user can set, on one screen.
///
/// One list of sections, and no notion of a second page anywhere in it: the
/// window this describes has no tabs, because a setting behind a tab is one the
/// user has to go looking for, and the whole of what Cheppu can be set to fits
/// on the one screen without scrolling (`docs/product-experience.md` §11).
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
    ///   - isChoosingAHotkey: whether the window is waiting for the user to
    ///     press the key they want. The row says so while it is, because one
    ///     that looked the same either way would take their next keystroke
    ///     without warning.
    ///   - hotkey: the key the user dictates with. It decides its own row and
    ///     which permissions have one: Input Monitoring is on the screen only
    ///     while the chosen key needs it, because a row offering the way to a
    ///     pane the user has no reason to visit is Cheppu asking for a
    ///     permission it does not need.
    ///   - cleanup: which Cleanup rules the user has on.
    ///   - areCuesOn: whether a Dictation makes a sound.
    ///   - launchesAtLogin: whether macOS starts Cheppu when the user logs in.
    ///     Read from the system rather than remembered here, because the system
    ///     is where the answer actually lives (ADR-0010).
    ///   - permissions: what macOS says about each permission this instant. One
    ///     nobody answered for is shown as not granted: a row that quietly went
    ///     missing would be the one the user came to check.
    ///   - spellings: what the user has taught Cheppu and whether it is being
    ///     read — or, while the part of the Engine that reads them is missing,
    ///     that it is. The row is always on the screen, even with nothing
    ///     taught yet: it is where a user finds out that correcting a word in
    ///     History is a thing Cheppu does anything with.
    public init(
        hotkey: Hotkey,
        isChoosingAHotkey: Bool = false,
        cleanup: CleanupRules,
        areCuesOn: Bool,
        launchesAtLogin: Bool,
        permissions: [Permission: PermissionStatus],
        spellings: SpellingsRow
    ) {
        self.sections = [
            Section(
                title: "Hotkey",
                controls: [.hotkey(hotkey, isBeingChosen: isChoosingAHotkey)]
            ),
            Section(
                title: "Cleanup",
                controls: CleanupRule.allCases.map { .cleanupRule($0, isOn: cleanup[$0]) }
            ),
            Section(title: "Sounds", controls: [.cues(areOn: areCuesOn)]),
            Section(title: "Startup", controls: [.launchAtLogin(isOn: launchesAtLogin)]),
            Section(
                title: "Permissions",
                controls: Permission.neededBy(hotkey).map {
                    .permission($0, permissions[$0] ?? .notGranted)
                }
            ),
            Section(title: "History", controls: [.history]),
            Section(title: "Spellings", controls: [.spellings(spellings)]),
        ]
    }
}
