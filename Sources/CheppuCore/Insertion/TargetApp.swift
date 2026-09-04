/// The application that has keyboard focus at the moment the Dictation stops,
/// and that receives the Insertion.
///
/// Noted when the Dictation stops rather than when it starts, because that is
/// where the user is looking when they finish speaking. Between the two they
/// may have clicked into a different window, and the words belong where they
/// are, not where they were.
///
/// Three things describe it, and each answers a different question. The process
/// is which app this is — the only thing that can tell "still the app I was
/// dictating into" from "something else came to the front while the Engine was
/// working". The bundle identifier and the focused element's role are what kind
/// of app it is and what kind of thing inside it the keyboard is pointing at,
/// which together are the whole of what Terminal awareness has to read (#12).
public struct TargetApp: Equatable, Sendable {
    /// What kind of app it is, where it has a bundle to say so. A process
    /// launched without one — a bare binary in a Terminal — has none, which is
    /// why it is optional rather than a promise.
    public let bundleIdentifier: String?

    /// The running process, as macOS numbers them. `Int32` rather than `pid_t`
    /// so that the core names it without reaching for a system framework; the
    /// app target is where the two meet.
    public let processIdentifier: Int32

    /// The accessibility role of whatever has keyboard focus, as macOS names it
    /// — `AXTextArea` for the body of a mail message, `AXTextField` for a search
    /// box.
    ///
    /// Nothing, where the app exposes no focused element at all. That is not a
    /// gap in the reading: an app that answers nothing about what the keyboard
    /// is pointing at is exactly the shape most Terminals have, which is what
    /// `isATerminal` reads it for.
    ///
    /// A property of the moment rather than of the app, unlike the two above,
    /// and it is here because it is read at the same instant and for the same
    /// Insertion. `isTheSameAppAs(_:)` is what asks whether focus has moved, so
    /// the user clicking from a field to a button inside the app they dictated
    /// into does not read as the app having changed.
    public let focusedElementRole: String?

    public init(bundleIdentifier: String?, processIdentifier: Int32, focusedElementRole: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.focusedElementRole = focusedElementRole
    }

    /// Whether this is the same running app as another reading of focus.
    ///
    /// The process and nothing else, because the process is what "which app is
    /// this" means: a bundle identifier can be missing, and two readings a
    /// moment apart differ in the focused element's role every time the user
    /// clicks from one control to another without leaving the app.
    ///
    /// This is what Insertion checks before it types, so that a Dictation lands
    /// in the app it was meant for or nowhere.
    public func isTheSameAppAs(_ other: TargetApp) -> Bool {
        processIdentifier == other.processIdentifier
    }
}
