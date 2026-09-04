import Foundation

@testable import CheppuCore

/// The Hotkey the tests press.
///
/// A real one watches the whole keyboard for one key; this one is tapped when
/// the test says so, which is the same thing to the core. It can also be a
/// keyboard Cheppu is not allowed to watch, which is what a machine without
/// Accessibility granted looks like from here.
actor FakeHotkey: HotkeyPort {
    private let isAccessibilityGranted: Bool
    private var reportTo: (@Sendable (HotkeyEvent) async -> Void)?

    init(isAccessibilityGranted: Bool = true) {
        self.isAccessibilityGranted = isAccessibilityGranted
    }

    func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async throws {
        guard isAccessibilityGranted else { throw HotkeyFailure.accessibilityDenied }
        reportTo = handler
    }

    /// The user taps the Hotkey.
    ///
    /// Waits for everything the tap set in motion, so a test can tap twice and
    /// then read back a whole Dictation.
    func tap() async {
        await reportTo?(.tapped)
    }

    /// Whether anything is listening for a tap.
    var isBeingWatched: Bool { reportTo != nil }
}

/// Audio capture that hands back canned audio without a microphone.
struct FakeAudioCapture: AudioCapturePort {
    let journal: PortJournal
    let captured: CapturedAudio

    /// What this microphone hears the moment capture opens. A real one reports
    /// as the buffers arrive; reporting them all at once is the same thing to
    /// the core, and it happens when the test says so rather than when a
    /// scheduler gets round to it.
    var hearsLevels: [InputLevel] = []

    func startCapturing(reporting report: @escaping @Sendable (InputLevel) async -> Void)
        async throws
    {
        await journal.record(.capturingStarted)
        for level in hearsLevels {
            await report(level)
        }
    }

    func stopCapturing() async throws -> CapturedAudio {
        await journal.record(.capturingStopped)
        return captured
    }
}

/// An Engine that returns a canned Raw Transcript, so the core suite never
/// loads a model.
struct FakeEngine: EnginePort {
    let journal: PortJournal
    let transcript: RawTranscript

    func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript {
        await journal.record(.transcribed(audio))
        return transcript
    }
}

/// The two apps the user is working in: the one they were writing an email in,
/// and the one they switched to.
enum ATargetApp {
    static let mail = TargetApp(bundleIdentifier: "com.apple.mail", processIdentifier: 501)
    static let browser = TargetApp(bundleIdentifier: "com.apple.Safari", processIdentifier: 502)
}

/// Where the keyboard is pointing, as the test says it is.
///
/// A real Insertion asks macOS which app is frontmost; this one is told, and
/// can be told again mid-Dictation, which is how a test moves the user from one
/// app to another while they are still speaking.
actor FakeFocus {
    private(set) var app: TargetApp?

    init(on app: TargetApp?) {
        self.app = app
    }

    /// The user clicks into another app.
    func moveTo(_ app: TargetApp?) {
        self.app = app
    }
}

/// Insertion into a Target App that is only ever asked what it was told to
/// insert, and where.
struct FakeInsertion: InsertionPort {
    /// What this Insertion does when it is finally asked to put the words
    /// somewhere.
    enum Outcome {
        /// It lands, and the journal says where.
        case lands

        /// It will not go through, for a reason the user is not told yet. What
        /// they are told is the Clipboard Fallback ticket's; all this outcome
        /// is for is showing that a Dictation which fails still ends.
        case refuses

        /// The user has moved to another app while the Engine worked, so it is
        /// abandoned rather than typed into the wrong window.
        case findsTheFocusMoved
    }

    /// An Insertion that would not go through, whatever the reason.
    struct Refused: Error {}

    let journal: PortJournal
    let focus: FakeFocus
    var outcome: Outcome = .lands

    func focusedApp() async -> TargetApp? {
        await focus.app
    }

    func insert(_ finalText: FinalText, into targetApp: TargetApp) async throws {
        switch outcome {
        case .lands:
            await journal.record(.inserted(finalText, into: targetApp))
        case .refuses:
            throw Refused()
        case .findsTheFocusMoved:
            throw InsertionFailure.focusMoved
        }
    }
}

/// A pasteboard that remembers one string.
actor FakeClipboard: ClipboardPort {
    private var contents: String?

    init(contents: String? = nil) {
        self.contents = contents
    }

    func read() async -> String? {
        contents
    }

    func write(_ text: String) async {
        contents = text
    }
}

/// History in memory.
struct FakeHistory: HistoryPort {
    let journal: PortJournal

    func append(_ entry: HistoryEntry) async throws {
        await journal.record(.appendedToHistory(entry))
    }
}

/// The Pill and the Cues, written down instead of shown and played.
struct FakeFeedback: FeedbackPort {
    let journal: PortJournal

    func showPill(_ state: PillState) async {
        await journal.record(.pillShown(state))
    }

    func hidePill() async {
        await journal.record(.pillHidden)
    }

    func play(_ cue: Cue) async {
        await journal.record(.cuePlayed(cue))
    }
}

/// A Clock the test moves by hand. Time passes when a test says so and never
/// because it waited.
actor FakeClock: ClockPort {
    private var reading: Date

    init(reading: Date) {
        self.reading = reading
    }

    func now() async -> Date {
        reading
    }

    func advance(by duration: Duration) {
        reading += duration.asTimeInterval
    }
}

extension Duration {
    /// This Duration in the seconds `Date` counts in.
    var asTimeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}
