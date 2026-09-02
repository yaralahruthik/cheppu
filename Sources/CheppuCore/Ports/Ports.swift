import Foundation

// Cheppu's core decides; the ports do. Each one is the narrowest description of
// a thing the core needs done that it cannot do itself, and each has exactly two
// implementations: the real one in the app target, and a fake in the core suite.
//
// This is what lets the whole of Cheppu's behaviour be tested with no
// permissions granted, no Engine downloaded, no network, and no audio hardware.

/// What the user did with the Hotkey.
///
/// The port reports the gesture and nothing about how it was produced — a tap of
/// a bare modifier, a chord, or a test. Hold and Escape join it with their own
/// tickets.
public enum HotkeyEvent: Equatable, Sendable {
    case activationStarted
    case activationStopped
}

/// Where Activation gestures come from.
///
/// Nothing observes this yet: until the real `CGEvent` tap lands, a Dictation is
/// driven through `DictationCore.receive(_:)` directly.
public protocol HotkeyPort: Sendable {
    /// Starts reporting Activation gestures, replacing any handler already
    /// installed.
    func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async
}

/// The microphone.
public protocol AudioCapturePort: Sendable {
    /// Begins capturing. Called first of everything a Dictation does, so that no
    /// speech is lost to the Cue that follows it.
    func startCapturing() async throws

    /// Ends capturing and hands over what was captured.
    func stopCapturing() async throws -> CapturedAudio
}

/// The on-device speech-to-text model.
public protocol EnginePort: Sendable {
    /// Turns captured audio into a Raw Transcript with per-word timings.
    ///
    /// Called once the Dictation has stopped. There is no streaming or
    /// partial-result path.
    func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript
}

/// Placing Final Text at the text cursor of the Target App.
public protocol InsertionPort: Sendable {
    /// Inserts the Final Text as if it had been typed. Throwing means it did not
    /// land, and the Clipboard Fallback ticket decides what happens then.
    func insert(_ finalText: FinalText) async throws
}

/// The pasteboard, which Cheppu borrows and gives back.
public protocol ClipboardPort: Sendable {
    func read() async -> String?
    func write(_ text: String) async
}

/// The local store that makes sure nothing said is ever lost.
public protocol HistoryPort: Sendable {
    /// Appends one Dictation's Final Text. Called before Insertion is attempted,
    /// on every path out of Transcribing.
    func append(_ entry: HistoryEntry) async throws
}

/// The Pill and the Cues — the two senses through which the user knows the
/// state without looking at Cheppu.
public protocol FeedbackPort: Sendable {
    func showPill(_ state: PillState) async
    func hidePill() async
    func play(_ cue: Cue) async
}

/// Every reading of the time the core takes.
///
/// Nothing in the core calls a system clock directly, so a test can stamp a
/// History entry, and later reach the Cap and the hold threshold, without
/// waiting. The waiting half of this port arrives with the Cap, which is the
/// first thing that needs it.
public protocol ClockPort: Sendable {
    func now() async -> Date
}
