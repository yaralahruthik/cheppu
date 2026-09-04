import CheppuCore

/// What the Hotkey is, and what the keyboard just did with it.
///
/// The only part of watching the keyboard that decides anything, and so the part
/// with tests. Everything it decides is one of two claims about the user: they
/// meant to dictate, or they were typing and Cheppu should keep out of it.
/// Escape is the one key it passes on without making either claim, because what
/// Escape means depends on whether a Dictation is Listening, which only the
/// machine knows.
///
/// The press is reported on the way down rather than on the way back up, because
/// a Dictation has to be running before the 250 ms that tell a tap from a Hold
/// have elapsed — otherwise the threshold is paid for out of the user's first
/// word. How long the press lasted, and what either length means, is not decided
/// here: the keyboard reports both ends of it and the core times it.
///
/// Starting on the way down is what makes the third report necessary. Right
/// Option is a live modifier: held with a letter it types an accented character
/// on several layouts, so a press that has already started a Dictation has to be
/// something Cheppu can hand back the moment it turns out to have been an é.
/// That is `pressSpoiled`, and it is reported where the typing happens rather
/// than where the hand leaves the keyboard, so the microphone closes at once.
struct HotkeyGesture {
    /// The Hotkey: the right Option key on its own.
    ///
    /// It is the default because it does nothing on its own in any app, so
    /// turning Cheppu on takes no shortcut away from anyone, and because it
    /// needs no permission beyond the one watching the keyboard already needs.
    /// Changing it, to another bare modifier or to a chord, is #16's.
    static let hotkey: ModifierKeys = [.rightOption]

    /// Whether the Hotkey was down as of the last stroke.
    private var isHeld = false

    /// Whether nothing has joined it since it went down.
    private var isOnItsOwn = false

    /// The stroke, and what it did to the press, if it did anything.
    mutating func seeing(_ stroke: KeyStroke) -> HotkeyEvent? {
        switch stroke {
        case .keyPressed:
            // The Hotkey held while a key is struck is the user typing with a
            // modifier, not reaching for Cheppu.
            return spoilThePress()

        case .escapePressed:
            // Reported wherever it was pressed, and never as a key struck: a
            // Hotkey held while Escape goes down is someone throwing the
            // Dictation away, and taken as typing it would be a key brushed
            // during a Hold — which transcribes and inserts what they said,
            // the one thing they asked for it not to do. What Escape means at
            // this moment, and whether it means anything at all, is the
            // machine's.
            return .escapePressed

        case .modifiersHeld(let held):
            guard held.contains(Self.hotkey) else {
                // Only a press Cheppu reported has a release worth reporting.
                let hadReportedThePress = isHeld && isOnItsOwn
                isHeld = false
                isOnItsOwn = false
                return hadReportedThePress ? .released : nil
            }

            guard isHeld else {
                // A fresh press. Anything already held with it — Command,
                // Shift — makes this a chord meant for another app, and a chord
                // is never reported at all, so there is no Dictation to take
                // back when it ends.
                isHeld = true
                isOnItsOwn = held == Self.hotkey
                return isOnItsOwn ? .pressed : nil
            }

            // A modifier joined it. The press is spoiled for good: letting go
            // of that modifier before the Hotkey must not turn a chord back
            // into an Activation.
            return held == Self.hotkey ? nil : spoilThePress()
        }
    }

    /// Takes back a press that turned out to be typing, once.
    ///
    /// Once, because a press stops being Cheppu's the first time the user types
    /// with it. Everything they type after that is the same press, and the
    /// Dictation it started has already been handed back.
    private mutating func spoilThePress() -> HotkeyEvent? {
        guard isHeld, isOnItsOwn else { return nil }
        isOnItsOwn = false
        return .pressSpoiled
    }
}
