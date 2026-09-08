import Testing

// The measurement itself, with no Engine anywhere near it. These run in the fast
// suite rather than behind `CHEPPU_ACCURACY`: they cost microseconds, and a
// harness whose arithmetic is wrong would report a rate nobody could act on.
@Suite("Word error rate")
struct WordErrorRateTests {
    private static func rate(heard: String, reference: String) -> WordErrorRate {
        WordErrorRate(heard: heard, against: reference)
    }

    @Test("A transcript word for word with what was said has no errors in it")
    func aTranscriptWordForWordWithWhatWasSaidHasNoErrorsInIt() {
        let measured = Self.rate(
            heard: "the words appear where your cursor is",
            reference: "the words appear where your cursor is")

        #expect(measured.errors == 0)
        #expect(measured.rate == 0)
        #expect(measured.referenceWords == 7)
    }

    @Test("A word heard as another word is one substitution")
    func aWordHeardAsAnotherWordIsOneSubstitution() {
        let measured = Self.rate(
            heard: "the words appear where your curser is",
            reference: "the words appear where your cursor is")

        #expect(measured.substitutions == 1)
        #expect(measured.deletions == 0)
        #expect(measured.insertions == 0)
        #expect(measured.rate == 1.0 / 7.0)
    }

    @Test("A word the Engine missed is one deletion")
    func aWordTheEngineMissedIsOneDeletion() {
        let measured = Self.rate(
            heard: "the words appear where cursor is",
            reference: "the words appear where your cursor is")

        #expect(measured.deletions == 1)
        #expect(measured.substitutions == 0)
        #expect(measured.insertions == 0)
    }

    @Test("A word the Engine invented is one insertion")
    func aWordTheEngineInventedIsOneInsertion() {
        let measured = Self.rate(
            heard: "the words appear right where your cursor is",
            reference: "the words appear where your cursor is")

        #expect(measured.insertions == 1)
        #expect(measured.substitutions == 0)
        #expect(measured.deletions == 0)
    }

    // The rate is errors over what was said, not over what was heard, so an
    // Engine that invents a hundred words is not rewarded with a bigger
    // denominator.
    @Test("More errors than there were words is a rate above one")
    func moreErrorsThanThereWereWordsIsARateAboveOne() {
        let measured = Self.rate(heard: "one two three four five six", reference: "silence here")

        #expect(measured.referenceWords == 2)
        #expect(measured.rate > 1)
    }

    @Test("Nothing heard at all is every word of the reference deleted")
    func nothingHeardAtAllIsEveryWordOfTheReferenceDeleted() {
        let measured = Self.rate(heard: "", reference: "the words appear")

        #expect(measured.deletions == 3)
        #expect(measured.rate == 1)
    }

    // MARK: - What the normaliser erases

    // Punctuation and case are Cleanup's business and are tested there. Counting
    // them here would report a comma as a misheard word and hide the ones that
    // matter.
    @Test("Punctuation and case are not accuracy")
    func punctuationAndCaseAreNotAccuracy() {
        let measured = Self.rate(
            heard: "The words appear, where your cursor is!",
            reference: "the words appear where your cursor is")

        #expect(measured.errors == 0)
    }

    @Test("A curly apostrophe is the same word as a straight one")
    func aCurlyApostropheIsTheSameWordAsAStraightOne() {
        #expect(Self.rate(heard: "it\u{2019}s here", reference: "it's here").errors == 0)
    }

    // Whether the Engine wrote a hyphen is a spelling choice, not a word it
    // failed to hear; "twenty-one" and "twenty one" are the same thing said.
    @Test("A hyphen is a word boundary on both sides of the comparison")
    func aHyphenIsAWordBoundaryOnBothSidesOfTheComparison() {
        let measured = Self.rate(heard: "twenty-one machines", reference: "twenty one machines")

        #expect(measured.errors == 0)
        #expect(measured.referenceWords == 3)
    }

    // A missing apostrophe is a different word on the screen, which is a word
    // the user has to go back and fix.
    @Test("A word missing its apostrophe is a substitution")
    func aWordMissingItsApostropheIsASubstitution() {
        #expect(Self.rate(heard: "dont stop", reference: "don't stop").substitutions == 1)
    }

    @Test("Runs of whitespace and newlines are not words")
    func runsOfWhitespaceAndNewlinesAreNotWords() {
        let measured = Self.rate(
            heard: "the words\n\n   appear\t\n", reference: "the words appear")

        #expect(measured.errors == 0)
        #expect(measured.referenceWords == 3)
    }

    // MARK: - Adding fixtures up

    // The rate over the corpus is every error over every word said, so a
    // ten-word fixture cannot weigh as much as two minutes of dictation.
    @Test("Fixtures add up by their errors and their words, not by their rates")
    func fixturesAddUpByTheirErrorsAndTheirWordsNotByTheirRates() {
        let short = Self.rate(heard: "wrong", reference: "right")
        let long = Self.rate(
            heard: "the words appear where your cursor is and nothing leaves the machine",
            reference: "the words appear where your cursor is and nothing leaves the machine")

        let together = WordErrorRate(totalling: [short, long])

        #expect(together.errors == 1)
        #expect(together.referenceWords == 13)
        #expect(together.rate == 1.0 / 13.0)
    }

    @Test("Nothing measured at all is a rate of nothing")
    func nothingMeasuredAtAllIsARateOfNothing() {
        let together = WordErrorRate(totalling: [])

        #expect(together.referenceWords == 0)
        #expect(together.rate == 0)
    }
}

// The same words, scored two ways. Counting as spoken forgives the ways two
// faithful transcripts of the same sounds can be written differently; counting
// as written forgives nothing, because a word the user has to go back and fix
// is a word the user has to go back and fix. Neither is the true one, which is
// why the harness commits a ceiling for each.
@Suite("Word error rate, as spoken")
struct SpokenWordErrorRateTests {
    private static func spoken(heard: String, reference: String) -> WordErrorRate {
        WordErrorRate(heard: heard, against: reference, counting: .asSpoken)
    }

    private static func written(heard: String, reference: String) -> WordErrorRate {
        WordErrorRate(heard: heard, against: reference, counting: .asWritten)
    }

    @Test("A number written in digits is the number that was said")
    func aNumberWrittenInDigitsIsTheNumberThatWasSaid() {
        #expect(Self.spoken(heard: "version 3", reference: "version three").errors == 0)
        #expect(Self.written(heard: "version 3", reference: "version three").errors == 1)
    }

    @Test("A compound the Engine split in two is one word either way")
    func aCompoundTheEngineSplitInTwoIsOneWordEitherWay() {
        #expect(Self.spoken(heard: "core ml runs", reference: "coreml runs").errors == 0)
        #expect(Self.spoken(heard: "fluidinference ships", reference: "fluid inference ships")
            .errors == 0)
        #expect(Self.written(heard: "core ml runs", reference: "coreml runs").errors > 0)
    }

    @Test("A contraction is the two words it stands for")
    func aContractionIsTheTwoWordsItStandsFor() {
        #expect(Self.spoken(heard: "you're talking", reference: "you are talking").errors == 0)
        #expect(Self.written(heard: "you're talking", reference: "you are talking").errors > 0)
    }

    @Test("An American spelling of a British word is the same word said")
    func anAmericanSpellingOfABritishWordIsTheSameWordSaid() {
        #expect(Self.spoken(heard: "quantized to int 8", reference: "quantised to int eight")
            .errors == 0)
        #expect(Self.written(heard: "quantized to int 8", reference: "quantised to int eight")
            .errors == 2)
    }

    // The whole point of forgiving the spellings is that what is left is the
    // Engine getting a word wrong, which no amount of normalising should hide.
    @Test("None of it forgives a word the Engine actually got wrong")
    func noneOfItForgivesAWordTheEngineActuallyGotWrong() {
        #expect(Self.spoken(heard: "chepo is listening", reference: "cheppu is listening")
            .substitutions == 1)
        #expect(Self.spoken(heard: "event tab", reference: "event tap").substitutions == 1)
        #expect(Self.spoken(heard: "fluid odio", reference: "fluidaudio").errors > 0)
    }

    @Test("Counting as spoken is never harsher than counting as written")
    func countingAsSpokenIsNeverHarsherThanCountingAsWritten() {
        let heard = "chepo resamples to 16 khz before the decoder"
        let said = "cheppu resamples to sixteen kilohertz before the decoder"

        #expect(Self.spoken(heard: heard, reference: said).errors
            <= Self.written(heard: heard, reference: said).errors)
    }
}
