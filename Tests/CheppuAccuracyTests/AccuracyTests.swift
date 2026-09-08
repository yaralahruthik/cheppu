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
    /// The Engine where the machine already keeps it, so that running this
    /// twice does not fetch it twice.
    private static func engine() throws -> ParakeetEngine {
        ParakeetEngine(
            directory: EngineFiles.directory(
                inApplicationSupport: try EngineFiles.defaultApplicationSupport()),
            configuration: .default
        )
    }

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
