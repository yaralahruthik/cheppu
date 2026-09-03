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
// tap — and read back what its ports were told. Nothing here looks inside the
// core, loads a model, opens a microphone, or waits for a clock.
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

    /// A core wired to fakes, plus the journal they all write to.
    private struct Scenario {
        let journal: PortJournal
        let clock: FakeClock
        let hotkey: FakeHotkey
        let core: DictationCore

        init(
            hears: RawTranscript = DictationCoreTests.heardWords,
            captures: CapturedAudio = DictationCoreTests.spokenAudio,
            hearsLevels: [InputLevel] = [],
            now: Date = DictationCoreTests.aTuesdayAfternoon,
            insertionRefuses: Bool = false,
            isAccessibilityGranted: Bool = true
        ) {
            let journal = PortJournal()
            let clock = FakeClock(reading: now)
            let hotkey = FakeHotkey(isAccessibilityGranted: isAccessibilityGranted)
            self.journal = journal
            self.clock = clock
            self.hotkey = hotkey
            self.core = DictationCore(
                hotkey: hotkey,
                audio: FakeAudioCapture(journal: journal, captured: captures, hearsLevels: hearsLevels),
                engine: FakeEngine(journal: journal, transcript: hears),
                insertion: insertionRefuses ? RefusingInsertion() : FakeInsertion(journal: journal),
                clipboard: FakeClipboard(),
                history: FakeHistory(journal: journal),
                feedback: FakeFeedback(journal: journal),
                clock: clock
            )
        }

        /// Taps the Hotkey, speaks, and taps it again.
        func toggleADictation() async throws {
            try await core.receive(.activationToggled)
            try await core.receive(.activationToggled)
        }

        /// The same Dictation, driven from the keyboard rather than through the
        /// core's own door.
        func toggleADictationWithTheHotkey() async throws {
            try await core.watchForActivations()
            await hotkey.tap()
            await hotkey.tap()
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
                .inserted(FinalText("hello there")),
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

    @Test("A Toggle Activation puts the words where the cursor is")
    func aToggleActivationPutsTheWordsWhereTheCursorIs() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()

        #expect(await scenario.journal.calls.contains(.inserted(FinalText("hello there"))))
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
                .inserted(FinalText("hello there")),
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
                before: .inserted(FinalText("hello there"))
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
        let scenario = Scenario(insertionRefuses: true)

        await #expect(throws: RefusingInsertion.Refused.self) {
            try await scenario.toggleADictation()
        }

        #expect(await scenario.journal.calls.last == .pillHidden)

        try await scenario.core.receive(.activationToggled)
        let timesCaptureOpened = await scenario.journal.calls.filter { $0 == .capturingStarted }.count
        #expect(timesCaptureOpened == 2)
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

    @Test("Stopping a Dictation that was never started touches nothing")
    func stoppingADictationThatWasNeverStartedTouchesNothing() async throws {
        let scenario = Scenario()

        try await scenario.core.receive(.activationStopped)

        #expect(await scenario.journal.calls.isEmpty)
    }

    @Test("A second Toggle Activation runs the same course as the first")
    func aSecondToggleActivationRunsTheSameCourseAsTheFirst() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()
        try await scenario.toggleADictation()

        let insertions = await scenario.journal.calls.filter { $0 == .inserted(FinalText("hello there")) }
        #expect(insertions.count == 2)
    }
}
