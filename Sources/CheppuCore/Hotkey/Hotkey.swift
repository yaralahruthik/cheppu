/// The single user-configurable key or key chord that performs Activation.
///
/// Two shapes, because two kinds of hand reach for a dictation key. A bare
/// modifier is one key held on its own — the fastest thing there is to press,
/// and the default. A chord is a key struck with modifiers held, for a keyboard
/// or a layout where no bare modifier is going spare.
///
/// It is a value rather than a set of flags so that the shapes Cheppu cannot
/// act on cannot be written down: there is no "two bare modifiers at once", and
/// no chord that is a letter with nothing held, which would take every D on the
/// machine.
public enum Hotkey: Equatable, Hashable, Sendable {
    /// One modifier key, held on its own.
    case bareModifier(Modifier)

    /// A key struck while these modifiers are held, and no others.
    ///
    /// The set is never empty: a chord is recorded from what the user pressed,
    /// and a key with nothing held is refused there rather than represented
    /// here (`HotkeyRecording`).
    case chord(Key, with: Set<Modifier>)

    /// The right Option key, on its own.
    ///
    /// The default because it does nothing on its own in any app, so turning
    /// Cheppu on takes no shortcut away from anyone, and because it needs no
    /// permission beyond the one watching the keyboard already needs
    /// (`docs/product-experience.md` §6).
    public static let byDefault = Hotkey.bareModifier(.rightOption)

    /// Everything that must be held for this to be the Hotkey, and nothing else.
    public var modifiers: Set<Modifier> {
        switch self {
        case .bareModifier(let modifier): [modifier]
        case .chord(_, let modifiers): modifiers
        }
    }

    /// The key struck, where the Hotkey is a chord.
    public var key: Key? {
        switch self {
        case .bareModifier: nil
        case .chord(let key, _): key
        }
    }

    /// What the user reads in Settings, and what the app says when it has to
    /// name the key out loud.
    ///
    /// A bare modifier is named in words, because a lone ⌥ on a line is not a
    /// key anyone recognises. A chord is printed the way every menu on macOS
    /// prints one, so that the Hotkey reads like the shortcuts beside it rather
    /// than like a setting.
    public var name: String {
        switch self {
        case .bareModifier(let modifier): modifier.name
        case .chord(let key, let modifiers):
            modifiers.inDisplayOrder.map(\.symbol).joined() + key.name
        }
    }

    /// Whether macOS will not report this Hotkey without Input Monitoring.
    ///
    /// Only the Globe key. Every other key on the keyboard arrives on the grant
    /// that watching the keyboard already has, which is what lets Cheppu ask
    /// for no permission the chosen Hotkey does not actually need.
    public var needsInputMonitoring: Bool {
        modifiers.contains(.function)
    }

    /// What the user has to be told at the moment they choose this Hotkey —
    /// not before, when it would be a paragraph about keys they have not
    /// picked, and not never.
    ///
    /// Nothing, for almost every choice. The warning is worth having only for
    /// as long as it is rare: a screen that objected to every key would be one
    /// the user learns to click through.
    public var warnings: [HotkeyWarning] {
        var warnings: [HotkeyWarning] = []
        if needsInputMonitoring { warnings.append(.globeKey) }
        if let taken = systemShortcutItSharesWith { warnings.append(.systemShortcut(taken)) }
        return warnings
    }

    /// What macOS already does with this chord, if it does anything.
    ///
    /// Matched with the sides taken off, because macOS does not care which
    /// Command key opened Spotlight — and neither does the Chord itself, which
    /// is matched at the keyboard the same way.
    private var systemShortcutItSharesWith: String? {
        guard case .chord(let key, let modifiers) = self else { return nil }
        let symbols = Modifier.withoutSides(modifiers)

        return Self.systemShortcuts.first { $0.symbols == symbols && $0.key == key.name }?.does
    }

    /// The shortcuts macOS ships with that someone might reach for a dictation
    /// key on top of.
    ///
    /// Committed rather than read from the system: what macOS exposes is the
    /// symbolic hot keys the user has changed, not the ones they have not, and
    /// a warning that only fired for customised shortcuts would be silent for
    /// exactly the defaults everybody has.
    private static let systemShortcuts:
        [(symbols: Set<String>, key: String, does: String)] = [
            (["⌘"], "Space", "open Spotlight"),
            (["⌃"], "Space", "change your input source"),
            (["⌃", "⌘"], "Space", "open Emoji & Symbols"),
            (["⌘"], "Tab", "switch between apps"),
            (["⌘"], "Q", "quit the app you are in"),
            (["⌘"], "W", "close a window"),
            (["⌘"], "C", "copy"),
            (["⌘"], "V", "paste"),
            (["⌘"], "X", "cut"),
            (["⌘"], "Z", "undo"),
            (["⌘"], "A", "select everything"),
            (["⌘"], "S", "save"),
            (["⌘"], "F", "find"),
            (["⌘"], "P", "print"),
            (["⌘"], "N", "make a new document"),
            (["⌘"], "O", "open a file"),
            (["⌘"], "T", "open a new tab"),
            (["⌘"], "H", "hide the app you are in"),
            (["⌘"], "M", "minimise a window"),
            (["⇧", "⌘"], "3", "take a screenshot"),
            (["⇧", "⌘"], "4", "take a screenshot of part of the screen"),
            (["⇧", "⌘"], "5", "open the screenshot tools"),
        ]

    // MARK: - What is remembered

    /// The Hotkey written down, for the preferences domain.
    ///
    /// Names rather than key codes: a code is a position on one keyboard, and a
    /// preference that meant a different key on the next one would be a Hotkey
    /// that silently moved.
    public var written: String {
        (modifiers.inDisplayOrder.map(\.rawValue) + (key.map { [$0.written] } ?? [])).joined(
            separator: "+")
    }

    /// The Hotkey that was written down, or nothing where it cannot be read.
    ///
    /// Refused rather than guessed at: whoever asked can fall back to a Hotkey
    /// that works, which is a better answer than a key that happens to parse.
    public init?(written: String) {
        let parts = written.split(separator: "+").map(String.init)

        if parts.count == 1, let modifier = Modifier(rawValue: parts[0]) {
            self = .bareModifier(modifier)
            return
        }

        guard parts.count > 1, let key = Key(named: parts[parts.count - 1]) else { return nil }
        let modifiers = parts.dropLast().compactMap(Modifier.init(rawValue:))
        guard modifiers.count == parts.count - 1 else { return nil }

        self = .chord(key, with: Set(modifiers))
    }
}

extension Set where Element == Modifier {
    /// The modifiers in the order macOS prints them: 🌐 ⌃ ⌥ ⇧ ⌘.
    ///
    /// Taken from the order they are declared in, so that a modifier added
    /// later is placed by moving one line rather than by editing a second list
    /// that could come to disagree with the first.
    var inDisplayOrder: [Modifier] {
        Modifier.allCases.filter(contains)
    }
}
