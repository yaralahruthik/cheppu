/// What tells a Terminal from every other place a Dictation's words can land.
///
/// A newline in a Terminal is not a line break. It is Return, and it runs
/// whatever is on the line — so a Paragraph Break inserted into one can execute
/// a command the user never asked for. That is the one place where inserting
/// what the user said is worse than inserting something slightly different, and
/// it is why the question has to be answered before every Insertion.
///
/// It has to be answered from the outside, too. Cheppu cannot read what is on
/// the user's screen or what they have typed — that would mean reading their
/// Terminal in order to insert into it — so the whole of the evidence is what
/// kind of app has focus and what kind of thing inside it the keyboard is
/// pointing at.
///
/// Two things answer it, and they answer opposite halves.
public enum Terminal {
    /// The Terminals Cheppu knows by name.
    ///
    /// Committed here rather than made a setting, for the same reason the Filler
    /// Word list is: a list the user could edit is one they would have to keep
    /// in their head to know what Cheppu did to their words.
    ///
    /// It is exact for the Terminals on it and says nothing about the rest,
    /// which is why it is only half the answer. Adding a name to it is always
    /// safe; leaving one off is what the other half is for.
    public static let bundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp-Preview",
        "co.zeit.hyper",
        "org.tabby",
        "com.raphaelamorim.rio",
    ]

    /// The accessibility roles that mean the keyboard is pointing at somewhere
    /// text is written.
    ///
    /// The list is inverted on purpose: Cheppu commits the roles that mean *a
    /// place text is edited* and treats everything else — an unfamiliar role, or
    /// no focused element at all — as a Terminal.
    ///
    /// Inverted because that is where the evidence is. There is no accessibility
    /// role that means "Terminal": the emulators that expose an accessibility
    /// tree at all expose the same `AXTextArea` that TextEdit and Xcode do, and
    /// the ones that draw their screen on the GPU — which is most of the recent
    /// ones — expose nothing to find. A list of Terminal roles would therefore
    /// have nothing real to match on, and every emulator not named above would
    /// get the dangerous behaviour. A list of text surfaces has the opposite
    /// failure: an unfamiliar app whose focused element Cheppu does not
    /// recognise loses its Paragraph Breaks, which costs the user a line break
    /// they can add back rather than a command they did not run.
    ///
    /// See ADR-0008.
    public static let textSurfaceRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
        "AXComboBox",
        "AXWebArea",
    ]
}

extension TargetApp {
    /// Whether a newline typed into this app would run a command rather than
    /// start a line.
    ///
    /// Known by name, or — for every Terminal Cheppu has never heard of — by
    /// the keyboard not pointing at anything Cheppu recognises as a place text
    /// is written. Either one is enough: a Terminal on the list is a Terminal
    /// whatever its focused element says it is, which is what keeps Terminal.app
    /// and iTerm2 safe despite both exposing an ordinary text area.
    public var isATerminal: Bool {
        if let bundleIdentifier, Terminal.bundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        guard let focusedElementRole else { return true }
        return !Terminal.textSurfaceRoles.contains(focusedElementRole)
    }
}
