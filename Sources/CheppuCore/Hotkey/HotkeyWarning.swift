/// What the user has to be told at the moment they choose a Hotkey.
///
/// Two things, and both of them are about the choice in front of them rather
/// than about Cheppu: one key would fire alongside something macOS already
/// does, and one key needs two things granted or it does nothing at all. They
/// are said where the choice is made — a warning shown before the user has
/// picked anything is a paragraph about keys they were never going to choose,
/// and one shown afterwards is a bug report they have to write themselves.
public enum HotkeyWarning: Equatable, Hashable, Sendable {
    /// The chord is one macOS already uses, and what macOS does with it.
    case systemShortcut(String)

    /// The Globe key, which needs Input Monitoring and a change to a macOS
    /// setting before it reaches Cheppu at all.
    case globeKey

    /// The line at the top of what the user is shown.
    public var title: String {
        switch self {
        case .systemShortcut: "macOS already uses that shortcut"
        case .globeKey: "The Globe key needs two more things"
        }
    }

    /// The rest of it, in the sentences it is worth.
    ///
    /// It says what will happen rather than what is wrong. A user who is told
    /// "that is a system shortcut" has been given something to worry about; one
    /// who is told what pressing it will now do has been given something to
    /// decide.
    public var explanation: String {
        switch self {
        case .systemShortcut(let does):
            // Cheppu's watch on the keyboard can read a key and cannot swallow
            // one (ADR-0006), so the shortcut is not taken away — it is
            // doubled, which is the thing the user actually has to picture.
            "macOS uses it to \(does). Cheppu never takes a keystroke from another app, so "
                + "pressing it would start a dictation and \(does) at the same time."
        case .globeKey:
            "macOS does not hand the Globe key to apps the way it hands over every other key, "
                + "so Cheppu needs Input Monitoring to see it. And unless System Settings › "
                + "Keyboard › “Press 🌐 key to” is set to “Do Nothing”, macOS acts on the press "
                + "itself and Cheppu never sees it at all."
        }
    }
}
