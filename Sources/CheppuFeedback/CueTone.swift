import CheppuCore
import Foundation

/// The sound one Cue is made of.
///
/// Two notes and an envelope, computed rather than shipped as an audio file.
/// `Scripts/make-app.sh` assembles the bundle by hand and ADR-0003 rules out
/// the resource machinery an Xcode project would have brought, so a Cue is
/// written down here for the same reason the menu bar icon is drawn in code:
/// it is the one form that cannot go missing from the bundle.
///
/// It is also the form that can be held to something. What a Cue has to be is
/// short, unmistakable from the other two, and free of the click a tone cut off
/// mid-cycle makes — and all three of those are readable off the samples.
struct CueTone: Hashable, Sendable {
    /// Frames per second. 44.1 kHz is what every Mac plays without resampling.
    static let sampleRate: Double = 44_100

    /// How long one note lasts, in seconds.
    ///
    /// Short enough that the pair is over in about a tenth of a second: the
    /// start Cue plays over a microphone that is already open, and the stop Cue
    /// is on the path to the words appearing (`docs/product-experience.md` §7).
    /// Neither may be something the user waits through.
    static let note: Double = 0.055

    /// How long a note takes to come up to full and go back down, in seconds.
    ///
    /// The whole of what keeps a Cue from clicking. A sine wave that begins at
    /// full amplitude begins with a step, and a step is heard as a click —
    /// which is the one sound a Cue must not make, because it says something
    /// went wrong rather than something began.
    static let edge: Double = 0.008

    /// How loud a Cue is, as a fraction of full scale.
    ///
    /// Quiet on purpose. This plays hundreds of times a day next to the user's
    /// own voice, and a Cue that has to be turned down is one that gets turned
    /// off.
    static let gain: Double = 0.22

    /// The notes, in order, in hertz.
    let notes: [Double]

    /// What each Cue sounds like.
    ///
    /// The three are told apart by shape rather than by pitch, because shape is
    /// what survives a laptop speaker, a room with people in it, and a user who
    /// is not listening for it: a Dictation opens, closes, or is thrown away.
    static func of(_ cue: Cue) -> CueTone {
        switch cue {
        // Up: something has opened, and the microphone is already listening
        // through it.
        case .dictationStarted: CueTone(notes: [660, 990])

        // The same two notes the other way round. A pair the ear hears as
        // opening and closing is what lets a Dictation be run entirely by feel
        // (`docs/product-experience.md` §3).
        case .dictationStopped: CueTone(notes: [990, 660])

        // Neither up nor down, and lower than both: two knocks on the same low
        // note. A rise and a fall already mean "listening" and "the words are
        // on their way", and Cancel has to say the opposite of the second of
        // those — that there are none.
        case .dictationCancelled: CueTone(notes: [330, 330])
        }
    }

    /// The sound itself, one note after another.
    var samples: [Float] {
        let framesPerNote = Int(Self.note * Self.sampleRate)

        return notes.flatMap { frequency in
            (0..<framesPerNote).map { frame in
                let second = Double(frame) / Self.sampleRate
                let wave = sin(2 * .pi * frequency * second)
                return Float(wave * Self.gain * Self.envelope(at: second))
            }
        }
    }

    /// How much of the note is sounding this far into it: nothing at either
    /// end, and everything in the middle.
    private static func envelope(at second: Double) -> Double {
        min(min(second, note - second) / edge, 1)
    }

    /// The same sound as a 16-bit mono WAV.
    ///
    /// A container rather than bare samples because what plays this is
    /// `NSSound`, which takes a sound file's contents and nothing else. It is
    /// forty-four bytes of header — the smallest thing that stands between a
    /// computed tone and something the Mac will play, and small enough to be
    /// checked rather than trusted.
    var wav: Data {
        let samples = samples
        let bytesOfSound = samples.count * 2

        var wav = Data(capacity: 44 + bytesOfSound)
        wav.append(tag: "RIFF")
        wav.append(UInt32(36 + bytesOfSound))
        wav.append(tag: "WAVE")

        wav.append(tag: "fmt ")
        wav.append(UInt32(16))  // The length of this chunk: uncompressed audio.
        wav.append(UInt16(1))  // Linear PCM.
        wav.append(UInt16(1))  // One channel.
        wav.append(UInt32(Self.sampleRate))
        wav.append(UInt32(Self.sampleRate) * 2)  // Bytes a second.
        wav.append(UInt16(2))  // Bytes a frame.
        wav.append(UInt16(16))  // Bits a sample.

        wav.append(tag: "data")
        wav.append(UInt32(bytesOfSound))
        for sample in samples {
            // Clamped on the way in as well as on the way out of the envelope,
            // because a sample past full scale does not wrap quietly here: it
            // wraps to the opposite extreme, and the Cue would carry a crack
            // through the middle of it.
            let full = (Double(sample) * Double(Int16.max)).rounded()
            let sixteenBit = Int16(min(max(full, Double(Int16.min)), Double(Int16.max)))
            wav.append(UInt16(bitPattern: sixteenBit))
        }
        return wav
    }
}

extension Data {
    /// A chunk name, which a WAV writes as its four characters.
    fileprivate mutating func append(tag: String) {
        append(contentsOf: Array(tag.utf8))
    }

    /// A number, which a WAV writes least significant byte first.
    fileprivate mutating func append(_ number: UInt32) {
        Swift.withUnsafeBytes(of: number.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(_ number: UInt16) {
        Swift.withUnsafeBytes(of: number.littleEndian) { append(contentsOf: $0) }
    }
}
