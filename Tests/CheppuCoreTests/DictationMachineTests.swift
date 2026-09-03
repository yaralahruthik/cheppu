import Testing

@testable import CheppuCore

extension [DictationEffect] {
    /// Whether one effect was decided on before another. False when either is
    /// missing, so an assertion built on it fails rather than passes vacuously.
    func decides(_ first: DictationEffect, before second: DictationEffect) -> Bool {
        guard let earlier = firstIndex(of: first), let later = firstIndex(of: second) else {
            return false
        }
        return earlier < later
    }
}

// The machine is the whole of Cheppu's decision-making and none of its doing.
// These tests state a scripted sequence of events and read back the ordered
// effects, which is exactly what the core hands its ports.
@Suite("Dictation machine")
struct DictationMachineTests {
    private let spokenAudio = CapturedAudio(samples: [0.1, -0.2, 0.3], sampleRate: 16_000)

    private let heardWords = RawTranscript(
        text: "hello there",
        words: [
            WordTiming(word: "hello", start: .milliseconds(0), end: .milliseconds(400)),
            WordTiming(word: "there", start: .milliseconds(520), end: .milliseconds(900)),
        ]
    )

    /// Everything a Toggle Activation decides, from the first tap to the words
    /// landing.
    private func aWholeDictation(_ machine: inout DictationMachine) -> [DictationEffect] {
        machine.receive(.activationStarted)
            + machine.receive(.activationStopped)
            + machine.receive(.audioCaptured(spokenAudio))
            + machine.receive(.rawTranscriptReceived(heardWords))
            + machine.receive(.insertionSucceeded)
    }

    @Test("A Toggle Activation carries a Dictation from Idle back to Idle")
    func aToggleActivationCarriesADictationFromIdleBackToIdle() {
        var machine = DictationMachine()

        #expect(
            aWholeDictation(&machine) == [
                .startCapturing,
                .playCue(.dictationStarted),
                .showPill(.listening(.silent)),
                .stopCapturing,
                .playCue(.dictationStopped),
                .showPill(.transcribing),
                .transcribe(spokenAudio),
                .recordInHistory(FinalText("hello there")),
                .insert(FinalText("hello there")),
                .hidePill,
            ]
        )
    }

    @Test("Capture opens before the start Cue plays, so no speech is lost to the greeting")
    func captureOpensBeforeTheStartCuePlays() {
        var machine = DictationMachine()

        let effects = machine.receive(.activationStarted)

        #expect(effects.decides(.startCapturing, before: .playCue(.dictationStarted)))
    }

    @Test("The microphone closes before the stop Cue plays, so the Cue is not in what is transcribed")
    func theMicrophoneClosesBeforeTheStopCuePlays() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        let effects = machine.receive(.activationStopped)

        #expect(effects.decides(.stopCapturing, before: .playCue(.dictationStopped)))
    }

    @Test("It says it is transcribing before it transcribes, so the pause never reads as a hang")
    func itSaysItIsTranscribingBeforeItTranscribes() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        let effects = machine.receive(.activationStopped) + machine.receive(.audioCaptured(spokenAudio))

        #expect(effects.decides(.showPill(.transcribing), before: .transcribe(spokenAudio)))
    }

    @Test("History is written before Insertion is attempted")
    func historyIsWrittenBeforeInsertionIsAttempted() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.audioCaptured(spokenAudio))

        let effects = machine.receive(.rawTranscriptReceived(heardWords))

        #expect(
            effects.decides(
                .recordInHistory(FinalText("hello there")),
                before: .insert(FinalText("hello there"))
            )
        )
    }

    @Test("The Pill stays until the Final Text has landed")
    func thePillStaysUntilTheFinalTextHasLanded() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.audioCaptured(spokenAudio))

        #expect(!machine.receive(.rawTranscriptReceived(heardWords)).contains(.hidePill))
        #expect(machine.receive(.insertionSucceeded) == [.hidePill])
    }

    @Test("A Dictation that fails takes the Pill down and leaves Cheppu ready for the next one")
    func aDictationThatFailsLeavesCheppuReadyForTheNextOne() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)

        #expect(machine.receive(.dictationFailed) == [.hidePill])
        #expect(machine.receive(.activationStarted) == [
            .startCapturing,
            .playCue(.dictationStarted),
            .showPill(.listening(.silent)),
        ])
    }

    @Test("A second Activation start while Listening changes nothing")
    func aSecondActivationStartWhileListeningChangesNothing() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        #expect(machine.receive(.activationStarted).isEmpty)
        #expect(machine.receive(.activationStopped) == [
            .stopCapturing,
            .playCue(.dictationStopped),
            .showPill(.transcribing),
        ])
    }

    @Test("An Activation stop with no Dictation running changes nothing")
    func anActivationStopWithNoDictationRunningChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.activationStopped).isEmpty)
    }

    @Test("A Raw Transcript arriving out of turn changes nothing")
    func aRawTranscriptArrivingOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.rawTranscriptReceived(heardWords)).isEmpty)

        _ = machine.receive(.activationStarted)
        #expect(machine.receive(.rawTranscriptReceived(heardWords)).isEmpty)
    }

    @Test("A successful Insertion arriving out of turn changes nothing")
    func aSuccessfulInsertionArrivingOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.insertionSucceeded).isEmpty)
    }

    @Test("The Pill opens at silence, so it never claims to hear something before it has")
    func thePillOpensAtSilence() {
        var machine = DictationMachine()

        #expect(machine.receive(.activationStarted).contains(.showPill(.listening(.silent))))
    }

    @Test("While Listening, what the microphone is hearing is what the Pill shows")
    func whileListeningWhatTheMicrophoneIsHearingIsWhatThePillShows() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        #expect(machine.receive(.inputLevelChanged(InputLevel(0.6))) == [.showPill(.listening(InputLevel(0.6)))])
        #expect(machine.receive(.inputLevelChanged(InputLevel(0.1))) == [.showPill(.listening(InputLevel(0.1)))])
    }

    @Test("An input level arriving once the Dictation has stopped Listening changes nothing")
    func anInputLevelArrivingOnceTheDictationHasStoppedListeningChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.inputLevelChanged(InputLevel(0.6))).isEmpty)

        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        // The last buffer the microphone heard can land after it was closed. It
        // must not put a Listening Pill back over a Dictation that is already
        // transcribing.
        #expect(machine.receive(.inputLevelChanged(InputLevel(0.6))).isEmpty)
    }

    @Test("A second Toggle Activation runs the same course as the first")
    func aSecondToggleActivationRunsTheSameCourseAsTheFirst() {
        var machine = DictationMachine()
        let first = aWholeDictation(&machine)

        #expect(aWholeDictation(&machine) == first)
    }
}
