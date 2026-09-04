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
        text: "Hello there.",
        words: [
            WordTiming(word: "Hello", start: .milliseconds(0), end: .milliseconds(400)),
            WordTiming(word: "there.", start: .milliseconds(520), end: .milliseconds(900)),
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
        .startCapturing, .startTheCap, .playCue(.dictationStarted),
        .showPill(.listening(.silent)),
    ]

    /// What stopping a Dictation always decides, whichever Activation stopped it.
    private let closingADictation: [DictationEffect] = [
        .noteTargetApp, .stopCapturing, .stopTheCap, .playCue(.dictationStopped),
        .showPill(.transcribing),
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
                == [.stopCapturing, .stopTheCap, .hidePill])

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
                .startTheCap,
                .playCue(.dictationStarted),
                .showPill(.listening(.silent)),
                .noteTargetApp,
                .stopCapturing,
                .stopTheCap,
                .playCue(.dictationStopped),
                .showPill(.transcribing),
                .transcribe(spokenAudio),
                .recordInHistory(FinalText("Hello there.")),
                .insert(FinalText("Hello there."), into: mail),
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
                .recordInHistory(FinalText("Hello there.")),
                before: .insert(FinalText("Hello there."), into: mail)
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
                .contains(.insert(FinalText("Hello there."), into: browser)))
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
                .recordInHistory(FinalText("Hello there.")),
                .insert(FinalText("Hello there."), into: browser),
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
                .recordInHistory(FinalText("Hello there.")),
                .hidePill,
            ])
        #expect(tap(&machine) == openingADictation)
    }

    // MARK: - Cleanup

    /// A Dictation carried as far as the Engine answering, so that what the
    /// machine does with a Raw Transcript is all that is left to say.
    private func transcribed(_ transcript: RawTranscript) -> [DictationEffect] {
        var machine = DictationMachine()
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))
        return machine.receive(.rawTranscriptReceived(transcript))
    }

    @Test("What is inserted and kept is the Raw Transcript with Cleanup applied")
    func whatIsInsertedAndKeptIsTheRawTranscriptWithCleanupApplied() {
        // Cleanup stands between the Engine and everything downstream of it, so
        // there is one Final Text and both History and the Target App get it.
        #expect(
            transcribed(ARawTranscript.saidWithAPause) == [
                .recordInHistory(FinalText("That is one thought.\nThe next one")),
                .insert(FinalText("That is one thought.\nThe next one"), into: mail),
            ])
    }

    @Test("A Dictation that was nothing but a Filler Word is Discarded")
    func aDictationThatWasNothingButAFillerWordIsDiscarded() {
        let clearingAThroat = RawTranscript(
            text: "um",
            words: [WordTiming(word: "um", start: .zero, end: .milliseconds(200))]
        )

        // Cleanup leaves nothing behind, so there is nothing to insert and
        // nothing worth keeping. It ends the way any Dictation with no words in
        // it ends: silently, and without moving the user's cursor.
        #expect(transcribed(clearingAThroat) == [.hidePill])
    }

    @Test("Final Text never carries the whitespace the Engine left around it")
    func finalTextNeverCarriesTheWhitespaceTheEngineLeftAroundIt() {
        var machine = DictationMachine()
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        let spacedOut = RawTranscript(text: "  Hello there.\n", words: heardWords.words)

        // Inserted into the middle of a sentence, the Engine's own leading
        // space would double the one already in front of the cursor. History
        // keeps what was said, whitespace and all, so that Cleanup can go on
        // promising that with every rule off the Final Text is the Raw
        // Transcript byte for byte (#11).
        #expect(
            machine.receive(.rawTranscriptReceived(spacedOut)) == [
                .recordInHistory(FinalText("  Hello there.\n")),
                .insert(FinalText("Hello there."), into: mail),
            ])
    }

    @Test("A Target App noted out of turn changes nothing")
    func aTargetAppNotedOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.targetAppNoted(mail)).isEmpty)

        _ = machine.receive(.hotkeyPressed)
        #expect(machine.receive(.targetAppNoted(mail)).isEmpty)
    }

    // MARK: - Cancel

    @Test("Escape while Listening throws the whole Dictation away")
    func escapeWhileListeningThrowsTheWholeDictationAway() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        // The user misspoke. The microphone closes, the Cap is called off, and
        // the Dictation is over: nothing goes to the Engine, nothing is
        // inserted, and nothing is kept.
        #expect(
            machine.receive(.escapePressed) == [
                .stopCapturing, .stopTheCap, .playCue(.dictationCancelled), .hidePill,
            ])
    }

    @Test("A Cancelled Dictation never reaches the Engine, whatever the microphone heard")
    func aCancelledDictationNeverReachesTheEngine() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)
        _ = machine.receive(.escapePressed)

        // The audio the microphone had already heard arrives after the
        // Dictation was thrown away. It is dropped where it lands.
        #expect(machine.receive(.audioCaptured(spokenAudio)).isEmpty)
    }

    @Test("Cancel answers the user, where Discard says nothing at all")
    func cancelAnswersTheUserWhereDiscardSaysNothing() {
        var cancelled = DictationMachine()
        _ = cancelled.receive(.hotkeyPressed)

        // Cancel is something the user did on purpose, and their eyes are on
        // their work, so it is answered out loud — and with a Cue of its own
        // rather than the stop Cue, which would say their words were on the
        // way. Discard is something Cheppu did on their behalf, and it is
        // silent.
        #expect(cancelled.receive(.escapePressed).contains(.playCue(.dictationCancelled)))

        var discarded = DictationMachine()
        hold(&discarded)
        _ = discarded.receive(.targetAppNoted(mail))
        _ = discarded.receive(.audioCaptured(spokenAudio))
        #expect(
            discarded.receive(.rawTranscriptReceived(RawTranscript(text: "", words: [])))
                == [.hidePill])
    }

    @Test("A Cancelled Dictation leaves Cheppu ready for the next one")
    func aCancelledDictationLeavesCheppuReadyForTheNextOne() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)
        _ = machine.receive(.escapePressed)

        // The key may well still be down — Escape cancels a Hold as readily as
        // a Toggle — so letting go of it must not be read as the end of a
        // Dictation that is already over.
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(3))).isEmpty)
        #expect(tap(&machine) == openingADictation)
    }

    @Test("Escape changes nothing whenever a Dictation is not Listening")
    func escapeChangesNothingWheneverADictationIsNotListening() {
        var machine = DictationMachine()

        // Nothing running: Escape is the user closing a dialog in the app they
        // are working in, and it is none of Cheppu's business.
        #expect(machine.receive(.escapePressed).isEmpty)

        // With the Engine: what was said is already captured, and Escape is too
        // late to throw it away rather than a second, quieter way to lose work.
        hold(&machine)
        #expect(machine.receive(.escapePressed).isEmpty)

        // And on the way into the Target App.
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))
        _ = machine.receive(.rawTranscriptReceived(heardWords))
        #expect(machine.receive(.escapePressed).isEmpty)
        #expect(machine.receive(.insertionSucceeded) == [.hidePill])
    }

    // MARK: - Discard

    @Test("A Dictation the Engine heard no words in ends silently")
    func aDictationTheEngineHeardNoWordsInEndsSilently() {
        var machine = DictationMachine()
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        // A Hotkey tapped by accident. There is nothing to insert, so nothing
        // is inserted; and nothing worth keeping, so History is left alone. A
        // stray tap must litter neither the user's document nor their History.
        #expect(
            machine.receive(.rawTranscriptReceived(RawTranscript(text: "", words: [])))
                == [.hidePill])
    }

    @Test("A Dictation whose text is only whitespace is Discarded too")
    func aDictationWhoseTextIsOnlyWhitespaceIsDiscardedToo() {
        var machine = DictationMachine()
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))

        // What the Engine hands back for a Dictation with no speech in it is a
        // space and a newline as often as it is nothing at all, and a Dictation
        // that inserted those would be a stray tap that moved the user's cursor.
        #expect(
            machine.receive(.rawTranscriptReceived(RawTranscript(text: " \n", words: [])))
                == [.hidePill])
    }

    @Test("A Discarded Dictation leaves Cheppu ready for the next one")
    func aDiscardedDictationLeavesCheppuReadyForTheNextOne() {
        var machine = DictationMachine()
        hold(&machine)
        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))
        _ = machine.receive(.rawTranscriptReceived(RawTranscript(text: "", words: [])))

        #expect(tap(&machine) == openingADictation)
    }

    // MARK: - The Cap

    @Test("The Cap is five minutes, and a Dictation still running at it is transcribed as any other")
    func aDictationStillRunningAtTheCapStopsAndIsTranscribed() {
        #expect(DictationMachine.cap == .seconds(5 * 60))

        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)

        // The user walked away with a Toggle running. What they did say is
        // theirs — the Dictation ends exactly as if they had ended it
        // themselves.
        #expect(machine.receive(.capReached) == closingADictation)
    }

    @Test("The Cap starts with the Dictation and is called off when it ends")
    func theCapStartsWithTheDictationAndIsCalledOffWhenItEnds() {
        var machine = DictationMachine()

        #expect(machine.receive(.hotkeyPressed).contains(.startTheCap))
        // Every way out of Listening calls it off, so the five minutes of one
        // Dictation can never end over the top of the next one.
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(2))).contains(.stopTheCap))

        var cancelled = DictationMachine()
        _ = cancelled.receive(.hotkeyPressed)
        #expect(cancelled.receive(.escapePressed).contains(.stopTheCap))

        var spoiled = DictationMachine()
        _ = spoiled.receive(.hotkeyPressed)
        #expect(
            spoiled.receive(.hotkeyPressSpoiled(heldFor: .milliseconds(40))).contains(.stopTheCap))

        var failed = DictationMachine()
        _ = failed.receive(.hotkeyPressed)
        #expect(failed.receive(.dictationFailed) == [.stopTheCap, .hidePill])
    }

    @Test("The Cap reached out of turn changes nothing")
    func theCapReachedOutOfTurnChangesNothing() {
        var machine = DictationMachine()

        #expect(machine.receive(.capReached).isEmpty)

        // And a Cap that ends while the Engine is working on the Dictation it
        // was counting for cannot stop it a second time.
        hold(&machine)
        #expect(machine.receive(.capReached).isEmpty)
    }

    @Test("A Dictation stopped by the Cap leaves Cheppu ready for the next one")
    func aDictationStoppedByTheCapLeavesCheppuReadyForTheNextOne() {
        var machine = DictationMachine()
        _ = machine.receive(.hotkeyPressed)
        _ = machine.receive(.capReached)

        // Five minutes of a Hold is a key that is still down. Letting go of it
        // belongs to a Dictation that is over.
        #expect(machine.receive(.hotkeyReleased(heldFor: .seconds(5 * 60))).isEmpty)

        _ = machine.receive(.targetAppNoted(mail))
        _ = machine.receive(.audioCaptured(spokenAudio))
        _ = machine.receive(.rawTranscriptReceived(heardWords))
        _ = machine.receive(.insertionSucceeded)

        #expect(tap(&machine) == openingADictation)
    }
}
