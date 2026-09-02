import Foundation

/// The audio one Dictation captured, on its way from the microphone to the
/// Engine and no further.
///
/// The core never looks inside. It carries this from the Audio capture port to
/// the Engine port and then lets go of it, which is what keeps the promise that
/// audio is never written to disk and never outlives the Dictation that
/// produced it.
public struct CapturedAudio: Equatable, Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// Where one word fell in the Dictation, measured from its start.
///
/// Cleanup needs the gap between two words to decide whether the speaker paused
/// long enough to mean a Paragraph Break, so the Engine reports timings from the
/// beginning rather than growing a second return value later.
public struct WordTiming: Equatable, Sendable {
    public let word: String
    public let start: Duration
    public let end: Duration

    public init(word: String, start: Duration, end: Duration) {
        self.word = word
        self.start = start
        self.end = end
    }
}

/// The text exactly as the Engine produced it, before Cleanup.
public struct RawTranscript: Equatable, Sendable {
    public let text: String
    public let words: [WordTiming]

    public init(text: String, words: [WordTiming]) {
        self.text = text
        self.words = words
    }
}

/// The text that is inserted into the Target App and kept in History — what the
/// user thinks of as "what I said".
///
/// It is a type of its own rather than a `String` so that a Raw Transcript
/// cannot be inserted by accident once Cleanup stands between the two. Making it
/// from a string is deliberate for the same reason — there is no string literal
/// shorthand.
public struct FinalText: Equatable, Sendable {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }
}

/// One line of History: what was said, and when.
///
/// Text and a timestamp is the whole of it. No audio, no Raw Transcript, and no
/// record of where it was inserted.
public struct HistoryEntry: Equatable, Sendable {
    public let finalText: FinalText
    public let recordedAt: Date

    public init(finalText: FinalText, recordedAt: Date) {
        self.finalText = finalText
        self.recordedAt = recordedAt
    }
}

/// What the Pill is showing.
///
/// The two states the user has to be able to tell apart without looking
/// carefully: it is hearing me, and it is working on what it heard.
public enum PillState: Equatable, Sendable {
    case listening
    case transcribing
}

/// A short sound marking the edge of a Dictation, so one can be run by feel.
public enum Cue: Equatable, Sendable {
    case dictationStarted
    case dictationStopped
}
