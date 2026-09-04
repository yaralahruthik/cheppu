/// The application that has keyboard focus at the moment the Dictation stops,
/// and that receives the Insertion.
///
/// Noted when the Dictation stops rather than when it starts, because that is
/// where the user is looking when they finish speaking. Between the two they
/// may have clicked into a different window, and the words belong where they
/// are, not where they were.
///
/// Two things identify it, and each answers a different question. The process
/// is which app this is — the only thing that can tell "still the app I was
/// dictating into" from "something else came to the front while the Engine was
/// working". The bundle identifier is what kind of app it is, which is what
/// Terminal awareness reads (#12).
public struct TargetApp: Equatable, Sendable {
    /// What kind of app it is, where it has a bundle to say so. A process
    /// launched without one — a bare binary in a terminal — has none, which is
    /// why it is optional rather than a promise.
    public let bundleIdentifier: String?

    /// The running process, as macOS numbers them. `Int32` rather than `pid_t`
    /// so that the core names it without reaching for a system framework; the
    /// app target is where the two meet.
    public let processIdentifier: Int32

    public init(bundleIdentifier: String?, processIdentifier: Int32) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}
