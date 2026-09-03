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

    private let mail = ATargetApp.mail
    private let browser = ATargetApp.browser

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
        machine.receive(.activationToggled)
            + machine.receive(.activationToggled)
            + machine.receive(.targetAppNoted(mail))
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
                .noteTargetApp,
                .stopCapturing,
                .playCue(.dictationStopped),
                .showPill(.transcribing),
                .transcribe(spokenAudio),
                .recordInHistory(FinalText("hello there")),
                .insert(FinalText("hello there"), into: mail),
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
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        let effects = machine.receive(.rawTranscriptReceived(heardWords))

        #expect(
            effects.decides(
                .recordInHistory(FinalText("hello there")),
                before: .insert(FinalText("hello there"), into: mail)
            )
        )
    }

    @Test("The Pill stays until the Final Text has landed")
    func thePillStaysUntilTheFinalTextHasLanded() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.targetAppNoted(mail))
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

    @Test("A tap of the Hotkey starts a Dictation, and the next tap stops it")
    func aTapStartsADictationAndTheNextTapStopsIt() {
        var machine = DictationMachine()

        #expect(machine.receive(.activationToggled) == [
            .startCapturing,
            .playCue(.dictationStarted),
            .showPill(.listening(.silent)),
        ])
        #expect(machine.receive(.activationToggled) == [
            .noteTargetApp,
            .stopCapturing,
            .playCue(.dictationStopped),
            .showPill(.transcribing),
        ])
    }

    @Test("A tap while it is transcribing changes nothing")
    func aTapWhileItIsTranscribingChangesNothing() {
        var machine = DictationMachine()
        _ = machine.receive(.activationToggled)
        _ = machine.receive(.activationToggled)

        // The Dictation is with the Engine. A tap here is an impatient user, not
        // a third state, and starting a second Dictation over the top of one
        // being transcribed would lose the first.
        #expect(machine.receive(.activationToggled).isEmpty)
    }

    @Test("A tap after a Dictation ended without the Hotkey starts the next one")
    func aTapAfterADictationEndedWithoutTheHotkeyStartsTheNextOne() {
        var machine = DictationMachine()
        _ = machine.receive(.activationToggled)

        // Something other than the Hotkey ended that Dictation — here a
        // failure, later the Cap or a Cancel. Whether the next tap starts or
        // stops is the machine's to answer for exactly this reason: anything
        // else keeping its own copy of "is a Dictation running" would now be
        // wrong, and the user's next tap would do the opposite of what they
        // meant.
        _ = machine.receive(.dictationFailed)

        #expect(machine.receive(.activationToggled) == [
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
            .noteTargetApp,
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

    @Test("A Dictation notes its Target App the moment it stops, before it does anything else")
    func aDictationNotesItsTargetAppTheMomentItStops() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)

        // The Target App is whoever has focus at that instant, so it is read
        // before the microphone is closed and the Cue is played — both of which
        // take long enough for the user to have clicked somewhere else.
        #expect(machine.receive(.activationStopped).first == .noteTargetApp)
    }

    @Test("The Final Text goes to the app that was focused when the Dictation stopped")
    func theFinalTextGoesToTheAppThatWasFocusedWhenTheDictationStopped() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.targetAppNoted(browser))
        _ = machine.receive(.audioCaptured(spokenAudio))

        #expect(
            machine.receive(.rawTranscriptReceived(heardWords))
                .contains(.insert(FinalText("hello there"), into: browser)))
    }

    @Test("The Target App one Dictation noted is never the next one's")
    func theTargetAppOneDictationNotedIsNeverTheNextOnes() {
        var machine = DictationMachine()
        _ = aWholeDictation(&machine)

        _ = machine.receive(.activationToggled)
        _ = machine.receive(.activationToggled)
        _ = machine.receive(.targetAppNoted(browser))
        _ = machine.receive(.audioCaptured(spokenAudio))

        #expect(
            machine.receive(.rawTranscriptReceived(heardWords)) == [
                .recordInHistory(FinalText("hello there")),
                .insert(FinalText("hello there"), into: browser),
            ])
    }

    @Test("A Dictation with no app to insert into keeps the words and ends")
    func aDictationWithNoAppToInsertIntoKeepsTheWordsAndEnds() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.targetAppNoted(nil))
        _ = machine.receive(.audioCaptured(spokenAudio))

        // Nothing had focus, so there is nowhere for the words to be typed.
        // They are still the user's: History is written all the same, and the
        // Dictation ends rather than waiting for an Insertion that cannot come.
        // Telling the user, and leaving the text on the clipboard, is #14's.
        #expect(
            machine.receive(.rawTranscriptReceived(heardWords)) == [
                .recordInHistory(FinalText("hello there")),
                .hidePill,
            ])
        #expect(machine.receive(.activationToggled) == [
            .startCapturing,
            .playCue(.dictationStarted),
            .showPill(.listening(.silent)),
        ])
    }

    @Test("Final Text never carries the whitespace the Engine left around it")
    func finalTextNeverCarriesTheWhitespaceTheEngineLeftAroundIt() {
        var machine = DictationMachine()
        _ = machine.receive(.activationStarted)
        _ = machine.receive(.activationStopped)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        let spacedOut = RawTranscript(text: "  hello there\n", words: heardWords.words)

        // Inserted into the middle of a sentence, the Engine's own leading
        // space would double the one already in front of the cursor. History
        // keeps what was said, whitespace and all, so that Cleanup can go on
        // promising that with every rule off the Final Text is the Raw
        // Transcript byte for byte (#11).
        #expect(
            machine.receive(.rawTranscriptReceived(spacedOut)) == [
                .recordInHistory(FinalText("  hello there\n")),
                .insert(FinalText("hello there"), into: mail),
            ])
    }

    @Test("A Target App noted out of turn changes nothing")
    func aTargetAppNotedOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.targetAppNoted(mail)).isEmpty)

        _ = machine.receive(.activationStarted)
        #expect(machine.receive(.targetAppNoted(mail)).isEmpty)
    }
}
