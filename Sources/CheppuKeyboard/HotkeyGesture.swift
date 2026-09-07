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
/// It is built for one Hotkey and watches for that one. A user who changes their
/// Hotkey gets a new gesture with the new key, rather than one that changes its
/// mind halfway through a press it already reported.
struct HotkeyGesture {
    /// The key this gesture is watching for.
    private let hotkey: Hotkey

    /// What the user is holding this instant. Kept for both shapes of Hotkey:
    /// a bare modifier is the whole of what is held, and a chord is a key
    /// struck while exactly these are.
    private var held: Set<Modifier> = []

    /// Whether a press this gesture reported is still going on.
    private var isHeld = false

    /// Whether nothing has joined it since it went down. Only a bare modifier
    /// can lose this: a chord was unambiguous the moment it was struck.
    private var isOnItsOwn = false

    init(watchingFor hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// The stroke, and what it did to the press, if it did anything.
    mutating func seeing(_ stroke: KeyStroke) -> HotkeyEvent? {
        // Reported wherever it was pressed, and never as a key struck: a Hotkey
        // held while Escape goes down is someone throwing the Dictation away,
        // and taken as typing it would be a key brushed during a Hold — which
        // transcribes and inserts what they said, the one thing they asked for
        // it not to do. What Escape means at this moment, and whether it means
        // anything at all, is the machine's.
        if case .escapePressed = stroke { return .escapePressed }

        if case .modifiersHeld(let nowHeld) = stroke { held = nowHeld }

        switch hotkey {
        case .bareModifier(let modifier): return seeingWithABareModifier(modifier, stroke)
        case .chord(_, let modifiers): return seeingWithAChord(modifiers, stroke)
        }
    }

    /// A Hotkey that is one modifier key held on its own.
    ///
    /// Starting on the way down is what makes taking a press back necessary.
    /// A modifier is live: held with a letter it types an accented character on
    /// several layouts, so a press that has already started a Dictation has to
    /// be something Cheppu can hand back the moment it turns out to have been
    /// an é. That is `pressSpoiled`, and it is reported where the typing
    /// happens rather than where the hand leaves the keyboard, so the
    /// microphone closes at once.
    private mutating func seeingWithABareModifier(
        _ modifier: Modifier, _ stroke: KeyStroke
    ) -> HotkeyEvent? {
        switch stroke {
        // The Hotkey held while a key is struck is the user typing with a
        // modifier, not reaching for Cheppu. `hotkeyKeyPressed` cannot arrive
        // here — a bare-modifier Hotkey leaves the keyboard telling no key
        // apart — and is taken as typing rather than trusted.
        case .keyPressed, .hotkeyKeyPressed:
            return spoilThePress()

        case .hotkeyKeyReleased, .escapePressed:
            return nil

        case .modifiersHeld:
            guard held.contains(modifier) else {
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
                isOnItsOwn = held == [modifier]
                return isOnItsOwn ? .pressed : nil
            }

            // A modifier joined it. The press is spoiled for good: letting go
            // of that modifier before the Hotkey must not turn a chord back
            // into an Activation.
            return held == [modifier] ? nil : spoilThePress()
        }
    }

    /// A Hotkey that is a key struck with modifiers held.
    ///
    /// Nothing here is ever spoiled. A press of a bare modifier is ambiguous
    /// until the user's next keystroke settles it, and a chord never was: they
    /// held ⌃⌥ and struck D, which is not something anybody does on their way
    /// to typing. So a key struck afterwards is a key brushed during a Hold and
    /// is left alone, exactly as it would be during any other Dictation.
    private mutating func seeingWithAChord(
        _ modifiers: Set<Modifier>, _ stroke: KeyStroke
    ) -> HotkeyEvent? {
        switch stroke {
        case .hotkeyKeyPressed:
            // A key held down repeats, and every repeat arrives here as another
            // press. Only the first of them started anything.
            guard !isHeld, held == modifiers else { return nil }
            isHeld = true
            return .pressed

        case .hotkeyKeyReleased:
            guard isHeld else { return nil }
            isHeld = false
            return .released

        case .modifiersHeld:
            // The hand comes off a chord one key at a time, and whichever key
            // it leaves first ends the Hold. Ending it on the modifiers rather
            // than waiting for the key itself is what stops a Dictation running
            // on past the words.
            guard isHeld, held != modifiers else { return nil }
            isHeld = false
            return .released

        case .keyPressed, .escapePressed:
            return nil
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
