/// How wrong the Engine is allowed to be before the run goes red.
///
/// Not an aspiration, and not a number anybody picked because it sounded good.
/// Each ceiling is what the Engine actually measured on this corpus the first
/// time it ran, plus a small absolute margin, so that the test catches Cheppu
/// getting worse rather than asserting a standard it has never met. A ceiling
/// set below where the Engine already is would be red from the day it landed
/// and would be raised rather than read; one set far above would never go red
/// at all.
///
/// There are two of them because a red run is only actionable if it says which
/// question it answered. Parakeet writing "core ML" where it used to write
/// "CoreML" is not the same event as Parakeet no longer hearing the word, and a
/// single number would report them identically.
///
/// Raising either is allowed and is meant to be uncomfortable: it means the
/// Engine got worse, which is the regression this exists to catch, or the
/// corpus grew harder, which is a fixture added deliberately. Lowering one
/// after a genuine improvement is the other half of the same discipline — a
/// ceiling left far above an Engine that has got better is a test that has
/// stopped measuring anything.
enum AccuracyCeiling {
    /// What the Engine heard, forgiving the ways two faithful transcripts of
    /// the same sounds are written differently.
    ///
    /// The number to read if you want to know whether Cheppu understands the
    /// person using it, and the one comparable with a published
    /// speech-recognition rate.
    static let asSpoken = MeasuredOnce(
        measuring: "what the Engine heard",
        rate: 0.0381,
        margin: 0.02,
        on: "8 September 2026",
        chip: "Apple M4 Pro",
        engine: "Parakeet TDT v3 int8 via FluidAudio 0.15.6",
        over: """
            367 words across the three fixtures. What is left at this rate is the Engine \
            genuinely getting a word wrong: "Cheppu" heard as "chepo" every time it is said, \
            "Hruthik" as "ruthik", "Sequoia" as "sequa", "event tap" as "event tab".
            """
    )

    /// What the user reads, forgiving nothing.
    ///
    /// Higher than the rate above, and legitimately so: it counts every place
    /// the inserted text differs from what was written down, including the ones
    /// nobody would call a mishearing — "3" for "three", "core ml" for
    /// "CoreML", "you're" for "you are", "quantized" for "quantised". Those are
    /// still words the user goes back and fixes, so they are still worth a
    /// ceiling; they are simply a different problem, and mostly Cleanup's to
    /// solve rather than the Engine's.
    static let asWritten = MeasuredOnce(
        measuring: "what the user reads",
        rate: 0.0929,
        margin: 0.02,
        on: "8 September 2026",
        chip: "Apple M4 Pro",
        engine: "Parakeet TDT v3 int8 via FluidAudio 0.15.6",
        over: """
            366 words across the three fixtures. Rather more than half of the gap from the rate \
            above is spelling convention rather than accuracy, which is why both are committed \
            rather than only this one.
            """
    )

    /// The ceiling committed for one of the two questions.
    ///
    /// Looked up rather than chosen at each call site, so that the label a run
    /// prints, the rate it compares against and the way it counted words cannot
    /// drift apart into three things kept in step by hand.
    static func committed(for counting: WordErrorRate.Counting) -> MeasuredOnce {
        switch counting {
        case .asSpoken: asSpoken
        case .asWritten: asWritten
        }
    }

    /// A measurement, with enough beside it that somebody reading this a year
    /// later can tell whether it still means anything.
    struct MeasuredOnce {
        /// Which question this one answers, in the words a run prints.
        let measuring: String

        /// The first measured rate, as a fraction rather than a percentage.
        ///
        /// Recorded separately from the ceiling so that the margin stays
        /// visible and the two cannot drift into one number nobody can explain.
        let rate: Double

        /// The margin over that measurement.
        ///
        /// Absolute rather than proportional, because a proportional margin on
        /// a low rate is no margin at all: four percent plus ten percent of
        /// itself leaves less room than one misheard word in a short fixture.
        /// Two points is roughly one word in fifty — wide enough that the
        /// Engine's own run-to-run variation and a CoreML compiler scheduling
        /// the graph differently on a different Apple Silicon runner do not
        /// turn into a red build, and narrow enough that a real regression
        /// cannot hide under it.
        let margin: Double

        /// The day it was measured.
        let on: String

        /// The chip it was measured on.
        ///
        /// Parakeet on CoreML is a different graph on different silicon, so a
        /// rate measured on one says little about another. This was measured on
        /// the author's own machine and is enforced on whatever Apple Silicon
        /// GitHub provides; the margin is what absorbs the difference, and the
        /// first CI run is what proves it does.
        let chip: String

        /// The Engine it was measured with.
        ///
        /// A FluidAudio bump is the likeliest reason a rate ever moves without
        /// anybody touching Cheppu, so the version belongs beside the number
        /// rather than only in `Package.resolved`.
        let engine: String

        /// What the corpus was at the time, so that a ceiling measured over
        /// three fixtures is not silently reused for thirty.
        let over: String

        /// What the run is measured against.
        var ceiling: Double { rate + margin }
    }
}
