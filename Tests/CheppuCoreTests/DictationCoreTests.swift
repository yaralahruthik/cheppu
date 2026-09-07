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
        text: "Hello there.",
        words: [
            WordTiming(word: "Hello", start: .milliseconds(0), end: .milliseconds(400)),
            WordTiming(word: "there.", start: .milliseconds(520), end: .milliseconds(900)),
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
        let clipboard: FakeClipboard
        let cleanup: FakeCleanupSwitches
        let diagnostics: FakeDiagnostics
        let core: DictationCore

        init(
            hears: RawTranscript = DictationCoreTests.heardWords,
            captures: CapturedAudio = DictationCoreTests.spokenAudio,
            hearsLevels: [InputLevel] = [],
            now: Date = DictationCoreTests.aTuesdayAfternoon,
            typingIn app: TargetApp? = DictationCoreTests.mail,
            microphone: FakeAudioCapture.Outcome = .opens,
            insertion: FakeInsertion.Outcome = .lands,
            hadCopied: String? = nil,
            historyRefuses: Bool = false,
            isAccessibilityGranted: Bool = true,
            engine: FakeEngine.Outcome = .hears,
            cleaningWith rules: CleanupRules = .all
        ) {
            let journal = PortJournal()
            let clock = FakeClock(reading: now)
            let hotkey = FakeHotkey(isAccessibilityGranted: isAccessibilityGranted)
            let focus = FakeFocus(on: app)
            let clipboard = FakeClipboard(journal: journal, holding: hadCopied)
            let cleanup = FakeCleanupSwitches(rules)
            let diagnostics = FakeDiagnostics()
            self.cleanup = cleanup
            self.diagnostics = diagnostics
            self.journal = journal
            self.clock = clock
            self.hotkey = hotkey
            self.focus = focus
            self.clipboard = clipboard
            self.core = DictationCore(
                cleaningWith: cleanup,
                hotkey: hotkey,
                audio: FakeAudioCapture(
                    journal: journal, captured: captures, outcome: microphone,
                    hearsLevels: hearsLevels),
                engine: FakeEngine(journal: journal, transcript: hears, outcome: engine),
                insertion: FakeInsertion(journal: journal, focus: focus, outcome: insertion),
                clipboard: clipboard,
                history: FakeHistory(journal: journal, refuses: historyRefuses),
                feedback: FakeFeedback(journal: journal),
                permissions: FakePermissions(journal: journal),
                clock: clock,
                diagnostics: diagnostics
            )
        }

        /// The user reads the notice the Pill is showing, which takes as long
        /// as the core decided it should stay up.
        func readTheNotice() async {
            await clock.advance(by: DictationMachine.longEnoughToReadTheNotice)
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
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon)
                ),
                .inserted(FinalText("Hello there."), into: Self.mail),
                .pillHidden,
            ]
        )
    }

    // MARK: - Cleanup

    @Test("The words that land are the words the user meant, not how they said them")
    func theWordsThatLandAreTheWordsTheUserMeant() async throws {
        let scenario = Scenario(hears: ARawTranscript.saidWithAPause)

        try await scenario.toggleADictation()

        // The Filler Word is gone, the sentences start with capitals, and the
        // pause the user left between two thoughts is a Paragraph Break. History
        // and the Target App are given the same Final Text, because there is
        // only one.
        #expect(await scenario.insertedText == ["That is one thought.\nThe next one"])
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(
                        finalText: FinalText("That is one thought.\nThe next one"),
                        recordedAt: Self.aTuesdayAfternoon
                    )
                )
            ))
    }

    @Test("Dictating into a Terminal never puts a newline in it")
    func dictatingIntoATerminalNeverPutsANewlineInIt() async throws {
        let scenario = Scenario(
            hears: ARawTranscript.saidWithAPause, typingIn: ATargetApp.terminal)

        try await scenario.toggleADictation()

        // The same Dictation that lands in a mail window with a Paragraph Break
        // in it lands here as one line: a newline in a Terminal is Return, and
        // it would run whatever was on the line. The break becomes the space it
        // was made from rather than being dropped, so nothing the user said is
        // lost and nothing runs.
        #expect(await scenario.insertedText == ["That is one thought. The next one"])

        // And Cleanup's output is untouched by where the words were going.
        // History keeps what was said, not what was safe to type.
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(
                        finalText: FinalText("That is one thought.\nThe next one"),
                        recordedAt: Self.aTuesdayAfternoon
                    )
                )
            ))
    }

    @Test("A Terminal Cheppu has never heard of is still a Terminal")
    func aTerminalCheppuHasNeverHeardOfIsStillATerminal() async throws {
        let scenario = Scenario(
            hears: ARawTranscript.saidWithAPause, typingIn: ATargetApp.anUnfamiliarTerminal)

        try await scenario.toggleADictation()

        // Nobody added this one to the list, and it is treated as a Terminal all
        // the same: it exposes no focused element, so Cheppu does not know that
        // the keyboard is pointing at a place text is written, and the
        // behaviour it falls back to is the safe one.
        #expect(await scenario.insertedText == ["That is one thought. The next one"])
    }

    @Test("Even with the Paragraph Break rule off, no newline reaches a Terminal")
    func evenWithTheParagraphBreakRuleOffNoNewlineReachesATerminal() async throws {
        // A Raw Transcript with the Engine's own newline in the middle of it,
        // and every Cleanup rule off — so the Final Text is the Raw Transcript
        // byte for byte, newline and all.
        let scenario = Scenario(
            hears: RawTranscript(
                text: "ls\nrm -rf /",
                words: [
                    WordTiming(word: "ls", start: .zero, end: .milliseconds(200)),
                    WordTiming(word: "rm -rf /", start: .seconds(3), end: .seconds(4)),
                ]
            ),
            typingIn: ATargetApp.terminal,
            cleaningWith: .off
        )

        try await scenario.toggleADictation()

        // A newline the Engine wrote is exactly as dangerous as one Cheppu
        // wrote, so the boundary flattens every one of them rather than only the
        // Paragraph Breaks it knows it made.
        #expect(await scenario.insertedText == ["ls rm -rf /"])
    }

    @Test("A switch moved in Settings is the switch the next Dictation goes through")
    func aSwitchMovedInSettingsIsTheSwitchTheNextDictationGoesThrough() async throws {
        // The user dictates, decides they wanted what they said left alone,
        // and turns the rules off. What that has to cost them is the flicking —
        // not a relaunch, and not a Dictation spent finding out whether it took
        // (`docs/product-experience.md` §8). The switches are read on the way
        // out of the Engine, so the next thing they say is cleaned the way the
        // window in front of them says it will be.
        let scenario = Scenario(hears: ARawTranscript.saidWithAPause)

        try await scenario.toggleADictation()
        await scenario.cleanup.set(.off)
        try await scenario.toggleADictation()

        #expect(
            await scenario.insertedText == [
                "That is one thought.\nThe next one",
                "um, that is one thought. the next one",
            ]
        )
    }

    @Test("With every Cleanup rule off, what lands is the Raw Transcript")
    func withEveryCleanupRuleOffWhatLandsIsTheRawTranscript() async throws {
        let scenario = Scenario(hears: ARawTranscript.saidWithAPause, cleaningWith: .off)

        try await scenario.toggleADictation()

        // Off is a real option and not a softer version of on
        // (`docs/product-experience.md` §8). The Insertion still contributes no
        // whitespace of its own, which is a promise about where the words go
        // rather than about what they are.
        #expect(await scenario.insertedText == ["um, that is one thought. the next one"])
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

        #expect(await scenario.insertedText == ["Hello there."])
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
        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A Toggle Activation puts the words where the cursor is")
    func aToggleActivationPutsTheWordsWhereTheCursorIs() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(await scenario.journal.calls.contains(.inserted(FinalText("Hello there."), into: Self.mail)))
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
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon)
                ),
                .inserted(FinalText("Hello there."), into: Self.mail),
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
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon)
                ),
                before: .inserted(FinalText("Hello there."), into: Self.mail)
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

        // An Insertion that did not land is not an error the Dictation ends on:
        // it is answered, here, with the words on the clipboard and the Pill
        // saying so.
        try await scenario.toggleADictation()
        await scenario.readTheNotice()

        #expect(await scenario.journal.calls.last == .pillHidden)

        try await scenario.tapThroughTheCore()
        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
    }

    @Test("A History that will not take the words does not take the Dictation with it")
    func aHistoryThatWillNotTakeTheWordsDoesNotTakeTheDictationWithIt() async throws {
        // A full disk, or a store that cannot be opened. History is written
        // first because it is the last resort and not because it is the point,
        // so a store that refuses must not also cost the user the Insertion —
        // which is where the words were actually going (ADR-0009).
        let scenario = Scenario(historyRefuses: true)

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText == ["Hello there."])
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("Words a broken History could not keep are still left where the user can reach them")
    func wordsABrokenHistoryCouldNotKeepAreStillLeftWhereTheUserCanReachThem() async throws {
        // Both of the places a Dictation is kept have gone at once: the store
        // will not take the words and the Insertion will not land them. The
        // clipboard is what is left, and it is enough — the words are lost only
        // where all three have gone wrong together.
        let scenario = Scenario(insertion: .refuses, historyRefuses: true)

        try await scenario.toggleADictation()

        #expect(await scenario.clipboard.contents == "Hello there.")
        #expect(await scenario.journal.calls.last == .pillShown(.onTheClipboard))
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
            $0 == .inserted(FinalText("Hello there."), into: Self.mail)
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
                .inserted(FinalText("Hello there."), into: Self.browser)))
    }

    @Test("A Dictation whose Target App lost focus keeps the words rather than misplacing them")
    func aDictationWhoseTargetAppLostFocusKeepsTheWords() async throws {
        let scenario = Scenario(insertion: .findsTheFocusMoved)

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText.isEmpty)
        // The words are still the user's: History was written before the
        // Insertion was tried, and they are on the clipboard for the user to
        // put where they meant them to go.
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon))))
        #expect(await scenario.clipboard.contents == "Hello there.")
    }

    @Test("A Dictation with no app to insert into still keeps the words")
    func aDictationWithNoAppToInsertIntoStillKeepsTheWords() async throws {
        let scenario = Scenario(typingIn: nil)

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText.isEmpty)
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon))))
        #expect(await scenario.clipboard.contents == "Hello there.")

        await scenario.readTheNotice()
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
            hears: RawTranscript(text: " Hello there.\n", words: Self.heardWords.words))

        try await scenario.toggleADictation()

        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])
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
        #expect(await scenario.insertedText == ["Hello there."])
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

        #expect(await scenario.insertedText == ["Hello there."])

        // The second Dictation's five minutes are its own, and two more of them
        // are what ends it.
        await scenario.clock.advance(by: .seconds(2 * 60))

        #expect(await scenario.insertedText == ["Hello there.", "Hello there."])
    }

    @Test("The Cap stops a Hold that is still being held")
    func theCapStopsAHoldThatIsStillBeingHeld() async throws {
        let scenario = Scenario()
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.clock.advance(by: .seconds(5 * 60))

        #expect(await scenario.insertedText == ["Hello there."])

        // The key is still down five minutes later. Letting go of it belongs to
        // a Dictation that is over, and must not stop the next one before it
        // has begun.
        await scenario.hotkey.release()
        await scenario.tapTheHotkey()

        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
        #expect(await scenario.journal.calls.last == .pillShown(.listening(.silent)))
    }

    // MARK: - Clipboard Fallback

    @Test("An Insertion that did not land leaves the words on the clipboard and says so")
    func anInsertionThatDidNotLandLeavesTheWordsOnTheClipboard() async throws {
        let scenario = Scenario(insertion: .refuses)

        try await scenario.toggleADictation()

        // The whole of a Dictation that could not be typed. Nothing is lost —
        // History was written before the Insertion was tried — and nothing is
        // silent: the words go where the user can paste them, and the Pill says
        // so rather than disappearing on a Dictation that went nowhere.
        #expect(
            await scenario.callsIgnoringTimestamps == Self.openingADictation + [
                .capturingStopped,
                .cuePlayed(.dictationStopped),
                .pillShown(.transcribing),
                .transcribed(Self.spokenAudio),
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon)
                ),
                .leftOnTheClipboard(FinalText("Hello there.")),
                .pillShown(.onTheClipboard),
            ])

        await scenario.readTheNotice()
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test(
        "However an Insertion fails, the words end up on the clipboard and in History",
        arguments: [
            FakeInsertion.Outcome.refuses,
            .findsTheFocusMoved,
            .findsAccessibilityTakenAway,
        ]
    )
    func howeverAnInsertionFailsTheWordsEndUpOnTheClipboard(
        _ outcome: FakeInsertion.Outcome
    ) async throws {
        let scenario = Scenario(insertion: outcome)

        try await scenario.toggleADictation()

        // The three ways an Insertion does not land: the Target App would not
        // take it, the user moved on while the Engine worked, and the
        // Accessibility that types the paste was taken away mid-session. The
        // user is told the same thing about all three, because the same thing
        // is true of all three — the words are on the clipboard.
        #expect(await scenario.insertedText.isEmpty)
        #expect(await scenario.clipboard.contents == "Hello there.")
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("Hello there."), recordedAt: Self.aTuesdayAfternoon))))
        #expect(await scenario.journal.calls.contains(.pillShown(.onTheClipboard)))
    }

    @Test("The clipboard the user had is deliberately not given back")
    func theClipboardTheUserHadIsDeliberatelyNotGivenBack() async throws {
        let scenario = Scenario(insertion: .refuses, hadCopied: "https://example.com")

        try await scenario.toggleADictation()

        // The one place Cheppu keeps something of the user's rather than
        // putting it back. What they had copied is gone and what they said is
        // there instead, because a fallback that gave the clipboard back would
        // be a Dictation that vanished.
        #expect(await scenario.clipboard.contents == "Hello there.")
    }

    @Test("A Dictation that landed leaves the clipboard exactly as the user had it")
    func aDictationThatLandedLeavesTheClipboardAsTheUserHadIt() async throws {
        let scenario = Scenario(hadCopied: "https://example.com")

        try await scenario.toggleADictation()

        // The Insertion borrows the pasteboard and gives it back — that is
        // `PasteInsertion`'s, and it is tested there. What is asserted here is
        // that nothing else touches it: the Clipboard Fallback is the only
        // thing in Cheppu that leaves something on the user's clipboard.
        #expect(await scenario.clipboard.contents == "https://example.com")
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("The notice stays up until the user has had time to read it")
    func theNoticeStaysUpUntilTheUserHasHadTimeToReadIt() async throws {
        let scenario = Scenario(insertion: .refuses)

        try await scenario.toggleADictation()

        // The Pill is the whole of what says where the words went, so it
        // cannot come down in the same breath as it goes up.
        #expect(await scenario.journal.calls.last == .pillShown(.onTheClipboard))

        await scenario.readTheNotice()

        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("The next Dictation takes the notice over, and never has its Pill taken away")
    func theNextDictationTakesTheNoticeOver() async throws {
        let scenario = Scenario(insertion: .refuses)

        try await scenario.toggleADictation()
        // The user reads the notice, presses the Hotkey and starts speaking
        // again — all inside the time the notice would have come down in.
        try await scenario.tapThroughTheCore()
        await scenario.readTheNotice()

        // The Pill on screen belongs to the Dictation that is listening now,
        // and the notice the Dictation before it left is not what takes it
        // down.
        #expect(await scenario.journal.calls.last == .pillShown(.listening(.silent)))
    }

    @Test("The words left to paste are the words that were safe to type there")
    func theWordsLeftToPasteAreTheWordsThatWereSafeToTypeThere() async throws {
        let scenario = Scenario(
            hears: ARawTranscript.saidWithAPause,
            typingIn: ATargetApp.terminal,
            insertion: .refuses
        )

        try await scenario.toggleADictation()

        // What could not be typed is what is left to paste, and the user's next
        // keystroke pastes it into the same Terminal the Insertion was for. So
        // the Paragraph Break stays flattened — a newline there is Return
        // however it arrives (#12) — while History keeps what was said.
        #expect(await scenario.clipboard.contents == "That is one thought. The next one")
        #expect(
            await scenario.journal.calls.contains(
                .appendedToHistory(
                    HistoryEntry(
                        finalText: FinalText("That is one thought.\nThe next one"),
                        recordedAt: Self.aTuesdayAfternoon
                    )
                )))
    }


    // MARK: - A permission that is missing

    @Test("A Dictation with the Microphone taken away says so rather than doing nothing")
    func aDictationWithTheMicrophoneTakenAwaySaysSo() async throws {
        let scenario = Scenario(microphone: .findsTheMicrophoneTakenAway)
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()

        // Capture is the first thing a Dictation does, so a Microphone that has
        // been taken away means no Cue, no level and nothing heard. What the
        // user gets instead is the Pill naming the permission and Cheppu
        // offering the pane it is granted on — never the silence that is
        // indistinguishable from an app that has stopped working
        // (`docs/product-experience.md` §9).
        #expect(
            await scenario.callsIgnoringTimestamps == [
                .pillShown(.permissionMissing(.microphone)),
                .askedFor(.microphone),
            ])

        await scenario.readTheNotice()
        #expect(await scenario.journal.calls.last == .pillHidden)
    }

    @Test("A microphone that is not there is not a permission the user is sent off to grant")
    func aMicrophoneThatIsNotThereIsNotAPermissionToGrant() async throws {
        let scenario = Scenario(microphone: .findsNoMicrophone)
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()

        // No input device is not something a System Settings pane can fix
        // (`AudioCaptureFailure.permission`). The Dictation ends, and nothing is
        // named: there is no switch to send the user to.
        #expect(await scenario.journal.calls == [.pillHidden])
    }

    @Test("Every attempt is answered, because every attempt is a Dictation that did not happen")
    func everyAttemptIsAnswered() async throws {
        let scenario = Scenario(microphone: .findsTheMicrophoneTakenAway)
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()
        await scenario.readTheNotice()
        await scenario.hotkey.press()

        // Saying it once and leaving the second press to fail quietly would be
        // the same silence one press later. How often Cheppu puts an alert in
        // front of the user is the app's to decide; what the core does is
        // answer the press it was given.
        let said = await scenario.journal.calls.filter {
            $0 == .pillShown(.permissionMissing(.microphone))
        }
        let named = await scenario.journal.calls.filter { $0 == .askedFor(.microphone) }
        #expect(said.count == 2)
        #expect(named.count == 2)
    }

    // MARK: - The Diagnostics Log

    @Test("A Dictation is written down as the states it moved through")
    func aDictationIsWrittenDownAsTheStatesItMovedThrough() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictationWithTheHotkey()

        // The whole story of a Dictation in four lines, and the whole of its
        // timings too: what is written next to each of these is when it
        // happened, so how long the user spoke, how long the Engine took and
        // how long the words took to land are the gaps between them.
        #expect(
            scenario.diagnostics.notes == [
                .watchingForTheHotkey,
                .dictationMoved(from: .idle, to: .listening, by: .theHotkeyWentDown),
                .dictationMoved(from: .listening, to: .transcribing, by: .theHotkeyWentDown),
                .dictationMoved(
                    from: .transcribing, to: .inserting, by: .theRawTranscriptArrived),
                .dictationMoved(from: .inserting, to: .idle, by: .theInsertionLanded),
            ]
        )
    }

    @Test("Nothing the user said is anywhere in the log")
    func nothingTheUserSaidIsAnywhereInTheLog() async throws {
        let said = ARawTranscript.somethingWorthNotSharing
        let scenario = Scenario(hears: said)

        try await scenario.toggleADictationWithTheHotkey()

        // Dictate known text and search the log for it, which is the acceptance
        // this whole vocabulary exists to pass. Not one word of what the Engine
        // heard, and not one word of the Final Text that Cleanup made of it, is
        // anywhere in what was written down — because nothing a note is made of
        // can carry a word at all.
        let written = String(describing: scenario.diagnostics.notes)
        for word in said.words.map({ $0.word.trimmingCharacters(in: .punctuationCharacters) }) {
            #expect(!written.localizedCaseInsensitiveContains(word))
        }
    }

    @Test("The log is a line per thing that happened, not a line per event")
    func theLogIsALinePerThingThatHappened() async throws {
        let scenario = Scenario(
            hearsLevels: (0...20).map { InputLevel(Double($0) / 20) })

        try await scenario.toggleADictationWithTheHotkey()

        // A Dictation reports its Input Level many times a second and not one
        // of them is a thing that happened to it. A log that wrote a line per
        // event would bury the four that matter under a hundred that do not —
        // and would put a disk write on the stop-to-insert path
        // (`docs/product-experience.md` §7).
        #expect(scenario.diagnostics.notes.count == 5)
    }

    @Test("A permission that was taken away is named in the log")
    func aPermissionThatWasTakenAwayIsNamedInTheLog() async throws {
        let scenario = Scenario(microphone: .findsTheMicrophoneTakenAway)
        try await scenario.core.watchForActivations()

        await scenario.hotkey.press()

        // The one failure with a name worth writing down, and the one somebody
        // reading a week of these is looking for: every Dictation ending here
        // is a permission that was taken away, not an app that is broken.
        #expect(
            scenario.diagnostics.notes.contains(.permissionMissing(.microphone)))
        #expect(
            scenario.diagnostics.notes.contains(
                .dictationMoved(from: .listening, to: .idle, by: .aPermissionWasMissing)))
    }

    @Test("A failure the core has no name for is written down by its own name")
    func aFailureTheCoreHasNoNameForIsWrittenDownByItsOwnName() async throws {
        let scenario = Scenario(engine: .findsNoEngineOnTheMachine)
        try await scenario.core.watchForActivations()

        await scenario.tapTheHotkey()
        await scenario.tapTheHotkey()

        // Named rather than described: what a stranger's error prints is a
        // stranger's to decide, and a type name is written into the binary when
        // Cheppu is built.
        let named = scenario.diagnostics.notes.compactMap { note -> String? in
            guard case .somethingFailed(let name) = note else { return nil }
            return name.description
        }
        #expect(named == ["CheppuCoreTests.FakeEngine.NoEngineOnTheMachine"])
    }

    @Test("An Insertion that did not land is written down as the way it ended")
    func anInsertionThatDidNotLandIsWrittenDownAsTheWayItEnded() async throws {
        let scenario = Scenario(insertion: .findsTheFocusMoved)

        try await scenario.toggleADictationWithTheHotkey()

        // The Clipboard Fallback, read off the log: the Dictation reached
        // Inserting and left it without the words landing. That is what tells
        // somebody diagnosing a report of "my words did not appear" that they
        // are on the clipboard rather than lost.
        #expect(
            scenario.diagnostics.notes.last
                == .dictationMoved(from: .inserting, to: .idle, by: .theInsertionDidNotLand))
    }

    @Test("A keyboard Cheppu may not watch is written down, because nothing else says so")
    func aKeyboardCheppuMayNotWatchIsWrittenDown() async throws {
        let scenario = Scenario(isAccessibilityGranted: false)

        await #expect(throws: HotkeyFailure.self) {
            try await scenario.core.watchForActivations()
        }

        // The one failure that is not a Dictation's: there is no Dictation to
        // fail, so from outside the app a Hotkey nobody may watch and a Hotkey
        // nobody pressed look exactly the same.
        #expect(
            scenario.diagnostics.notes == [
                .theHotkeyCouldNotBeWatched(FailureName(of: HotkeyFailure.accessibilityDenied))
            ]
        )
    }
}
