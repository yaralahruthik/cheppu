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
    private static let sampleRate: Double = 48_000

    /// One buffer through the meter, from a meter that has heard nothing.
    private static func reading(of samples: [Float]) -> Double {
        var meter = InputLevelMeter()
        return meter.hearing(samples, at: sampleRate).value
    }

    @Test("Silence reads as silence")
    func silenceReadsAsSilence() {
        #expect(Self.reading(of: buffer(at: 0)) == 0)
    }

    @Test("A sound as loud as the microphone can hear fills the Pill")
    func aSoundAsLoudAsTheMicrophoneCanHearFillsThePill() {
        #expect(Self.reading(of: buffer(at: 1)) == 1)
    }

    @Test("Ordinary speech reads well up the Pill, where a raw loudness would barely move it")
    func ordinarySpeechReadsWellUpThePill() {
        // Speech at a comfortable distance from a laptop microphone sits around
        // -26 dBFS. Drawn as a raw amplitude that is a Pill 5% full, which is
        // indistinguishable from a Pill that is hearing nothing — which is the
        // one thing it exists to tell the user apart.
        let speech = Self.reading(of: buffer(at: 0.05))

        #expect(speech > 0.5)
        #expect(speech < 1)
    }

    @Test("Louder reads higher")
    func louderReadsHigher() {
        #expect(Self.reading(of: buffer(at: 0.5)) > Self.reading(of: buffer(at: 0.05)))
        #expect(Self.reading(of: buffer(at: 0.05)) > Self.reading(of: buffer(at: 0.005)))
    }

    @Test("A room quieter than anything worth showing reads as silence")
    func aRoomQuieterThanAnythingWorthShowingReadsAsSilence() {
        // Below the floor there is nothing the user could act on, and a Pill
        // that twitches at room tone says it is hearing them when it is not.
        #expect(Self.reading(of: buffer(at: 0.0001)) == 0)
    }

    @Test("The reading rises the moment the speaker does")
    func theReadingRisesTheMomentTheSpeakerDoes() {
        var meter = InputLevelMeter()
        _ = meter.hearing(buffer(at: 0), at: Self.sampleRate)

        // No lag on the way up: the Pill has to answer "can it hear me right
        // now?" on the first syllable, not a moment after it.
        #expect(meter.hearing(buffer(at: 1), at: Self.sampleRate) == InputLevel(1))
    }

    @Test("The reading falls rather than dropping out between syllables")
    func theReadingFallsRatherThanDroppingOutBetweenSyllables() {
        var meter = InputLevelMeter()
        _ = meter.hearing(buffer(at: 1), at: Self.sampleRate)

        // 4096 frames at 48 kHz is 85 ms — a gap between words, not the end of
        // a sentence. A meter that went straight to zero here would strobe.
        let betweenWords = meter.hearing(buffer(at: 0), at: Self.sampleRate).value

        #expect(betweenWords > 0.3)
        #expect(betweenWords < 1)
    }

    @Test("A pause long enough to be a pause reads as silence again")
    func aPauseLongEnoughToBeAPauseReadsAsSilenceAgain() {
        var meter = InputLevelMeter()
        _ = meter.hearing(buffer(at: 1), at: Self.sampleRate)

        // A little over a second of nothing.
        var level = InputLevel(1)
        for _ in 0..<14 {
            level = meter.hearing(buffer(at: 0), at: Self.sampleRate)
        }

        #expect(level.value < 0.01)
    }

    @Test("How fast the reading falls does not depend on how big the buffers are")
    func howFastTheReadingFallsDoesNotDependOnHowBigTheBuffersAre() {
        // The device chooses the buffer size, not Cheppu. If the decay were per
        // buffer rather than per second, the Pill would behave differently on
        // different hardware for no reason the user could see.
        var inOneBuffer = InputLevelMeter()
        _ = inOneBuffer.hearing(buffer(at: 1), at: Self.sampleRate)
        let afterOneLongSilence = inOneBuffer.hearing(
            buffer(at: 0, frames: 4_096), at: Self.sampleRate)

        var inFourBuffers = InputLevelMeter()
        _ = inFourBuffers.hearing(buffer(at: 1), at: Self.sampleRate)
        var afterFourShortSilences = InputLevel(1)
        for _ in 0..<4 {
            afterFourShortSilences = inFourBuffers.hearing(
                buffer(at: 0, frames: 1_024), at: Self.sampleRate)
        }

        #expect(abs(afterOneLongSilence.value - afterFourShortSilences.value) < 0.001)
    }

    @Test("The reading follows the shape of speech: up on a word, held through the gap, down at the end")
    func theReadingFollowsTheShapeOfSpeech() {
        var meter = InputLevelMeter()

        // A word, the 40 ms a speaker leaves between two of them, a louder
        // word, and then someone who has stopped talking.
        let word = meter.hearing(buffer(at: 0.2), at: Self.sampleRate).value
        let betweenWords = meter.hearing(buffer(at: 0.0001, frames: 2_048), at: Self.sampleRate).value
        let louderWord = meter.hearing(buffer(at: 0.3), at: Self.sampleRate).value
        var afterSpeaking = louderWord
        for _ in 0..<14 {
            afterSpeaking = meter.hearing(buffer(at: 0.0001), at: Self.sampleRate).value
        }

        #expect(word > 0.5)
        #expect(betweenWords > word * 0.6)
        #expect(louderWord > word)
        #expect(afterSpeaking < 0.01)
    }

    @Test("A device that hands over more than full scale does not leave the Pill pinned")
    func aDeviceThatHandsOverMoreThanFullScaleDoesNotLeaveThePillPinned() {
        var atFullScale = InputLevelMeter()
        _ = atFullScale.hearing(buffer(at: 1), at: Self.sampleRate)

        var pastFullScale = InputLevelMeter()
        _ = pastFullScale.hearing(buffer(at: 4), at: Self.sampleRate)

        // Both were as loud as the Pill can draw. Neither may then take longer
        // to empty than the other for being louder than the Pill can show.
        #expect(
            atFullScale.hearing(buffer(at: 0), at: Self.sampleRate)
                == pastFullScale.hearing(buffer(at: 0), at: Self.sampleRate))
    }

    @Test("A buffer with nothing in it leaves the reading where it was")
    func aBufferWithNothingInItLeavesTheReadingWhereItWas() {
        var meter = InputLevelMeter()
        let loud = meter.hearing(buffer(at: 1), at: Self.sampleRate)

        #expect(meter.hearing([], at: Self.sampleRate) == loud)
    }
}
