import Testing

@testable import CheppuCore

// The machine is the whole of Cheppu's decision-making and none of its doing.
// These tests state a scripted sequence of events and read back the ordered
// effects, which is exactly what the core hands its ports.
@Suite("Dictation machine")
struct DictationMachineTests {
    private let transcript = RawTranscript(
        text: "hello there",
        words: [
            WordTiming(word: "hello", start: .milliseconds(0), end: .milliseconds(400)),
            WordTiming(word: "there", start: .milliseconds(520), end: .milliseconds(900)),
        ]
    )

    @Test("A Toggle Activation carries a Dictation from Idle back to Idle")
    func aToggleActivationCarriesADictationFromIdleBackToIdle() {
        var machine = DictationMachine()

        let effects =
            machine.receive(.activationStarted)
            + machine.receive(.activationStopped)
            + machine.receive(.rawTranscriptReceived(transcript))
            + machine.receive(.insertionSucceeded)

        #expect(
            effects == [
                .startCapturing,
                .playCue(.dictationStarted),
                .showPill(.listening),
                .playCue(.dictationStopped),
                .showPill(.transcribing),
                .stopCapturingAndTranscribe,
                .recordInHistory(FinalText("hello there")),
                .insert(FinalText("hello there")),
                .hidePill,
            ]
        )
    }

    @Test("Capture starts before the Cue plays, so no speech is lost to the greeting")
    func captureStartsBeforeTheCuePlays() {
        var machine = DictationMachine()

        #expect(machine.receive(.activationStarted).first == .startCapturing)
    }

    @Test("Stopping says it is transcribing before it transcribes, so the pause never reads as a hang")
    func stoppingSaysItIsTranscribingBeforeItTranscribes() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        let effects = machine.receive(.activationStopped)

        #expect(effects.firstIndex(of: .showPill(.transcribing))! < effects.firstIndex(of: .stopCapturingAndTranscribe)!)
    }

    @Test("History is written before Insertion is attempted")
    func historyIsWrittenBeforeInsertionIsAttempted() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)

        let effects = machine.receive(.rawTranscriptReceived(transcript))

        #expect(effects.firstIndex(of: .recordInHistory(FinalText("hello there")))! < effects.firstIndex(of: .insert(FinalText("hello there")))!)
    }

    @Test("The Pill stays until the Final Text has landed")
    func thePillStaysUntilTheFinalTextHasLanded() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)

        #expect(!machine.receive(.rawTranscriptReceived(transcript)).contains(.hidePill))
        #expect(machine.receive(.insertionSucceeded) == [.hidePill])
    }

    @Test("A second Activation start while Listening changes nothing")
    func aSecondActivationStartWhileListeningChangesNothing() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        #expect(machine.receive(.activationStarted).isEmpty)
        #expect(machine.receive(.activationStopped) == [
            .playCue(.dictationStopped),
            .showPill(.transcribing),
            .stopCapturingAndTranscribe,
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

        #expect(machine.receive(.rawTranscriptReceived(transcript)).isEmpty)

        _ = machine.receive(.activationStarted)
        #expect(machine.receive(.rawTranscriptReceived(transcript)).isEmpty)
    }

    @Test("A successful Insertion arriving out of turn changes nothing")
    func aSuccessfulInsertionArrivingOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.insertionSucceeded).isEmpty)
    }

    @Test("A second Toggle Activation runs the same course as the first")
    func aSecondToggleActivationRunsTheSameCourseAsTheFirst() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.rawTranscriptReceived(transcript))
        _ = machine.receive(.insertionSucceeded)

        #expect(machine.receive(.activationStarted) == [
            .startCapturing,
            .playCue(.dictationStarted),
            .showPill(.listening),
        ])
    }
}
