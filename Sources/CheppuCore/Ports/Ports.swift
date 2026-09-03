import Foundation

// Cheppu's core decides; the ports do. Each one is the narrowest description of
// a thing the core needs done that it cannot do itself, and each has exactly two
// implementations: the real one in whichever target owns that piece of the OS —
// the app, the Engine, the microphone — and a fake in the core suite.
//
// This is what lets the whole of Cheppu's behaviour be tested with no
// permissions granted, no Engine downloaded, no network, and no audio hardware.

/// What the user did with the Hotkey.
///
/// The port reports the gesture and nothing about how it was produced — a tap of
/// a bare modifier, a chord, or a test. Hold and Escape join it with their own
/// tickets.
public enum HotkeyEvent: Equatable, Sendable {
    /// The Hotkey was tapped on its own: pressed and released with no other key
    /// held and nothing typed in between.
    ///
    /// What a tap means depends on whether a Dictation is running, and the
    /// keyboard is the one place that cannot know. So the port reports the tap
    /// and the machine decides, which is what keeps a tap after the Cap has
    /// ended a Dictation a start rather than a stop nobody is waiting for.
    case tapped
}

/// Where Activation gestures come from.
public protocol HotkeyPort: Sendable {
    /// Starts reporting Activation gestures, replacing any handler already
    /// installed.
    ///
    /// Throwing means Cheppu may not watch the keyboard —
    /// `HotkeyFailure.accessibilityDenied` — so that a Hotkey which cannot work
    /// is something the app says out loud rather than a key that does nothing.
    func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async throws
}

/// The microphone.
public protocol AudioCapturePort: Sendable {
    /// Begins capturing, reporting how loud it is hearing as it goes. Called
    /// first of everything a Dictation does, so that no speech is lost to the
    /// Cue that follows it.
    ///
    /// Throwing means the Dictation has no microphone — access refused, or a
    /// device that would not open — and the core takes the Dictation down
    /// rather than listening to nothing.
    ///
    /// A refusal throws `AudioCaptureFailure.accessDenied`, which is the core's
    /// own vocabulary rather than the microphone's, so that the core can tell a
    /// refusal from a device that would not open.
    ///
    /// The report may suspend, so that the levels reach the core in the order
    /// they were heard. Whoever holds the microphone is responsible for the
    /// hand-off never reaching the audio thread, which cannot afford to wait.
    func startCapturing(reporting: @escaping @Sendable (InputLevel) async -> Void) async throws

    /// Ends capturing and hands over what was captured.
    ///
    /// The audio belongs to the caller from here: whoever was holding it lets
    /// go, so that nothing outlives the Dictation that produced it.
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

/// Putting the Engine on the machine.
///
/// Separate from `EnginePort` because the two are asked for at different moments
/// by different callers: Onboarding downloads once, a Dictation transcribes many
/// times. One object in the app target satisfies both, which is where the
/// ordering between them — nothing transcribes before the download has finished
/// — actually lives.
public protocol EngineDownloadPort: Sendable {
    /// Whether every file the Engine needs is already on the machine.
    ///
    /// Answered from disk, without the network, so that the ordinary launch —
    /// the Engine is already here — costs nothing.
    func isEngineDownloaded() async -> Bool

    /// Fetches whatever the Engine is missing, reporting progress as it arrives.
    ///
    /// Called again after an interrupted attempt, it carries on from where the
    /// last one stopped rather than starting the 600 MB over. Returning normally
    /// means the Engine is ready; throwing leaves what did arrive in place for
    /// the next attempt to build on.
    ///
    /// The report is a notification and not a request: nothing waits on it, so
    /// it is handed over synchronously rather than made something the download
    /// has to await before fetching the next chunk.
    func downloadEngine(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws
}

/// Placing Final Text at the text cursor of the Target App.
public protocol InsertionPort: Sendable {
    /// Which app has keyboard focus this instant, or nothing if none has.
    ///
    /// Asked when the Dictation stops, which is what makes the Target App the
    /// app the user was in when they finished speaking rather than the one they
    /// started in.
    func focusedApp() async -> TargetApp?

    /// Inserts the Final Text at the text cursor of the Target App, as if it
    /// had been typed.
    ///
    /// The Target App is passed rather than looked up again because the
    /// Insertion is *for* that app: throwing `InsertionFailure.focusMoved`
    /// where it is no longer the app with focus is what stops a Dictation
    /// landing in whichever window came to the front while the Engine was
    /// working. The check belongs next to the keystroke rather than up here,
    /// where anything between the two would be a window for focus to move in.
    ///
    /// Throwing means it did not land, and the Clipboard Fallback ticket
    /// decides what the user is told about that.
    func insert(_ finalText: FinalText, into targetApp: TargetApp) async throws
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
