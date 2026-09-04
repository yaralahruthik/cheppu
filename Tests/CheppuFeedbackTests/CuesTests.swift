import CheppuCore
import Testing

@testable import CheppuFeedback

// Whether a Cue is heard at all. What each one sounds like is `CueToneTests`;
// this is the switch in front of them, and the claim it makes is that off means
// silent — someone who turned the Cues off did it because they are in a room
// with other people in it.
@Suite("Cues")
struct CuesTests {
    private static let aWholeDictation: [Cue] = [.dictationStarted, .dictationStopped]

    private struct Scenario {
        let speaker = FakeSpeaker()
        let cueSwitch: FakeCueSwitch
        let cues: Cues

        init(cuesAreOn: Bool) {
            let speaker = self.speaker
            let cueSwitch = FakeCueSwitch(on: cuesAreOn)
            self.cueSwitch = cueSwitch
            self.cues = Cues(through: speaker, when: cueSwitch)
        }

        func run(_ cues: [Cue]) async {
            for cue in cues { await self.cues.play(cue) }
        }
    }

    @Test("With the Cues on, a Dictation is heard as well as seen")
    func withTheCuesOnADictationIsHeardAsWellAsSeen() async {
        let scenario = Scenario(cuesAreOn: true)

        await scenario.run(Self.aWholeDictation)

        #expect(await scenario.speaker.heard == Self.aWholeDictation)
    }

    @Test("Off means silent")
    func offMeansSilent() async {
        let scenario = Scenario(cuesAreOn: false)

        await scenario.run(Cue.allCases)

        // Not one of them, not quieter, and not a different sound: nothing at
        // all. Someone
        // dictating in a meeting has turned the Cues off because the room can
        // hear them, and a Cue that still played would be the whole reason they
        // turned it off.
        #expect(await scenario.speaker.heard.isEmpty)
    }

    @Test("The switch is read each time, so turning the Cues off silences the Dictation under way")
    func theSwitchIsReadEachTime() async throws {
        let scenario = Scenario(cuesAreOn: true)

        await scenario.cues.play(.dictationStarted)
        await scenario.cueSwitch.turn(on: false)
        await scenario.cues.play(.dictationStopped)

        // A switch read once at launch would leave the user with a Cheppu that
        // goes on making a sound until they quit it.
        #expect(await scenario.speaker.heard == [.dictationStarted])
    }
}

// One test about the machine rather than about Cheppu: that what `CueTone`
// writes is something a Mac will play. Nothing here is heard — a sound is built
// and asked how long it is, and never started.
@Suite("The Mac's speakers")
struct SystemSpeakerTests {
    @Test("The Mac makes a sound out of every Cue")
    @MainActor
    func theMacMakesASoundOutOfEveryCue() {
        let speaker = SystemSpeaker()

        for cue in Cue.allCases {
            let sound = speaker.sounds[cue]

            // A `NSSound` that could not be built out of the bytes is nil, and
            // a Cue nobody hears is a Cue that is not there.
            #expect(sound != nil)
            #expect(sound?.duration == Double(CueTone.of(cue).samples.count) / CueTone.sampleRate)
        }
    }
}
