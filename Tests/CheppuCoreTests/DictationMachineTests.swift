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

    /// The Hotkey down and up again well inside the threshold: a tap, and so a
    /// Toggle.
    @discardableResult
    private func tap(_ machine: inout DictationMachine) -> [DictationEffect] {
        machine.receive(.hotkeyPressed)
            + machine.receive(.hotkeyReleased(heldFor: .milliseconds(120)))
    }

    /// The Hotkey held down for as long as it takes to say something, and then
    /// let go: a Hold.
    @discardableResult
    private func hold(
        _ machine: inout DictationMachine, for heldFor: Duration = .seconds(2)
    ) -> [DictationEffect] {
        machine.receive(.hotkeyPressed) + machine.receive(.hotkeyReleased(heldFor: heldFor))
    }

    /// What starting a Dictation always decides, whichever Activation started it.
    private let openingADictation: [DictationEffect] = [
        .startCapturing, .playCue(.dictationStarted), .showPill(.listening(.silent)),
    ]

    /// What stopping a Dictation always decides, whichever Activation stopped it.
    private let closingADictation: [DictationEffect] = [
        .noteTargetApp, .stopCapturing, .playCue(.dictationStopped), .showPill(.transcribing),
    ]

    /// Everything a Toggle Activation decides, from the first tap to the words
    /// landing.
    private func aWholeDictation(_ machine: inout DictationMachine) -> [DictationEffect] {
        tap(&machine)
            + tap(&machine)
            + machine.receive(.targetAppNoted(mail))
            + machine.receive(.audioCaptured(spokenAudio))
            + machine.receive(.rawTranscriptReceived(heardWords))
            + machine.receive(.insertionSucceeded)
    }

    // MARK: - Toggle and Hold

    @Test("A tap of the Hotkey starts a Dictation, and the next tap stops it")
    func aTapStartsADictationAndTheNextTapStopsIt() {
        var machine = DictationMachine()

        #expect(tap(&machine) == openingADictation)
        #expect(tap(&machine) == closingADictation)
    }

    @Test("A tap leaves the Dictation running, so a Toggle survives letting go of the key")
    func aTapLeavesTheDictationRunning() {
        var machine = DictationMachine()

        _ = machine.receive(.hotkeyPressed)
        // The key is back up well inside the threshold. Nothing is decided by
        // that: the user tapped, and a Toggle Dictation runs until they tap
        // again.
        #expect(machine.receive(.hotkeyReleased(heldFor: .milliseconds(120))).isEmpty)

        // Still Listening, and still hearing them.
        #expect(
            machine.receive(.inputLevelChanged(InputLevel(0.4)))
                == [.showPill(.listening(InputLevel(0.4)))])
    }

    @Test("Holding the Hotkey past the threshold runs the Dictation only while it is held")
    func holdingTheHotkeyRunsTheDictationOnlyWhileItIsHeld() {
        var machine = DictationMachine()

        #expect(machine.receive(.hotkeyPressed) == openingADictation)
        // Two seconds is long past a tap, so letting go is the end of a Hold
        // rather than the start of a Toggle nobody asked for.
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(2))) == closingADictation)
    }

    @Test("The Dictation starts on the way down, before the threshold has decided anything")
    func theDictationStartsOnTheWayDown() {
        var machine = DictationMachine()

        // Whichever of the two this press turns out to be, the microphone is
        // open from the moment the key goes down: a Hold user starts speaking
        // as they press, and the 250 ms spent telling the gestures apart must
        // not be 250 ms of their voice.
        #expect(machine.receive(.hotkeyPressed) == openingADictation)
    }

    @Test("The threshold is 250 ms, and a press held exactly that long is a Hold")
    func aPressHeldExactlyTheThresholdIsAHold() {
        #expect(DictationMachine.holdThreshold == .milliseconds(250))

        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        #expect(
            machine.receive(.hotkeyReleased(heldFor: DictationMachine.holdThreshold))
                == closingADictation)
    }

    @Test("A press a hair inside the threshold is a tap")
    func aPressAHairInsideTheThresholdIsATap() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        #expect(machine.receive(.hotkeyReleased(heldFor: .milliseconds(249))).isEmpty)
    }

    @Test("Leaning on the Hotkey to end a Toggle ends it, so there is no mode to get stuck in")
    func leaningOnTheHotkeyToEndAToggleEndsIt() {
        var machine = DictationMachine()
        tap(&machine)

        // The user started with a tap and finished with a long press, which is
        // not a gesture anyone was taught. The same key does the obvious thing
        // both ways: the Dictation stops.
        #expect(hold(&machine) == closingADictation)
    }

    @Test("A press while it is transcribing changes nothing")
    func aPressWhileItIsTranscribingChangesNothing() {
        var machine = DictationMachine()
        tap(&machine)
        tap(&machine)

        // The Dictation is with the Engine. A press here is an impatient user,
        // not a third state, and starting a second Dictation over the top of
        // one being transcribed would lose the first.
        #expect(hold(&machine).isEmpty)
    }

    @Test("A tap after a Dictation ended without the Hotkey starts the next one")
    func aTapAfterADictationEndedWithoutTheHotkeyStartsTheNextOne() {
        var machine = DictationMachine()
        tap(&machine)

        // Something other than the Hotkey ended that Dictation — here a
        // failure, later the Cap or a Cancel. Whether the next tap starts or
        // stops is the machine's to answer for exactly this reason: anything
        // else keeping its own copy of "is a Dictation running" would now be
        // wrong, and the user's next tap would do the opposite of what they
        // meant.
        _ = machine.receive(.dictationFailed)

        #expect(tap(&machine) == openingADictation)
    }

    @Test("A release of a press Cheppu never saw begin changes nothing")
    func aReleaseOfAPressCheppuNeverSawBeginChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(2))).isEmpty)

        // And a key that was already down when a Toggle Dictation started does
        // not stop it on the way up: that press began before the Dictation and
        // was never an Activation of it.
        tap(&machine)
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(2))).isEmpty)
        #expect(
            machine.receive(.inputLevelChanged(InputLevel(0.4)))
                == [.showPill(.listening(InputLevel(0.4)))])
        #expect(machine.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40))).isEmpty)
    }

    // MARK: - A press that turns out to be typing

    @Test("A press that turns out to be typing takes back the Dictation it started")
    func aPressThatTurnsOutToBeTypingTakesBackTheDictationItStarted() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        // Right Option types an accented character on several layouts, so a
        // Dictation begun on the way down has to be handed back when the press
        // turns out to have been an é. The microphone closes and the Pill goes,
        // and nothing is transcribed, inserted or kept: the user was typing.
        #expect(
            machine.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40)))
                == [.stopCapturing, .hidePill])

        // Nothing is left running, so the next tap starts a Dictation rather
        // than stopping one.
        #expect(tap(&machine) == openingADictation)
    }

    @Test("A spoiled press never reaches the Engine, whatever the microphone heard")
    func aSpoiledPressNeverReachesTheEngine() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)
        _ = machine.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40)))

        // The audio the microphone had already heard arrives after the
        // Dictation was taken back. It is dropped where it lands.
        #expect(machine.receive(.audioCaptured(spokenAudio)).isEmpty)
    }

    @Test("A tap that stops a Toggle stops it even if the user types before letting go")
    func aTapThatStopsAToggleStopsItEvenIfTheUserTypesBeforeLettingGo() {
        var machine = DictationMachine()
        tap(&machine)

        // The user finishes dictating, taps to stop, and their hand lands on
        // the keyboard before the key is back up. The Dictation is already
        // stopping: a press of the Hotkey while one is running means stop, and
        // it means it where the press begins rather than where it ends.
        //
        // Deciding it on the way up instead would lose the stop entirely — a
        // press spoiled by typing is never released — and the Dictation would
        // go on listening to everything typed after it.
        #expect(machine.receive(.hotkeyPressed) == closingADictation)
        #expect(machine.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40))).isEmpty)
        #expect(machine.receive(.hotkeyReleased(heldFor: .milliseconds(80))).isEmpty)
    }

    @Test("A key brushed during a Hold ends the Dictation rather than throwing away what was said")
    func aKeyBrushedDuringAHoldEndsTheDictationRatherThanThrowingItAway() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        // Three seconds in, the press is a Hold and the user has been speaking
        // into it. A stray key is not an é, and audio is effort they cannot
        // repeat — so what they said is transcribed and kept.
        //
        // It ends here rather than on the way up because a spoiled press is
        // never reported released: a Dictation left running would be one
        // nothing could end.
        #expect(machine.receive(.hotkeyPressSpoiled(heldFor: .seconds(3))) == closingADictation)
    }

    @Test("A spoiled press with no Dictation running changes nothing")
    func aSpoiledPressWithNoDictationRunningChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40))).isEmpty)
    }

    // MARK: - The shape of a Dictation

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

    @Test("A Hold Activation carries a Dictation from Idle back to Idle")
    func aHoldActivationCarriesADictationFromIdleBackToIdle() {
        var machine = DictationMachine()

        let effects =
            hold(&machine)
            + machine.receive(.targetAppNoted(mail))
            + machine.receive(.audioCaptured(spokenAudio))
            + machine.receive(.rawTranscriptReceived(heardWords))
            + machine.receive(.insertionSucceeded)

        // The same Dictation, decided the same way. Which gesture started it is
        // the user's business and nothing else's.
        var toggled = DictationMachine()
        #expect(effects == aWholeDictation(&toggled))
    }

    @Test("Capture opens before the start Cue plays, so no speech is lost to the greeting")
    func captureOpensBeforeTheStartCuePlays() {
        var machine = DictationMachine()

        let effects = machine.receive(.hotkeyPressed)

        #expect(effects.decides(.startCapturing, before: .playCue(.dictationStarted)))
    }

    @Test("The microphone closes before the stop Cue plays, so the Cue is not in what is transcribed")
    func theMicrophoneClosesBeforeTheStopCuePlays() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        let effects = machine.receive(.hotkeyReleased(heldFor: .seconds(2)))

        #expect(effects.decides(.stopCapturing, before: .playCue(.dictationStopped)))
    }

    @Test("It says it is transcribing before it transcribes, so the pause never reads as a hang")
    func itSaysItIsTranscribingBeforeItTranscribes() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        let effects =
            machine.receive(.hotkeyReleased(heldFor: .seconds(2)))
            + machine.receive(.audioCaptured(spokenAudio))

        #expect(effects.decides(.showPill(.transcribing), before: .transcribe(spokenAudio)))
    }

    @Test("History is written before Insertion is attempted")
    func historyIsWrittenBeforeInsertionIsAttempted() {
        var machine = DictationMachine()
        hold(&machine)
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
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        #expect(!machine.receive(.rawTranscriptReceived(heardWords)).contains(.hidePill))
        #expect(machine.receive(.insertionSucceeded) == [.hidePill])
    }

    @Test("A Dictation that fails takes the Pill down and leaves Cheppu ready for the next one")
    func aDictationThatFailsLeavesCheppuReadyForTheNextOne() {
        var machine = DictationMachine()
        hold(&machine)

        #expect(machine.receive(.dictationFailed) == [.hidePill])
        #expect(machine.receive(.hotkeyPressed) == openingADictation)
    }

    @Test("A press of the Hotkey while a Dictation is running stops it on the way down")
    func aPressWhileADictationIsRunningStopsItOnTheWayDown() {
        var machine = DictationMachine()
        tap(&machine)

        // The user has finished speaking, so everything between the press and
        // the words appearing is spent from the latency budget. There is
        // nothing left to wait for the key to come up for.
        #expect(machine.receive(.hotkeyPressed) == closingADictation)
        #expect(machine.receive(.hotkeyReleased(heldFor: .milliseconds(80))).isEmpty)
    }

    @Test("A Raw Transcript arriving out of turn changes nothing")
    func aRawTranscriptArrivingOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.rawTranscriptReceived(heardWords)).isEmpty)

        _ = machine.receive(.hotkeyPressed)
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

        #expect(machine.receive(.hotkeyPressed).contains(.showPill(.listening(.silent))))
    }

    @Test("While Listening, what the microphone is hearing is what the Pill shows")
    func whileListeningWhatTheMicrophoneIsHearingIsWhatThePillShows() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        #expect(machine.receive(.inputLevelChanged(InputLevel(0.6))) == [.showPill(.listening(InputLevel(0.6)))])
        #expect(machine.receive(.inputLevelChanged(InputLevel(0.1))) == [.showPill(.listening(InputLevel(0.1)))])
    }

    @Test("An input level arriving once the Dictation has stopped Listening changes nothing")
    func anInputLevelArrivingOnceTheDictationHasStoppedListeningChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.inputLevelChanged(InputLevel(0.6))).isEmpty)

        hold(&machine)
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
        _ = machine.receive(.hotkeyPressed)

        // The Target App is whoever has focus at that instant, so it is read
        // before the microphone is closed and the Cue is played — both of which
        // take long enough for the user to have clicked somewhere else.
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(2))).first == .noteTargetApp)
    }

    @Test("The Final Text goes to the app that was focused when the Dictation stopped")
    func theFinalTextGoesToTheAppThatWasFocusedWhenTheDictationStopped() {
        var machine = DictationMachine()
        hold(&machine)
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

        tap(&machine)
        tap(&machine)
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
        hold(&machine)
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
        #expect(tap(&machine) == openingADictation)
    }

    @Test("Final Text never carries the whitespace the Engine left around it")
    func finalTextNeverCarriesTheWhitespaceTheEngineLeftAroundIt() {
        var machine = DictationMachine()
        hold(&machine)
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

        _ = machine.receive(.hotkeyPressed)
        #expect(machine.receive(.targetAppNoted(mail)).isEmpty)
    }
}
