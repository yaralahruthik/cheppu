import Foundation

@testable import CheppuCore

/// The Hotkey the tests press. Nothing is wired to it yet: the core is driven
/// through its own door until the real `CGEvent` tap arrives.
struct FakeHotkey: HotkeyPort {
    func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async {}
}

/// Audio capture that hands back canned audio without a microphone.
struct FakeAudioCapture: AudioCapturePort {
    let journal: PortJournal
    let captured: CapturedAudio

    func startCapturing() async throws {
        await journal.record(.capturingStarted)
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

/// Insertion into a Target App that is only ever asked what it was told to
/// insert.
struct FakeInsertion: InsertionPort {
    let journal: PortJournal

    func insert(_ finalText: FinalText) async throws {
        await journal.record(.inserted(finalText))
    }
}

/// An Insertion that will not go through, whatever the reason. What the user is
/// told about it is the Clipboard Fallback ticket's; all this fake is for is
/// showing that a Dictation which fails still ends.
struct RefusingInsertion: InsertionPort {
    struct Refused: Error {}

    func insert(_ finalText: FinalText) async throws {
        throw Refused()
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
