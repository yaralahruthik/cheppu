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

    /// The same words with no whitespace of their own at either end, which is
    /// how they go into the Target App.
    ///
    /// The Engine hands back a leading space and a trailing newline often
    /// enough that dictating into the middle of a sentence would double the
    /// space already in front of the cursor and leave a line break behind the
    /// words. Cheppu cannot read what surrounds the cursor — that would mean
    /// reading the user's document in order to insert into it — so what joins
    /// sensibly is to contribute no whitespace of its own and let the sentence
    /// the user is already writing supply the spaces
    /// (`docs/product-experience.md` §5).
    ///
    /// Applied at the Insertion boundary rather than to the Final Text itself,
    /// which is where Terminal awareness will be applied too (#12): what is
    /// kept is what was said, and what is typed is what fits where it is going.
    /// It is also what leaves Cleanup free to promise that with every rule off
    /// the Final Text is the Raw Transcript, byte for byte (#11).
    public var normalisedForInsertion: FinalText {
        FinalText(text.trimmingCharacters(in: .whitespacesAndNewlines))
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

/// How loud the microphone is hearing, from silence to the loudest it can hear.
///
/// A number the Pill can draw directly rather than decibels it would have to
/// interpret: the question the user is asking is "can it hear me right now?",
/// and the answer to that is a height, not a measurement. What that number is
/// made of — the loudness of a buffer, and how fast the reading is allowed to
/// fall — belongs to whoever is holding the microphone.
public struct InputLevel: Equatable, Sendable {
    /// Silence, and where the Pill opens: a Dictation must never look like it
    /// is hearing something before it has heard anything.
    public static let silent = InputLevel(0)

    public let value: Double

    /// Clamped, because a level outside 0...1 is not something the Pill could
    /// draw and not something the user could read.
    public init(_ value: Double) {
        self.value = min(max(value, 0), 1)
    }
}

/// What the Pill is showing.
///
/// The two states the user has to be able to tell apart without looking
/// carefully: it is hearing me, and it is working on what it heard.
///
/// Listening carries the level rather than sitting next to it. A Pill that says
/// "listening" and nothing else answers the wrong question — the user wants to
/// know it is hearing *them*, not that it is switched on (see
/// `docs/product-experience.md` §3) — so the two are never separable states.
public enum PillState: Equatable, Sendable {
    case listening(InputLevel)
    case transcribing
}

/// A short sound marking the edge of a Dictation, so one can be run by feel.
public enum Cue: Equatable, Sendable {
    case dictationStarted
    case dictationStopped
}
