import CheppuCore
import Foundation
import Testing

@testable import CheppuEngine

/// The one place a fake would defeat the purpose: the real Parakeet, over
/// the author actually speaking, measured against what they actually said.
///
/// Every other suite in this repository runs with nothing downloaded, nothing
/// granted and nothing plugged in, which is what keeps it fast and what makes
/// the ports worth having. None of it can answer the only question that decides
/// whether Cheppu is usable: are the words right. This can, and pays 480 MB and
/// a model load for the privilege, which is why it is off unless asked for:
///
///     CHEPPU_ACCURACY=1 swift test --filter CheppuAccuracyTests
///
/// It runs in CI on its own job, on an Apple Silicon runner, so that the fast
/// suite never waits for it.
@Suite(
    "Accuracy",
    .enabled(if: ProcessInfo.processInfo.environment["CHEPPU_ACCURACY"] != nil),
    .serialized
)
struct AccuracyTests {
    /// The bare Engine, where the machine already keeps it, so that running
    /// this twice does not fetch it twice.
    ///
    /// Bare is the point. Both Ceilings measure the Engine on its own: a
    /// Spelling that made the Corpus score better is not the Engine getting
    /// better, and a Ceiling lowered on the strength of one would be a test
    /// that had stopped measuring the Engine (ADR-0014). Nothing is passed
    /// here, so there are no Spellings to read and no second pass to run.
    private static func engine(reading spellings: Spellings? = nil) throws -> ParakeetEngine {
        let applicationSupport = try EngineFiles.defaultApplicationSupport()
        return ParakeetEngine(
            directory: EngineFiles.directory(inApplicationSupport: applicationSupport),
            spellingsDirectory: EngineFiles.spellingsDirectory(
                inApplicationSupport: applicationSupport),
            configuration: .default,
            readingSpellings: spellings.map(WhatTheUserTaughtIt.init)
        )
    }

    /// The proving Spelling, committed beside the fixtures.
    ///
    /// **Cheppu**. Measured on 10 September 2026 on the bare Engine (Apple M4
    /// Pro, Parakeet TDT v3 int8, FluidAudio 0.15.6), the Engine hears it as
    /// "Chapo" in `proper-nouns` and as "Chepo" in `technical-terms`. It is the
    /// one word every user of this app will say, and it is wrong in two
    /// fixtures out of three, which is as good a case as the Corpus will ever
    /// offer.
    private static let provingSpelling = Spelling("Cheppu")!

    /// The two fixtures the bare Engine gets that word wrong in.
    private static let getsTheProvingWordWrong = ["proper-nouns", "technical-terms"]

    @Test("The Engine hears the author, and no worse than it did before")
    func theEngineHearsTheAuthorAndNoWorseThanItDidBefore() async throws {
        let fixtures = try AccuracyFixture.committed()
        let engine = try Self.engine()
        try await engine.downloadEngine { _ in }

        var measured: [WordErrorRate.Counting: [WordErrorRate]] = [:]

        for fixture in fixtures {
            // Transcribed once and scored twice. The Engine is the expensive
            // part and both questions are asked of the same words, so asking it
            // again would only add a way for the two answers to disagree.
            let heard = try await engine.transcribe(fixture.audio())

            // Printed per fixture as well as asserted over the corpus: a red run
            // is only actionable if it says which fixture got worse, and the
            // three kinds of error say what kind of worse it is.
            print("  \(fixture.name)")
            for counting in WordErrorRate.Counting.allCases {
                let rate = WordErrorRate(
                    heard: heard.text, against: fixture.reference, counting: counting)
                print("    \(AccuracyCeiling.committed(for: counting).measuring): \(rate)")
                measured[counting, default: []].append(rate)
            }
        }

        for counting in WordErrorRate.Counting.allCases {
            Self.check(
                WordErrorRate(totalling: measured[counting] ?? []),
                against: AccuracyCeiling.committed(for: counting),
                over: fixtures.count)
        }
    }

    @Test("A word the Engine gets wrong, corrected once, comes out right — and nothing else moves")
    func aWordTheEngineGetsWrongCorrectedOnceComesOutRight() async throws {
        // The mechanism ADR-0014 chose, proved the way it says to prove it: one
        // Spelling, and the fixtures the bare Engine gets that word wrong in
        // coming out right. Not by moving a Ceiling, which watches the bare
        // Engine.
        //
        // The second half of the test is the more important one. A Spelling
        // that put the word in everywhere would also put it in here, and would
        // be exactly the rule with no ears that ADR-0014 rejects — so the whole
        // Corpus is measured both ways, and reading a Spelling has to make
        // Cheppu more right rather than merely different.
        let fixtures = try AccuracyFixture.committed()
        let bare = try Self.engine()
        let taught = try Self.engine(reading: Spellings([Self.provingSpelling]))

        try await bare.downloadEngine { _ in }
        try await taught.downloadTheSpellingsPart { _ in }

        var measured: [WordErrorRate.Counting: (bare: [WordErrorRate], taught: [WordErrorRate])] =
            [:]

        for fixture in fixtures {
            let audio = try fixture.audio()
            let heardBare = try await bare.transcribe(audio).text
            let heardTaught = try await taught.transcribe(audio).text

            print("  \(fixture.name)")
            print("    bare:   \(heardBare)")
            print("    taught: \(heardTaught)")

            if Self.getsTheProvingWordWrong.contains(fixture.name) {
                #expect(
                    !heardBare.contains(Self.provingSpelling.text),
                    """
                    the bare Engine now spells “\(Self.provingSpelling.text)” right in \
                    \(fixture.name), so this fixture no longer proves anything. Pick a word it \
                    still gets wrong, or drop this fixture from the list.
                    """)
                #expect(
                    heardTaught.contains(Self.provingSpelling.text),
                    """
                    the Spelling “\(Self.provingSpelling.text)” was not put back into \
                    \(fixture.name), where the bare Engine gets that word wrong. Either the \
                    second pass did not run — the part of the Engine that reads Spellings is \
                    fetched by this test — or the rescorer no longer finds the acoustic \
                    evidence for it.
                    """)
            }

            for counting in WordErrorRate.Counting.allCases {
                measured[counting, default: ([], [])].bare.append(
                    WordErrorRate(heard: heardBare, against: fixture.reference, counting: counting))
                measured[counting, default: ([], [])].taught.append(
                    WordErrorRate(
                        heard: heardTaught, against: fixture.reference, counting: counting))
            }
        }

        for counting in WordErrorRate.Counting.allCases {
            let both = measured[counting] ?? ([], [])
            let bareRate = WordErrorRate(totalling: both.bare)
            let taughtRate = WordErrorRate(totalling: both.taught)
            print(
                "\(AccuracyCeiling.committed(for: counting).measuring): "
                    + "bare \(bareRate), with one Spelling \(taughtRate)")

            #expect(
                taughtRate.rate <= bareRate.rate,
                """
                reading one Spelling made the Corpus worse on \
                \(AccuracyCeiling.committed(for: counting).measuring): \
                \(WordErrorRate.percentage(taughtRate.rate)) against \
                \(WordErrorRate.percentage(bareRate.rate)) bare. A Spelling is put in only \
                where the sound supports it; a pass that is putting it in anywhere else has \
                become the replacement rule ADR-0014 rejects.
                """)
        }
    }

    /// One measurement against the ceiling committed for it, said out loud
    /// either way.
    ///
    /// The rate is printed on a green run as well as a red one, because the
    /// margin is the interesting part: a corpus sitting just under its ceiling
    /// is a different situation from one sitting well below it, and only the
    /// number says which.
    private static func check(
        _ measured: WordErrorRate, against ceiling: AccuracyCeiling.MeasuredOnce, over fixtures: Int
    ) {
        print(
            """
            \(ceiling.measuring), over \(fixtures) fixtures: \(measured)
              ceiling \(WordErrorRate.percentage(ceiling.ceiling)) — \
            \(WordErrorRate.percentage(ceiling.rate)) first measured on \(ceiling.chip), \
            plus \(WordErrorRate.percentage(ceiling.margin))
            """)

        #expect(
            measured.rate <= ceiling.ceiling,
            """
            accuracy has regressed on \(ceiling.measuring): \
            \(WordErrorRate.percentage(measured.rate)) against a ceiling of \
            \(WordErrorRate.percentage(ceiling.ceiling)). Either the Engine got worse, which is \
            what this test exists to catch, or a fixture was added that is harder than the ones \
            the ceiling was measured on — in which case raise it deliberately and say so in \
            AccuracyCeiling.
            """)
    }

}

/// That the corpus is a corpus: every fixture has both its halves, and
/// between them they exercise the speech the author actually produces.
///
/// Not behind `CHEPPU_ACCURACY`, because none of it loads the Engine and all of
/// it fails in seconds. A fixture committed without its reference should be
/// caught by the run that added it rather than by the nightly that finally
/// downloads Parakeet.
@Suite("Accuracy fixtures")
struct AccuracyFixtureTests {
    /// The three kinds of speech the corpus has to cover, named as the files
    /// are named, so that the coverage is a fact about the repository rather
    /// than a claim in a comment.
    private static let mustCover = ["technical-terms", "proper-nouns", "long-form-dictation"]

    /// What counts as long-form: long enough that a paragraph of it exists, and
    /// long enough that one misheard word is not the whole of the fixture's
    /// rate.
    private static let longForm = 150

    @Test("Every fixture has both halves")
    func everyFixtureHasItsAudioAndItsReference() throws {
        #expect(throws: Never.self) { try AccuracyFixture.committed() }
    }

    @Test("The corpus covers technical terms, proper nouns and long-form dictation")
    func theCorpusCoversTechnicalTermsProperNounsAndLongFormDictation() throws {
        let committed = Set(try AccuracyFixture.committed().map(\.name))

        for kind in Self.mustCover {
            #expect(
                committed.contains(kind),
                """
                no \(kind).wav in the corpus. The ceiling only means something if the fixtures \
                exercise the speech the author actually produces; add one with \
                Scripts/add-an-accuracy-fixture.sh.
                """)
        }
    }

    @Test("The long-form fixture is actually long")
    func theLongFormFixtureIsActuallyLong() throws {
        let fixtures = try AccuracyFixture.committed()
        let longForm = try #require(fixtures.first { $0.name == "long-form-dictation" })
        let words = WordErrorRate.words(in: longForm.reference).count

        #expect(
            words >= Self.longForm,
            "long-form-dictation is \(words) words, which is not long-form dictation")
    }

    @Test("Every fixture is at what the Engine hears in")
    func everyFixtureIsAtWhatTheEngineHearsIn() throws {
        // Reads the audio, which is the only thing that can answer this, and is
        // still far cheaper than loading Parakeet.
        for fixture in try AccuracyFixture.committed() {
            let audio = try fixture.audio()
            #expect(audio.sampleRate == AccuracyFixture.sampleRate)
            #expect(!audio.samples.isEmpty, "\(fixture.name).wav has no audio in it")
        }
    }
}

/// What the user taught Cheppu, for a suite that commits it rather than
/// correcting a History entry to get there.
private struct WhatTheUserTaughtIt: SpellingsPort {
    let taught: Spellings

    init(_ taught: Spellings) {
        self.taught = taught
    }

    func spellings() async -> Spellings { taught }
}
