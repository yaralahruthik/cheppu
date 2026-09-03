import CheppuCore

/// What the Hotkey is, and whether what just happened at the keyboard was a tap
/// of it.
///
/// The only part of watching the keyboard that decides anything, and so the part
/// with tests. Everything it decides is one of two claims about the user: they
/// meant to dictate, or they were typing and Cheppu should keep out of it.
///
/// A tap is reported when the key comes back up rather than when it goes down,
/// which is a deliberate departure from #1: "the Dictation begins on key-down in
/// both cases, so no speech is lost while the threshold elapses". That line is
/// written for the world #8 builds, where a press has to start something before
/// 250 ms have decided whether it was a Toggle or a Hold. There is no threshold
/// yet, so there is no window to lose speech in — only the length of the user's
/// own tap, which they spend tapping rather than speaking.
///
/// What key-down would buy today is the opposite. Right Option is a live
/// modifier: held with a letter it types an accented character on several
/// layouts, so a Dictation begun on the way down would start every time someone
/// typed an é, and then have to be taken back — and taking one back is Cancel,
/// which is #9's. #8 moves the start to the key going down, along with the
/// threshold that makes it necessary and the Hold that makes it worth having.
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

    /// The stroke, and the Activation it completed, if it completed one.
    mutating func seeing(_ stroke: KeyStroke) -> HotkeyEvent? {
        switch stroke {
        case .keyPressed:
            // The Hotkey held while a key is struck is the user typing with a
            // modifier, not reaching for Cheppu.
            isOnItsOwn = false
            return nil

        case .modifiersHeld(let held):
            guard held.contains(Self.hotkey) else {
                let wasATap = isHeld && isOnItsOwn
                isHeld = false
                isOnItsOwn = false
                return wasATap ? .tapped : nil
            }

            if !isHeld {
                // A fresh press. Anything already held with it — Command,
                // Shift — makes this a chord meant for another app.
                isOnItsOwn = held == Self.hotkey
            } else if held != Self.hotkey {
                // A modifier joined it. The press is spoiled for good: letting
                // go of that modifier before the Hotkey must not turn a chord
                // back into an Activation.
                isOnItsOwn = false
            }
            isHeld = true
            return nil
        }
    }
}
