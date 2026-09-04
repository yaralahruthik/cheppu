import CheppuCore
import Foundation
import Testing

@testable import CheppuFeedback

// A Cue is heard rather than seen, so what a test can hold it to is what makes
// it hearable: that the three are told apart by ear, that they are short enough
// to be over before the user has spoken a word, and that they begin and end at
// silence rather than with the click a tone cut off mid-cycle makes.
@Suite("Cue tones")
struct CueToneTests {
    @Test("The three Cues are three different sounds")
    func theThreeCuesAreThreeDifferentSounds() {
        let tones = Set(Cue.allCases.map(CueTone.of))

        #expect(tones.count == Cue.allCases.count)
    }

    @Test("Starting rises and stopping is the same sound backwards")
    func startingRisesAndStoppingIsTheSameSoundBackwards() {
        let start = CueTone.of(.dictationStarted)
        let stop = CueTone.of(.dictationStopped)

        // Two notes, one way and then the other. A Dictation is a thing that
        // opens and closes, and a pair the ear hears as opening and closing is
        // what lets one be run without looking (`docs/product-experience.md` §3).
        #expect(start.notes.first! < start.notes.last!)
        #expect(stop.notes == start.notes.reversed())
    }

    @Test("Cancelling is neither of them")
    func cancellingIsNeitherOfThem() {
        let cancel = CueTone.of(.dictationCancelled)

        // Not a rise and not a fall: the two shapes already mean "listening"
        // and "the words are on their way", and Cancel means there are none.
        #expect(cancel.notes.first == cancel.notes.last)
        #expect(cancel.notes.min()! < CueTone.of(.dictationStarted).notes.min()!)
    }

    @Test("Every Cue is over before the user has said a word")
    func everyCueIsOverBeforeTheUserHasSaidAWord() {
        for cue in Cue.allCases {
            let tone = CueTone.of(cue)
            let seconds = Double(tone.samples.count) / CueTone.sampleRate

            // The start Cue plays over an open microphone and the stop Cue is
            // on the way to the words appearing (§7). Neither may be something
            // the user notices the length of.
            #expect(seconds > 0.05)
            #expect(seconds < 0.2)
        }
    }

    @Test("Every Cue begins and ends at silence")
    func everyCueBeginsAndEndsAtSilence() {
        for cue in Cue.allCases {
            let samples = CueTone.of(cue).samples

            // A tone that starts or stops mid-cycle is heard as a click, which
            // is the one sound a Cue must not make: it says something went
            // wrong rather than something began.
            #expect(abs(samples.first!) < 0.01)
            #expect(abs(samples.last!) < 0.01)
        }
    }

    @Test("No Cue is louder than a sound can be")
    func noCueIsLouderThanASoundCanBe() {
        for cue in Cue.allCases {
            #expect(CueTone.of(cue).samples.allSatisfy { abs($0) <= 1 })
        }
    }

    @Test("A Cue is a sound a player will take")
    func aCueIsASoundAPlayerWillTake() {
        let tone = CueTone.of(.dictationStarted)
        let wav = tone.wav

        // Sixteen-bit mono, described in the header exactly as it is laid out
        // after it. A player handed a WAV whose sizes disagree with its
        // contents plays silence, and a Cue nobody hears is a Cue that is not
        // there.
        #expect(wav.tag(at: 0) == "RIFF")
        #expect(wav.tag(at: 8) == "WAVE")
        #expect(wav.tag(at: 12) == "fmt ")
        #expect(wav.tag(at: 36) == "data")

        #expect(wav.number(at: 16, bytes: 4) == 16)
        #expect(wav.number(at: 20, bytes: 2) == 1)
        #expect(wav.number(at: 22, bytes: 2) == 1)
        #expect(wav.number(at: 24, bytes: 4) == Int(CueTone.sampleRate))
        #expect(wav.number(at: 28, bytes: 4) == Int(CueTone.sampleRate) * 2)
        #expect(wav.number(at: 32, bytes: 2) == 2)
        #expect(wav.number(at: 34, bytes: 2) == 16)

        #expect(wav.number(at: 40, bytes: 4) == tone.samples.count * 2)
        #expect(wav.count == 44 + tone.samples.count * 2)
        #expect(wav.number(at: 4, bytes: 4) == wav.count - 8)
    }
}

extension Data {
    /// The four-character chunk name at this offset, as a WAV writes it.
    fileprivate func tag(at offset: Int) -> String {
        String(decoding: self[offset..<offset + 4], as: UTF8.self)
    }

    /// The little-endian number at this offset, as a WAV writes it.
    fileprivate func number(at offset: Int, bytes: Int) -> Int {
        self[offset..<offset + bytes].reversed().reduce(0) { $0 << 8 | Int($1) }
    }
}
