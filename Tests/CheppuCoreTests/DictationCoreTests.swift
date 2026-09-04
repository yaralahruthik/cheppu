import Foundation
import Testing

@testable import CheppuCore

extension [PortJournal.Call] {
    /// Whether one port was called before another. False when either call is
    /// missing, so an assertion built on it fails rather than passes vacuously.
    func calls(_ first: PortJournal.Call, before second: PortJournal.Call) -> Bool {
        guard let earlier = firstIndex(of: first), let later = firstIndex(of: second) else {
            return false
        }
        return earlier < later
    }
}

// These tests drive the core the way the user drives it — a tap, then another
// tap, or the key held down and let go — and read back what its ports were
// told. Nothing here looks inside the core, loads a model, opens a microphone,
// or waits for a clock: a Hold is two seconds long because the Clock says so.
@Suite("Dictation core")
struct DictationCoreTests {
    private static let spokenAudio = CapturedAudio(samples: [0.1, -0.2, 0.3], sampleRate: 16_000)

    private static let heardWords = RawTranscript(
        text: "hello there",
        words: [
            WordTiming(word: "hello", start: .milliseconds(0), end: .milliseconds(400)),
            WordTiming(word: "there", start: .milliseconds(520), end: .milliseconds(900)),
        ]
    )

    private static let aTuesdayAfternoon = Date(timeIntervalSince1970: 1_700_000_000)

    private static let mail = ATargetApp.mail
    private static let browser = ATargetApp.browser

    /// What every port is told when a Dictation opens, whichever Activation
    /// opened it.
    private static let openingADictation: [PortJournal.Call] = [
        .capturingStarted, .cuePlayed(.dictationStarted), .pillShown(.listening(.silent)),
    ]

    /// A core wired to fakes, plus the journal they all write to.
    private struct Scenario {
        let journal: PortJournal
        let clock: FakeClock
        let hotkey: FakeHotkey
        let focus: FakeFocus
        let core: DictationCore

        init(
            hears: RawTranscript = DictationCoreTests.heardWords,
            captures: CapturedAudio = DictationCoreTests.spokenAudio,
            hearsLevels: [InputLevel] = [],
            now: Date = DictationCoreTests.aTuesdayAfternoon,
            typingIn app: TargetApp? = DictationCoreTests.mail,
            insertion: FakeInsertion.Outcome = .lands,
            historyRefuses: Bool = false,
            isAccessibilityGranted: Bool = true
        ) {
            let journal = PortJournal()
            let clock = FakeClock(reading: now)
            let hotkey = FakeHotkey(isAccessibilityGranted: isAccessibilityGranted)
            let focus = FakeFocus(on: app)
            self.journal = journal
            self.clock = clock
            self.hotkey = hotkey
            self.focus = focus
            self.core = DictationCore(
                hotkey: hotkey,
                audio: FakeAudioCapture(journal: journal, captured: captures, hearsLevels: hearsLevels),
                engine: FakeEngine(journal: journal, transcript: hears),
                insertion: FakeInsertion(journal: journal, focus: focus, outcome: insertion),
                clipboard: FakeClipboard(),
                history: FakeHistory(journal: journal, refuses: historyRefuses),
                feedback: FakeFeedback(journal: journal),
                clock: clock
            )
        }

        /// Every Final Text the Dictation put somewhere, as the user would read
        /// it, in the order it was inserted.
        var insertedText: [String] {
            get async {
                await journal.calls.compactMap { call in
                    guard case .inserted(let finalText, _) = call else { return nil }
                    return finalText.text
                }
            }
        }

        /// Everything the ports were told, with the moment a History entry was
        /// stamped with left out.
        ///
        /// A Hold takes two seconds off the Clock and a tap takes none, so the
        /// stamps differ where nothing the user notices does. What is being
        /// compared is the Dictation, not the hour.
        var callsIgnoringTimestamps: [PortJournal.Call] {
            get async {
                await journal.calls.map { call in
                    guard case .appendedToHistory(let entry) = call else { return call }
                    return .appendedToHistory(
                        HistoryEntry(
                            finalText: entry.finalText,
                            recordedAt: DictationCoreTests.aTuesdayAfternoon
                        )
                    )
                }
            }
        }

        /// The Hotkey tapped, through the core's own door: down, and up again
        /// inside the threshold.
        func tapThroughTheCore() async throws {
            try await core.receive(.hotkeyPressed)
            try await core.receive(.hotkeyReleased(heldFor: .milliseconds(120)))
        }

        /// Taps the Hotkey, speaks, and taps it again.
        func toggleADictation() async throws {
            try await tapThroughTheCore()
            try await tapThroughTheCore()
        }

        /// The Hotkey tapped at the keyboard: down and up again with no time
        /// worth measuring in between, which is what a tap is.
        func tapTheHotkey() async {
            await hotkey.press()
            await hotkey.release()
        }

        /// The Hotkey held down for as long as it takes to say something, and
        /// then let go.
        ///
        /// The holding is done to the Clock rather than to the suite, which is
        /// what makes a two-second Hold cost a test nothing.
        func holdTheHotkey(for heldFor: Duration = .seconds(2)) async {
            await hotkey.press()
            await clock.advance(by: heldFor)
            await hotkey.release()
        }

        /// The same Dictation, driven from the keyboard rather than through the
        /// core's own door.
        func toggleADictationWithTheHotkey() async throws {
            try await core.watchForActivations()
            await tapTheHotkey()
            await tapTheHotkey()
        }
    }

    @Test("A tap of the Hotkey runs a Dictation, and the next tap ends it")
    func aTapOfTheHotkeyRunsADictationAndTheNextTapEndsIt() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictationWithTheHotkey()

        // The whole Dictation, set off by two taps of a key pressed in whatever
        // app the user was already working in.
        #expect(
            await scenario.journal.calls == [
                .capturingStarted,
                .cuePlayed(.dictationStarted),
                .pillShown(.listening(.silent)),
                .capturingStopped,
                .cuePlayed(.dictationStopped),
                .pillShown(.transcribing),
                .transcribed(Self.spokenAudio),
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon)
                ),
                .inserted(FinalText("hello there"), into: Self.mail),
                .pillHidden,
            ]
        )
    }

    @Test("Without Accessibility, watching for Activations says so rather than silently doing nothing")
    func withoutAccessibilityWatchingForActivationsSaysSo() async throws {
        let scenario = Scenario(isAccessibilityGranted: false)

        await #expect(throws: HotkeyFailure.accessibilityDenied) {
            try await scenario.core.watchForActivations()
        }

        // And nothing is left half-watching behind the refusal.
        #expect(await !scenario.hotkey.isBeingWatched)
    }

    @Test("Nothing watches the keyboard until it is asked to")
    func nothingWatchesTheKeyboardUntilItIsAskedTo() async throws {
        let scenario = Scenario()

        // Building the core does not start a tap. Watching is something the app
        // does once it is running, and it is the moment Accessibility is
        // wanted.
        #expect(await !scenario.hotkey.isBeingWatched)

        try await scenario.core.watchForActivations()

        #expect(await scenario.hotkey.isBeingWatched)
    }

    // MARK: - Toggle and Hold

    @Test("Releasing the Hotkey inside 250 ms starts a Toggle that runs until the next tap")
    func releasingTheHotkeyInsideTheThresholdStartsAToggle() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .milliseconds(200))
        await scenario.hotkey.release()

        // The key is back up and the microphone is still open: a tap starts a
        // Dictation that goes on running until the user taps again.
        #expect(await scenario.journal.calls == Self.openingADictation)

        await scenario.tapTheHotkey()

        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("Holding the Hotkey past 250 ms runs the Dictation only while it is held")
    func holdingTheHotkeyPastTheThresholdRunsTheDictationOnlyWhileItIsHeld() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .seconds(2))

        // Two seconds in, with the key still down, the Dictation is still
        // listening: a Hold lasts as long as the user holds it.
        #expect(await scenario.journal.calls == Self.openingADictation)

        await scenario.hotkey.release()

        // And letting go stops it, all the way through to the words landing.
        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("The Dictation starts on the way down, so speech during the threshold is captured")
    func theDictationStartsOnTheWayDown() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()

        // Before the Clock has moved at all — before anything could have
        // decided whether this is a Toggle or a Hold — the microphone is open.
        // The 250 ms are spent listening rather than waiting.
        #expect(await scenario.journal.calls.first == .capturingStarted)
    }

    @Test("Tap and Hold run the same Dictation, so the same key does the obvious thing both ways")
    func tapAndHoldRunTheSameDictation() async throws {
        let tapped = Scenario()
        try await tapped.core.watchForActivations()
        await tapped.tapTheHotkey()
        await tapped.tapTheHotkey()

        let held = Scenario()
        try await held.core.watchForActivations()
        await held.holdTheHotkey()

        // There is no setting and no mode between these two. Which gesture the
        // user made is their business, and nothing downstream of the Hotkey can
        // tell.
        #expect(await tapped.callsIgnoringTimestamps == held.callsIgnoringTimestamps)
    }

    @Test("Leaning on the Hotkey to end a Toggle ends it")
    func leaningOnTheHotkeyToEndAToggleEndsIt() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()
        // Started with a tap, finished with a long press. Nobody was taught
        // that gesture, and it does the obvious thing anyway.
        await scenario.holdTheHotkey()

        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A press that turns out to be typing takes back the Dictation it started")
    func aPressThatTurnsOutToBeTypingTakesTheDictationBack() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .milliseconds(40))
        await scenario.hotkey.typeWithItHeld()

        // Right Option types an accented character on several layouts, so a
        // Dictation begun on the way down has to be handed back when the press
        // turns out to have been an é. The microphone closes and the Pill goes,
        // and what it heard goes nowhere: nothing transcribed, nothing
        // inserted, nothing kept.
        #expect(
            await scenario.journal.calls
                == Self.openingADictation + [.capturingStopped, .pillHidden]
        )

        // And the next tap starts a Dictation rather than stopping one that was
        // never really running.
        await scenario.tapTheHotkey()
        await scenario.tapTheHotkey()

        #expect(await scenario.insertedText == ["hello there"])
    }

    @Test("A key brushed during a Hold ends the Dictation rather than throwing away what was said")
    func aKeyBrushedDuringAHoldEndsTheDictationRatherThanThrowingItAway() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .seconds(3))
        // Three seconds into a Hold, a stray key. What was said is not thrown
        // away over it: a press that far in is a Hold rather than an accented
        // character, and the Dictation ends the way a Hold ends.
        await scenario.hotkey.typeWithItHeld()

        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A tap that stops a Toggle stops it even if the user types before letting go")
    func aTapThatStopsAToggleStopsItEvenIfTheUserTypesBeforeLettingGo() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()

        // The user finishes dictating, taps to stop, and their hand lands on
        // the keyboard before the key is back up — so the press is spoiled and
        // never released. The Dictation stopped where the press began, and the
        // words land rather than the microphone being left open on what they
        // type next.
        await scenario.hotkey.press()
        await scenario.hotkey.typeWithItHeld()

        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A Toggle Activation puts the words where the cursor is")
    func aToggleActivationPutsTheWordsWhereTheCursorIs() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(await scenario.journal.calls.contains(.inserted(FinalText("hello there"), into: Self.mail)))
    }

    @Test("A Toggle Activation, from the tap to the words landing")
    func aToggleActivationFromTheTapToTheWordsLanding() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(
            await scenario.journal.calls == [
                .capturingStarted,
                .cuePlayed(.dictationStarted),
                .pillShown(.listening(.silent)),
                .capturingStopped,
                .cuePlayed(.dictationStopped),
                .pillShown(.transcribing),
                .transcribed(Self.spokenAudio),
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon)
                ),
                .inserted(FinalText("hello there"), into: Self.mail),
                .pillHidden,
            ]
        )
    }

    @Test("The microphone is closed before the stop Cue plays, so the Cue is not in what is transcribed")
    func theMicrophoneIsClosedBeforeTheStopCuePlays() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(await scenario.journal.calls.calls(.capturingStopped, before: .cuePlayed(.dictationStopped)))
    }

    @Test("The Pill says it is transcribing before the Engine is asked, so a pause is never a hang")
    func thePillSaysItIsTranscribingBeforeTheEngineIsAsked() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        // The Engine is the one part of a Dictation that takes long enough for
        // the user to wonder (`docs/product-experience.md` §3), and they are
        // told what is happening before it starts rather than after it ends.
        #expect(
            await scenario.journal.calls.calls(
                .pillShown(.transcribing),
                before: .transcribed(Self.spokenAudio)
            )
        )
    }

    @Test("The audio the Dictation captured is the audio the Engine was given")
    func theAudioTheDictationCapturedIsTheAudioTheEngineWasGiven() async throws {
        let spoken = CapturedAudio(samples: [0.9, 0.8, 0.7, 0.6], sampleRate: 44_100)
        let scenario = Scenario(captures: spoken)

        try await scenario.toggleADictation()

        #expect(await scenario.journal.calls.contains(.transcribed(spoken)))
    }

    @Test("The Final Text reaches History before Insertion is attempted")
    func theFinalTextReachesHistoryBeforeInsertionIsAttempted() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(
            await scenario.journal.calls.calls(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon)
                ),
                before: .inserted(FinalText("hello there"), into: Self.mail)
            )
        )
    }

    @Test("A History entry is stamped with what the Clock reads at the time")
    func aHistoryEntryIsStampedWithWhatTheClockReadsAtTheTime() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()
        await scenario.clock.advance(by: .seconds(90))
        try await scenario.toggleADictation()

        let stamps = await scenario.journal.calls.compactMap { call -> Date? in
            guard case .appendedToHistory(let entry) = call else { return nil }
            return entry.recordedAt
        }
        #expect(stamps == [Self.aTuesdayAfternoon, Self.aTuesdayAfternoon.addingTimeInterval(90)])
    }

    @Test("A Dictation whose Insertion fails still ends, so the next tap is not met with a dead app")
    func aDictationWhoseInsertionFailsStillEnds() async throws {
        let scenario = Scenario(insertion: .refuses)

        await #expect(throws: FakeInsertion.Refused.self) {
            try await scenario.toggleADictation()
        }

        #expect(await scenario.journal.calls.last == .pillHidden)

        try await scenario.tapThroughTheCore()
        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
    }

    @Test("A Dictation that fails on its last step still takes the Pill down")
    func aDictationThatFailsOnItsLastStepStillTakesThePillDown() async throws {
        // Nothing had focus, so this Dictation ends at History — and History
        // will not take it. The machine has already returned to Idle by the
        // time that happens, which is the one moment a failure could leave a
        // Pill on screen with nothing left running to take it away.
        let scenario = Scenario(typingIn: nil, historyRefuses: true)

        await #expect(throws: FakeHistory.Refused.self) {
            try await scenario.toggleADictation()
        }

        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("What the microphone is hearing is what the Pill is told to show")
    func whatTheMicrophoneIsHearingIsWhatThePillIsToldToShow() async throws {
        let scenario = Scenario(hearsLevels: [InputLevel(0.2), InputLevel(0.7)])

        try await scenario.toggleADictation()

        #expect(
            await Array(scenario.journal.calls.prefix(5)) == [
                .capturingStarted,
                .cuePlayed(.dictationStarted),
                // The Pill opens at silence and then shows each level the
                // microphone reported, in the order it was heard.
                .pillShown(.listening(.silent)),
                .pillShown(.listening(InputLevel(0.2))),
                .pillShown(.listening(InputLevel(0.7))),
            ]
        )
    }

    @Test("Letting go of a Hotkey that started nothing touches nothing")
    func lettingGoOfAHotkeyThatStartedNothingTouchesNothing() async throws {
        let scenario = Scenario()

        try await scenario.core.receive(.hotkeyReleased(heldFor: .seconds(2)))

        #expect(await scenario.journal.calls.isEmpty)
    }

    @Test("A second Toggle Activation runs the same course as the first")
    func aSecondToggleActivationRunsTheSameCourseAsTheFirst() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()
        try await scenario.toggleADictation()

        let insertions = await scenario.journal.calls.filter {
            $0 == .inserted(FinalText("hello there"), into: Self.mail)
        }
        #expect(insertions.count == 2)
    }

    @Test("The Target App is the app focused when the Dictation stops, not when it started")
    func theTargetAppIsTheAppFocusedWhenTheDictationStops() async throws {
        let scenario = Scenario(typingIn: Self.mail)

        try await scenario.tapThroughTheCore()
        // The user carries on speaking while they click into another app, which
        // is where they meant the words to go.
        await scenario.focus.moveTo(Self.browser)
        try await scenario.tapThroughTheCore()

        #expect(
            await scenario.journal.calls.contains(
                .inserted(FinalText("hello there"), into: Self.browser)))
    }

    @Test("A Dictation whose Target App lost focus keeps the words rather than misplacing them")
    func aDictationWhoseTargetAppLostFocusKeepsTheWords() async throws {
        let scenario = Scenario(insertion: .findsTheFocusMoved)

        await #expect(throws: InsertionFailure.focusMoved) {
            try await scenario.toggleADictation()
        }

        #expect(await scenario.insertedText.isEmpty)
        // The words are still the user's: History was written before the
        // Insertion was tried, and the Dictation ended rather than hanging.
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon))))
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A Dictation with no app to insert into still keeps the words")
    func aDictationWithNoAppToInsertIntoStillKeepsTheWords() async throws {
        let scenario = Scenario(typingIn: nil)

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText.isEmpty)
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon))))
        #expect(await scenario.journal.calls.last == .pillHidden)

        // And the Dictation ended, so the next tap of the Hotkey starts one
        // rather than trying to stop the one that never finished.
        try await scenario.tapThroughTheCore()
        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
    }

    @Test("Dictating mid-sentence joins to what is around it rather than doubling a space")
    func dictatingMidSentenceJoinsToWhatIsAroundIt() async throws {
        // Parakeet hands back a leading space and a trailing newline often
        // enough that a Dictation into the middle of a sentence would arrive
        // with a doubled space in front of it and a line break behind it.
        let scenario = Scenario(
            hears: RawTranscript(text: " hello there\n", words: Self.heardWords.words))

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText == ["hello there"])
    }


    // MARK: - Cancel

    @Test("Escape while it is listening throws the whole Dictation away")
    func escapeWhileItIsListeningThrowsTheWholeDictationAway() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()
        // The user misspoke. Everything that follows is the Dictation being
        // handed back: the microphone closes, a Cue of its own says so, and the
        // Pill goes. The Engine is never asked, nothing is inserted, and
        // nothing reaches History.
        await scenario.hotkey.pressEscape()

        #expect(
            await scenario.journal.calls
                == Self.openingADictation
                + [.capturingStopped, .cuePlayed(.dictationCancelled), .pillHidden]
        )
    }

    @Test("A Cancelled Dictation leaves Cheppu ready for the next one")
    func aCancelledDictationLeavesCheppuReadyForTheNextOne() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .seconds(2))
        // Escape while the key is still down: a Hold is Cancelled the same way
        // a Toggle is, and letting go afterwards belongs to a Dictation that is
        // already over.
        await scenario.hotkey.pressEscape()
        await scenario.hotkey.release()

        #expect(await scenario.insertedText.isEmpty)

        // And nothing is left counting for it: five minutes on, the Cap that
        // belonged to the Cancelled Dictation is not still out there to end
        // whatever the user is doing by then.
        let afterTheCancel = await scenario.journal.calls
        await scenario.clock.advance(by: .seconds(5 * 60))
        #expect(await scenario.journal.calls == afterTheCancel)

        await scenario.tapTheHotkey()
        await scenario.tapTheHotkey()

        #expect(await scenario.insertedText == ["hello there"])
    }

    @Test("Escape when no Dictation is listening touches nothing")
    func escapeWhenNoDictationIsListeningTouchesNothing() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        // Someone closing a dialog in the app they are working in. Cheppu is
        // handed the key like every other one it was not sent, and does nothing
        // with it.
        await scenario.hotkey.pressEscape()

        #expect(await scenario.journal.calls.isEmpty)

        // And after a Dictation has landed, it is nothing to it either.
        await scenario.tapTheHotkey()
        await scenario.tapTheHotkey()
        let afterTheDictation = await scenario.journal.calls
        await scenario.hotkey.pressEscape()

        #expect(await scenario.journal.calls == afterTheDictation)
    }

    // MARK: - Discard

    @Test("A Dictation with no speech in it disappears silently")
    func aDictationWithNoSpeechInItDisappearsSilently() async throws {
        // The Hotkey tapped by accident, and tapped again: the Engine heard
        // nothing in it.
        let scenario = Scenario(hears: RawTranscript(text: "", words: []))

        try await scenario.toggleADictation()

        // Nothing inserted and nothing in History, so a stray tap litters
        // neither the user's document nor the record of what they said.
        #expect(
            await scenario.journal.calls == Self.openingADictation + [
                .capturingStopped,
                .cuePlayed(.dictationStopped),
                .pillShown(.transcribing),
                .transcribed(Self.spokenAudio),
                .pillHidden,
            ]
        )
    }

    @Test("A Dictation the Engine answered with whitespace is Discarded too")
    func aDictationTheEngineAnsweredWithWhitespaceIsDiscardedToo() async throws {
        // What Parakeet hands back for a Dictation with no speech in it is a
        // space and a newline as often as it is nothing at all. Inserting those
        // would be a stray tap that moved the user's cursor.
        let scenario = Scenario(hears: RawTranscript(text: " \n", words: []))

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText.isEmpty)
        #expect(await scenario.journal.calls.last == .pillHidden)

        // And Cheppu is ready for the next one.
        try await scenario.tapThroughTheCore()
        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
    }

    // MARK: - The Cap

    @Test("A Dictation left running stops itself at five minutes and is transcribed as any other")
    func aDictationLeftRunningStopsItselfAtFiveMinutes() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()

        // A second short of the Cap the user could still walk back and finish
        // the sentence: the microphone is open and nothing has been decided.
        await scenario.clock.advance(by: .seconds(5 * 60 - 1))
        #expect(await scenario.journal.calls == Self.openingADictation)

        // The five minutes pass on the Clock rather than in the suite.
        await scenario.clock.advance(by: .seconds(1))

        // And what they did say is transcribed and inserted exactly as it would
        // have been had they stopped it themselves.
        #expect(await scenario.insertedText == ["hello there"])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A Dictation the user ended leaves the Cap counting for nobody")
    func aDictationTheUserEndedLeavesTheCapCountingForNobody() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()
        await scenario.tapTheHotkey()

        // The user starts another two minutes later. Three minutes after that,
        // the first Dictation's five would have been up — and the second is
        // still listening, because one Dictation's Cap can never end over the
        // top of the next one.
        await scenario.clock.advance(by: .seconds(2 * 60))
        await scenario.tapTheHotkey()
        await scenario.clock.advance(by: .seconds(3 * 60))

        #expect(await scenario.insertedText == ["hello there"])

        // The second Dictation's five minutes are its own, and two more of them
        // are what ends it.
        await scenario.clock.advance(by: .seconds(2 * 60))

        #expect(await scenario.insertedText == ["hello there", "hello there"])
    }

    @Test("The Cap stops a Hold that is still being held")
    func theCapStopsAHoldThatIsStillBeingHeld() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .seconds(5 * 60))

        #expect(await scenario.insertedText == ["hello there"])

        // The key is still down five minutes later. Letting go of it belongs to
        // a Dictation that is over, and must not stop the next one before it
        // has begun.
        await scenario.hotkey.release()
        await scenario.tapTheHotkey()

        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
        #expect(await scenario.journal.calls.last == .pillShown(.listening(.silent)))
    }
}
