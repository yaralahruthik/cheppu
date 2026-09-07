import CheppuCore
import Foundation

/// Everything the user has set, where macOS keeps it.
///
/// One place, and it is the standard user defaults domain under Cheppu's own
/// bundle identifier (ADR-0004). There is no configuration file anybody is
/// expected to find or edit: what the user changes, they change in the Settings
/// window, and what Cheppu remembers is a handful of switches. History is the
/// deliberate exception and lives in a file of its own (ADR-0009).
///
/// Every switch is on unless the user has said otherwise, and that is the whole
/// of the default: someone who has never opened the window gets a Dictation
/// that is cleaned up and that they can hear, which is what they would have
/// chosen. Read at the moment each switch matters rather than held, so moving
/// one takes effect on the next Dictation and not the next launch (ADR-0010).
///
/// `UserDefaults` is documented as thread-safe and is reachable from wherever a
/// Dictation happens to be running; Swift cannot see that, so the promise is
/// made here rather than by wrapping it in an actor nothing would gain from.
public struct Preferences: CueSwitch, CleanupSwitches, HotkeyChoice, @unchecked Sendable {
    /// The keys, named for what they hold rather than for the row that shows
    /// them, so that renaming a control in the window cannot silently forget
    /// what the user chose.
    ///
    /// `CuesAreOn` is the key the menu bar has been writing since #10, and it
    /// keeps that name: a user who turned the sounds off before there was a
    /// Settings window still has them off after there is one.
    enum Key {
        static let cuesAreOn = "CuesAreOn"
        static let hotkey = "Hotkey"

        static func cleanup(_ rule: CleanupRule) -> String {
            switch rule {
            case .removesFillerWords: "CleanupRemovesFillerWords"
            case .capitalisesSentences: "CleanupCapitalisesSentences"
            case .breaksParagraphs: "CleanupBreaksParagraphs"
            }
        }
    }

    private let defaults: UserDefaults

    /// The user's own preferences.
    public init() {
        self.defaults = .standard
    }

    /// - Parameter defaults: the domain to keep the switches in. The suite uses
    ///   this to write somewhere of its own; Cheppu itself never passes it, so
    ///   running the tests cannot change what the user set.
    init(in defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Which key the user dictates with.
    ///
    /// Answered without suspending, unlike the port it satisfies, so that the
    /// window can draw the row from it as it is being opened.
    ///
    /// A remembered Hotkey nothing can read — a domain edited by hand, or one
    /// written by a version that spelled it differently — is the default rather
    /// than nothing at all. The alternative is an app whose key does nothing
    /// and that never says why.
    public func hotkey() -> Hotkey {
        defaults.string(forKey: Key.hotkey).flatMap(Hotkey.init(written:)) ?? .byDefault
    }

    /// Sets the key the user dictates with.
    ///
    /// Written down by name rather than by key code, so that a position that
    /// means something else on the next keyboard cannot silently become a
    /// different Hotkey.
    public func choose(_ hotkey: Hotkey) {
        defaults.set(hotkey.written, forKey: Key.hotkey)
    }

    /// Whether a Dictation makes a sound.
    ///
    /// Answered without suspending, unlike the port it satisfies, so that the
    /// menu can be built from it as it is opened rather than a moment
    /// afterwards.
    public func areCuesOn() -> Bool {
        isOn(Key.cuesAreOn)
    }

    /// Turns the Cues on or off, for a user dictating in a meeting.
    public func turnCues(on: Bool) {
        defaults.set(on, forKey: Key.cuesAreOn)
    }

    /// Which Cleanup rules a Dictation's words go through.
    ///
    /// Answered without suspending for the same reason the Cues are: the window
    /// draws three switches from this while it is being opened.
    public func rules() -> CleanupRules {
        CleanupRules(
            removesFillerWords: isOn(Key.cleanup(.removesFillerWords)),
            capitalisesSentences: isOn(Key.cleanup(.capitalisesSentences)),
            breaksParagraphs: isOn(Key.cleanup(.breaksParagraphs))
        )
    }

    /// Moves one Cleanup rule, and leaves the other two where they were.
    ///
    /// One key per rule rather than one key holding all three, so that a rule
    /// added later arrives on unless the user turns it off, rather than off
    /// because the value they saved never mentioned it.
    public func turn(_ rule: CleanupRule, on: Bool) {
        defaults.set(on, forKey: Key.cleanup(rule))
    }

    /// A switch the user has never touched is on.
    ///
    /// Asked for as an object rather than as a `Bool`, because a missing key
    /// reads as `false` otherwise — which would turn every default off for
    /// everyone who has not been to Settings.
    private func isOn(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
