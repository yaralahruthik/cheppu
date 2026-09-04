import Foundation

@testable import CheppuCore

/// The Hotkey the tests press.
///
/// A real one watches the whole keyboard for one key; this one is pressed when
/// the test says so, which is the same thing to the core. It can also be a
/// keyboard Cheppu is not allowed to watch, which is what a machine without
/// Accessibility granted looks like from here.
///
/// How long a press lasted is not in here, because it is not in a real keyboard
/// either: a test holds the Hotkey down by moving the Clock between pressing it
/// and letting go.
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

    /// The user presses the Hotkey.
    ///
    /// Waits for everything the press set in motion, so a test can press and
    /// let go and then read back a whole Dictation.
    func press() async {
        await reportTo?(.pressed)
    }

    /// The user lets go of it.
    func release() async {
        await reportTo?(.released)
    }

    /// The user types with it held down, which is an accented character rather
    /// than an Activation.
    func typeWithItHeld() async {
        await reportTo?(.pressSpoiled)
    }

    /// The user presses Escape, wherever they are and whatever Cheppu is doing.
    func pressEscape() async {
        await reportTo?(.escapePressed)
    }

    /// Whether anything is listening for the Hotkey.
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

/// The apps the user is working in: the one they were writing an email in, the
/// one they switched to, and the two they run commands in.
enum ATargetApp {
    static let mail = TargetApp(
        bundleIdentifier: "com.apple.mail", processIdentifier: 501,
        focusedElementRole: "AXTextArea")

    static let browser = TargetApp(
        bundleIdentifier: "com.apple.Safari", processIdentifier: 502,
        focusedElementRole: "AXTextField")

    /// A Terminal Cheppu knows by name, exposing the same ordinary text area as
    /// the mail window above. Being on the list is what tells them apart.
    static let terminal = TargetApp(
        bundleIdentifier: "com.apple.Terminal", processIdentifier: 503,
        focusedElementRole: "AXTextArea")

    /// A Terminal Cheppu has never heard of, which draws its own screen and so
    /// exposes no focused element to ask about. Nobody has to have added it to a
    /// list for a newline to be dangerous in it.
    static let anUnfamiliarTerminal = TargetApp(
        bundleIdentifier: "com.example.SomeoneElsesTerminal", processIdentifier: 504,
        focusedElementRole: nil)
}

/// Raw Transcripts to put in the Engine's mouth.
enum ARawTranscript {
    /// One Dictation with all three Cleanup rules' worth of work in it: a
    /// Filler Word, two sentences that do not start with a capital, and a
    /// two-second pause between them.
    ///
    /// Shared by the three suites that ask what Cleanup did with it — the rules
    /// themselves, the machine that applies them, and the core the app builds —
    /// so that all three are talking about the same Dictation.
    static let saidWithAPause = RawTranscript(
        text: "um, that is one thought. the next one",
        words: [
            WordTiming(word: "um,", start: .zero, end: .milliseconds(200)),
            WordTiming(word: "that", start: .milliseconds(300), end: .milliseconds(500)),
            WordTiming(word: "is", start: .milliseconds(600), end: .milliseconds(800)),
            WordTiming(word: "one", start: .milliseconds(900), end: .milliseconds(1_100)),
            WordTiming(word: "thought.", start: .milliseconds(1_200), end: .milliseconds(1_700)),
            WordTiming(word: "the", start: .milliseconds(3_700), end: .milliseconds(3_900)),
            WordTiming(word: "next", start: .milliseconds(4_000), end: .milliseconds(4_200)),
            WordTiming(word: "one", start: .milliseconds(4_300), end: .milliseconds(4_500)),
        ]
    )
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
    /// A History that will not take what it is handed — a disk that is full,
    /// or a store that cannot be opened. What the user is told about that is
    /// #13's and #14's; what it is here for is that a Dictation which fails on
    /// its way out still ends.
    struct Refused: Error {}

    let journal: PortJournal
    var refuses = false

    func append(_ entry: HistoryEntry) async throws {
        guard !refuses else { throw Refused() }
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

    /// The wait under way, and the moment it ends. There is one at a time here
    /// for the same reason there is one on a real Clock.
    private var waiting: (until: Date, whatFollows: @Sendable () async -> Void)?

    init(reading: Date) {
        self.reading = reading
    }

    func now() async -> Date {
        reading
    }

    /// Notes the wait rather than taking it. Nothing happens until the test
    /// moves the Clock past the end of it.
    func waitOut(_ span: Duration, then whatFollows: @escaping @Sendable () async -> Void) async {
        waiting = (reading + span.asTimeInterval, whatFollows)
    }

    func stopWaiting() async {
        waiting = nil
    }

    /// Moves the Clock on, and runs whatever was waiting for a moment now past.
    ///
    /// It does not return until everything that wait set in motion has finished,
    /// so a test that moves the Clock five minutes on can read back the whole
    /// Dictation the Cap ended without ever wondering whether it is over.
    func advance(by duration: Duration) async {
        reading += duration.asTimeInterval

        guard let waiting, waiting.until <= reading else { return }
        self.waiting = nil
        await waiting.whatFollows()
    }
}

extension Duration {
    /// This Duration in the seconds `Date` counts in.
    var asTimeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}
