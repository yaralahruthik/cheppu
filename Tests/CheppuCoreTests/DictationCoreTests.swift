import Foundation
import Testing

@testable import CheppuCore

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
        let core: DictationCore

        init(
            hears: RawTranscript = DictationCoreTests.heardWords,
            captures: CapturedAudio = DictationCoreTests.spokenAudio,
            now: Date = DictationCoreTests.aTuesdayAfternoon
        ) {
            let journal = PortJournal()
            let clock = FakeClock(reading: now)
            self.journal = journal
            self.clock = clock
            self.core = DictationCore(
                hotkey: FakeHotkey(),
                audio: FakeAudioCapture(journal: journal, captured: captures),
                engine: FakeEngine(journal: journal, transcript: hears),
                insertion: FakeInsertion(journal: journal),
                clipboard: FakeClipboard(),
                history: FakeHistory(journal: journal),
                feedback: FakeFeedback(journal: journal),
                clock: clock
            )
        }

        /// Taps the Hotkey, speaks, and taps it again.
        func toggleADictation() async throws {
            try await core.receive(.activationStarted)
            try await core.receive(.activationStopped)
        }
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
                .pillShown(.listening),
                .cuePlayed(.dictationStopped),
                .pillShown(.transcribing),
                .capturingStopped,
                .transcribed(Self.spokenAudio),
                .appendedToHistory(
                    HistoryEntry(finalText: FinalText("hello there"), recordedAt: Self.aTuesdayAfternoon)
                ),
                .inserted(FinalText("hello there")),
                .pillHidden,
            ]
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

        let calls = await scenario.journal.calls
        let recorded = try #require(
            calls.firstIndex { if case .appendedToHistory = $0 { true } else { false } }
        )
        let inserted = try #require(calls.firstIndex(of: .inserted(FinalText("hello there"))))
        #expect(recorded < inserted)
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

    @Test("Stopping a Dictation that was never started touches nothing")
    func stoppingADictationThatWasNeverStartedTouchesNothing() async throws {
        let scenario = Scenario()

        try await scenario.core.receive(.activationStopped)

        #expect(await scenario.journal.calls.isEmpty)
    }

    @Test("A second Toggle Activation runs the same course as the first")
    func aSecondDictationRunsTheSameCourseAsTheFirst() async throws {
        let scenario = Scenario()

        try await scenario.toggleADictation()
        try await scenario.toggleADictation()

        let insertions = await scenario.journal.calls.filter { $0 == .inserted(FinalText("hello there")) }
        #expect(insertions.count == 2)
    }
}
