/// Picking a Hotkey, one keystroke at a time.
///
/// The user opens Settings, presses the key they want to dictate with, and the
/// question at every stroke is the same: is that the key, or is that a hand on
/// its way to it? Deciding it here rather than in the window is what lets every
/// answer be a test rather than a thing someone has to sit down at a keyboard
/// to check.
///
/// It records the two shapes a `Hotkey` has and refuses everything else. A bare
/// letter is refused because it would take every one of them the user types for
/// the rest of the day; two bare modifiers together are refused because Cheppu
/// watches one key held on its own, and a hand on two of them is far likelier
/// to be halfway to a chord.
public struct HotkeyRecording {
    /// What is held this instant, and the most that has been held at once since
    /// the hand last left the keyboard.
    ///
    /// The peak is what says whether a modifier was ever on its own: a hand
    /// coming off Control-Option one key at a time passes through "Option
    /// alone" on its way, and taking that as a choice would give the user a
    /// Hotkey they did not pick.
    private var held: Set<Modifier> = []
    private var peak: Set<Modifier> = []

    /// Whether a Hotkey has been recorded. The hand leaves the keyboard after
    /// every chord, and that must not read as a second choice overwriting the
    /// first.
    private var isDone = false

    public init() {}

    /// The modifiers the user is holding changed.
    ///
    /// Answers with a bare-modifier Hotkey where the hand has just come off one
    /// key that was never joined by anything. Taken on the way up rather than
    /// on the way down, because a modifier that is still held might yet be the
    /// first half of a chord — deciding on key-down would make every chord
    /// impossible to type.
    public mutating func sawModifiers(_ modifiers: Set<Modifier>) -> Hotkey? {
        held = modifiers
        peak.formUnion(modifiers)

        guard !isDone, modifiers.isEmpty else { return nil }

        defer { peak = [] }
        guard peak.count == 1, let alone = peak.first else { return nil }

        isDone = true
        return .bareModifier(alone)
    }

    /// A key that is not a modifier went down.
    ///
    /// Answers with a chord where something was held with it, and with nothing
    /// where nothing was.
    public mutating func sawKey(_ key: Key) -> Hotkey? {
        guard !isDone, !held.isEmpty else { return nil }

        isDone = true
        return .chord(key, with: held)
    }
}
