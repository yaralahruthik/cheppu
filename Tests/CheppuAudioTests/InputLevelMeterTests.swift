import CheppuCore
import Foundation
import Testing

@testable import CheppuAudio

// The meter is the only part of the microphone that decides anything, so it is
// the part with tests. Every one of these is a claim about what the user sees
// on the Pill: silence looks like silence, speech looks like speech, and the
// reading does not flicker between syllables.
@Suite("Input level meter")
struct InputLevelMeterTests {
    /// A buffer of a constant amplitude, which is the loudness the meter reads.
    private static func buffer(at amplitude: Float, frames: Int = 4_096) -> [Float] {
        (0..<frames).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
    }

    private static let sampleRate: Double = 48_000

    /// One buffer through the meter, from a meter that has heard nothing.
    private static func reading(of samples: [Float]) -> Double {
        var meter = InputLevelMeter()
        return meter.hearing(samples, at: sampleRate).value
    }

    @Test("Silence reads as silence")
    func silenceReadsAsSilence() {
        #expect(Self.reading(of: Self.buffer(at: 0)) == 0)
    }

    @Test("A sound as loud as the microphone can hear fills the Pill")
    func aSoundAsLoudAsTheMicrophoneCanHearFillsThePill() {
        #expect(Self.reading(of: Self.buffer(at: 1)) == 1)
    }

    @Test("Ordinary speech reads well up the Pill, where a raw loudness would barely move it")
    func ordinarySpeechReadsWellUpThePill() {
        // Speech at a comfortable distance from a laptop microphone sits around
        // -26 dBFS. Drawn as a raw amplitude that is a Pill 5% full, which is
        // indistinguishable from a Pill that is hearing nothing — which is the
        // one thing it exists to tell the user apart.
        let speech = Self.reading(of: Self.buffer(at: 0.05))

        #expect(speech > 0.5)
        #expect(speech < 1)
    }

    @Test("Louder reads higher")
    func louderReadsHigher() {
        #expect(Self.reading(of: Self.buffer(at: 0.5)) > Self.reading(of: Self.buffer(at: 0.05)))
        #expect(Self.reading(of: Self.buffer(at: 0.05)) > Self.reading(of: Self.buffer(at: 0.005)))
    }

    @Test("A room quieter than anything worth showing reads as silence")
    func aRoomQuieterThanAnythingWorthShowingReadsAsSilence() {
        // Below the floor there is nothing the user could act on, and a Pill
        // that twitches at room tone says it is hearing them when it is not.
        #expect(Self.reading(of: Self.buffer(at: 0.0001)) == 0)
    }

    @Test("The reading rises the moment the speaker does")
    func theReadingRisesTheMomentTheSpeakerDoes() {
        var meter = InputLevelMeter()
        _ = meter.hearing(Self.buffer(at: 0), at: Self.sampleRate)

        // No lag on the way up: the Pill has to answer "can it hear me right
        // now?" on the first syllable, not a moment after it.
        #expect(meter.hearing(Self.buffer(at: 1), at: Self.sampleRate) == InputLevel(1))
    }

    @Test("The reading falls rather than dropping out between syllables")
    func theReadingFallsRatherThanDroppingOutBetweenSyllables() {
        var meter = InputLevelMeter()
        _ = meter.hearing(Self.buffer(at: 1), at: Self.sampleRate)

        // 4096 frames at 48 kHz is 85 ms — a gap between words, not the end of
        // a sentence. A meter that went straight to zero here would strobe.
        let betweenWords = meter.hearing(Self.buffer(at: 0), at: Self.sampleRate).value

        #expect(betweenWords > 0.3)
        #expect(betweenWords < 1)
    }

    @Test("A pause long enough to be a pause reads as silence again")
    func aPauseLongEnoughToBeAPauseReadsAsSilenceAgain() {
        var meter = InputLevelMeter()
        _ = meter.hearing(Self.buffer(at: 1), at: Self.sampleRate)

        // A little over a second of nothing.
        var level = InputLevel(1)
        for _ in 0..<14 {
            level = meter.hearing(Self.buffer(at: 0), at: Self.sampleRate)
        }

        #expect(level.value < 0.01)
    }

    @Test("How fast the reading falls does not depend on how big the buffers are")
    func howFastTheReadingFallsDoesNotDependOnHowBigTheBuffersAre() {
        // The device chooses the buffer size, not Cheppu. If the decay were per
        // buffer rather than per second, the Pill would behave differently on
        // different hardware for no reason the user could see.
        var inOneBuffer = InputLevelMeter()
        _ = inOneBuffer.hearing(Self.buffer(at: 1), at: Self.sampleRate)
        let afterOneLongSilence = inOneBuffer.hearing(
            Self.buffer(at: 0, frames: 4_096), at: Self.sampleRate)

        var inFourBuffers = InputLevelMeter()
        _ = inFourBuffers.hearing(Self.buffer(at: 1), at: Self.sampleRate)
        var afterFourShortSilences = InputLevel(1)
        for _ in 0..<4 {
            afterFourShortSilences = inFourBuffers.hearing(
                Self.buffer(at: 0, frames: 1_024), at: Self.sampleRate)
        }

        #expect(abs(afterOneLongSilence.value - afterFourShortSilences.value) < 0.001)
    }

    @Test("A buffer with nothing in it leaves the reading where it was")
    func aBufferWithNothingInItLeavesTheReadingWhereItWas() {
        var meter = InputLevelMeter()
        let loud = meter.hearing(Self.buffer(at: 1), at: Self.sampleRate)

        #expect(meter.hearing([], at: Self.sampleRate) == loud)
    }
}
