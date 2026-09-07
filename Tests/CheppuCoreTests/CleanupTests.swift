import Testing

@testable import CheppuCore

// Cleanup is a pure function: a Raw Transcript and its word timings in, Final
// Text out. These tests say what the user reads, given what the Engine heard
// and which switches are on. Nothing here has a clock, a file or a model
// anywhere near it, because neither does the thing under test.
@Suite("Cleanup")
struct CleanupTests {
    /// A Raw Transcript of words spoken one after another with nothing worth
    /// calling a pause between them, which is what the Engine hands back for an
    /// ordinary sentence.
    ///
    /// - Parameters:
    ///   - gap: how long the speaker stopped for, where they stopped.
    ///   - pausedAfter: the word they stopped after, written as it appears in
    ///     the text. Every other word follows the one before it with no pause
    ///     worth the name.
    private func spoken(
        _ text: String, pausingFor gap: Duration = .zero, after pausedAfter: String = ""
    ) -> RawTranscript {
        var words: [WordTiming] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            let start =
                words.last.map { $0.end + ($0.word == pausedAfter ? gap : .milliseconds(80)) }
                ?? .zero
            words.append(WordTiming(word: String(word), start: start, end: start + .milliseconds(300)))
        }
        return RawTranscript(text: text, words: words)
    }

    /// One rule on and the other two off, so that what a test asserts is that
    /// rule and nothing else.
    private static let onlyFillerWords = CleanupRules(
        removesFillerWords: true, capitalisesSentences: false, breaksParagraphs: false)

    // MARK: - Filler Words

    @Test("Filler Words are dropped, and the space they left with them")
    func fillerWordsAreDropped() {
        let cleanup = Cleanup(Self.onlyFillerWords)

        // A Filler Word at the front takes the space after it, so the sentence
        // starts where the user meant it to.
        #expect(cleanup.finalText(from: spoken("um so I was thinking")).text == "so I was thinking")

        // One in the middle takes the space that followed it, so the words on
        // either side of it are left separated exactly as they would have been
        // had it never been said.
        #expect(cleanup.finalText(from: spoken("I was uh thinking")).text == "I was thinking")

        // And one at the end has no word after it to separate from, so the
        // word before it takes over what the Filler Word was carrying and no space
        // is left dangling.
        #expect(cleanup.finalText(from: spoken("I was thinking uh")).text == "I was thinking")
    }

    @Test("A Filler Word is dropped with the punctuation the Engine hung on it")
    func aFillerWordIsDroppedWithItsPunctuation() {
        let cleanup = Cleanup(Self.onlyFillerWords)

        // Parakeet writes the pause it heard as a comma around a Filler Word,
        // so one removed without its own punctuation would leave the comma
        // standing where nothing was said.
        #expect(cleanup.finalText(from: spoken("So, um, I think")).text == "So, I think")
        #expect(cleanup.finalText(from: spoken("um, so I think")).text == "so I think")
    }

    @Test("A Filler Word never takes the sentence's full stop with it")
    func aFillerWordNeverTakesTheSentencesFullStopWithIt() {
        let cleanup = Cleanup(Self.onlyFillerWords)

        // Parakeet writes the pause it heard as a comma in front of the Filler Word
        // and puts the sentence's own full stop after it. The comma stood in
        // for the pause and goes with it; the full stop is where the sentence
        // ended, and it moves back onto the word the user actually finished on.
        #expect(
            cleanup.finalText(from: spoken("I don't know, uh. next thing happened.")).text
                == "I don't know. next thing happened.")

        // A word that had already finished its sentence keeps the one it has
        // rather than being given a second.
        #expect(
            cleanup.finalText(from: spoken("I went to the U.S. uh. then home")).text
                == "I went to the U.S. then home")

        // A Filler Word that opened the Dictation has no word to give a full
        // stop back to, and the sentence it ended was only the filler itself.
        #expect(cleanup.finalText(from: spoken("uh. I think")).text == "I think")
    }

    @Test("A Filler Word at the end of a sentence leaves the other two rules their work")
    func aFillerWordAtTheEndOfASentenceLeavesTheOtherTwoRulesTheirWork() {
        // The sentence still ended where the user ended it, so the next one is
        // still capitalised and a long pause after it still breaks a paragraph.
        // One rule must never quietly switch off the other two.
        let heard = RawTranscript(
            text: "i don't know, uh. next thing happened",
            words: [
                WordTiming(word: "i", start: .zero, end: .milliseconds(200)),
                WordTiming(word: "don't", start: .milliseconds(300), end: .milliseconds(500)),
                WordTiming(word: "know,", start: .milliseconds(600), end: .milliseconds(900)),
                WordTiming(word: "uh.", start: .milliseconds(1_000), end: .milliseconds(1_200)),
                WordTiming(word: "next", start: .milliseconds(3_500), end: .milliseconds(3_700)),
                WordTiming(word: "thing", start: .milliseconds(3_800), end: .milliseconds(4_000)),
                WordTiming(word: "happened", start: .milliseconds(4_100), end: .milliseconds(4_400)),
            ]
        )

        #expect(
            Cleanup(.all).finalText(from: heard).text == "I don't know.\nNext thing happened")
    }

    @Test("A Filler Word is dropped however it was capitalised")
    func aFillerWordIsDroppedHoweverItWasCapitalised() {
        let cleanup = Cleanup(Self.onlyFillerWords)

        #expect(cleanup.finalText(from: spoken("Um I think")).text == "I think")
        #expect(cleanup.finalText(from: spoken("UM I think")).text == "I think")
    }

    @Test("Only whole words from the committed list are dropped")
    func onlyWholeWordsFromTheCommittedListAreDropped() {
        let cleanup = Cleanup(Self.onlyFillerWords)

        // A word that merely begins with one is a word the user said.
        #expect(cleanup.finalText(from: spoken("the umbrella is uhuru")).text == "the umbrella is uhuru")

        // And so is one that carries meaning. Cleanup drops hesitation, not
        // the words around it: "hmm" is doubt and "ah" is recognition, and a
        // user who said either meant it.
        #expect(cleanup.finalText(from: spoken("hmm, ah, I see")).text == "hmm, ah, I see")
    }

    @Test("A Dictation that was nothing but a Filler Word comes back empty")
    func aDictationThatWasNothingButAFillerWordComesBackEmpty() {
        // Which is what makes it a Discard: there is nothing to insert and
        // nothing worth keeping, and the machine ends the Dictation silently
        // rather than moving the user's cursor for a stray tap.
        #expect(Cleanup(Self.onlyFillerWords).finalText(from: spoken("um")).text.isEmpty)
    }

    private static let onlyCapitals = CleanupRules(
        removesFillerWords: false, capitalisesSentences: true, breaksParagraphs: false)

    // MARK: - Sentence capitalisation

    @Test("A sentence starts with a capital letter")
    func aSentenceStartsWithACapitalLetter() {
        let cleanup = Cleanup(Self.onlyCapitals)

        // The first word of the Dictation, and the first word after each thing
        // that ended a sentence.
        #expect(
            cleanup.finalText(from: spoken("that is one thought. the next one? and a third!"))
                .text == "That is one thought. The next one? And a third!")
    }

    @Test("Only the start of a sentence is capitalised")
    func onlyTheStartOfASentenceIsCapitalised() {
        let cleanup = Cleanup(Self.onlyCapitals)

        // Not every word, and not the letters inside one: Cleanup capitalises
        // where a sentence begins and leaves the rest exactly as it was heard.
        #expect(
            cleanup.finalText(from: spoken("i met bob at the CIA, and iPhones were mentioned")).text
                == "I met bob at the CIA, and iPhones were mentioned")
    }

    @Test("A sentence that already starts with a capital is left alone")
    func aSentenceThatAlreadyStartsWithACapitalIsLeftAlone() {
        #expect(
            Cleanup(Self.onlyCapitals).finalText(from: spoken("This is fine. So is this.")).text
                == "This is fine. So is this.")
    }

    @Test("A sentence that opens with a quotation mark is capitalised at its first letter")
    func aSentenceThatOpensWithAQuotationMarkIsCapitalisedAtItsFirstLetter() {
        let cleanup = Cleanup(Self.onlyCapitals)

        // The capital belongs on the first letter rather than the first
        // character, and a sentence that ended inside quotation marks still
        // ended.
        #expect(
            cleanup.finalText(from: spoken("she said \"stop that.\" then she left.")).text
                == "She said \"stop that.\" Then she left.")
    }

    @Test("A number or a symbol at the start of a sentence is left as it was heard")
    func aNumberOrASymbolAtTheStartOfASentenceIsLeftAsItWasHeard() {
        // There is no capital form of "3", and Cleanup does not go looking for
        // the next word that has one: capitalising something further along
        // would be a rewrite rather than a rule the user can predict.
        #expect(
            Cleanup(Self.onlyCapitals).finalText(from: spoken("3 of them arrived. then more.")).text
                == "3 of them arrived. Then more.")
    }

    private static let onlyParagraphBreaks = CleanupRules(
        removesFillerWords: false, capitalisesSentences: false, breaksParagraphs: true)

    // MARK: - Paragraph Breaks

    @Test("A Paragraph Break goes where a long pause followed a finished sentence")
    func aParagraphBreakGoesWhereALongPauseFollowedAFinishedSentence() {
        let heard = spoken(
            "that is one thought. the next one", pausingFor: .seconds(2), after: "thought.")

        // The speaker finished a sentence and then stopped for two seconds,
        // which is someone starting a new thought rather than drawing breath.
        // The space between the two sentences becomes the break, so no space is
        // added and none is left over.
        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: heard).text
                == "that is one thought.\nthe next one")
    }

    @Test("A long pause in the middle of a sentence breaks nothing")
    func aLongPauseInTheMiddleOfASentenceBreaksNothing() {
        let heard = spoken(
            "that is one thought and the next", pausingFor: .seconds(4), after: "thought")

        // Someone stopped mid-sentence to think. Both halves are one sentence,
        // and a break through the middle of it would be a paragraph the user
        // never meant.
        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: heard).text
                == "that is one thought and the next")
    }

    @Test("A pause of a second after a finished sentence is not long enough to break a paragraph")
    func aPauseOfASecondIsNotLongEnoughToBreakAParagraph() {
        // The committed threshold is a second, and it has to be exceeded: a
        // second is where someone drawing breath between two sentences of the
        // same paragraph still is.
        let drawingBreath = spoken(
            "one thought. the next", pausingFor: .seconds(1), after: "thought.")
        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: drawingBreath).text
                == "one thought. the next")

        let aNewThought = spoken(
            "one thought. the next", pausingFor: .milliseconds(1_200), after: "thought.")
        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: aNewThought).text
                == "one thought.\nthe next")
    }

    @Test("A sentence that ended inside quotation marks can still end a paragraph")
    func aSentenceThatEndedInsideQuotationMarksCanStillEndAParagraph() {
        let heard = spoken(
            "she said \"stop that.\" then she left", pausingFor: .seconds(2), after: "that.\"")

        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: heard).text
                == "she said \"stop that.\"\nthen she left")
    }

    @Test("Word timings that do not line up with the text place no Paragraph Break")
    func wordTimingsThatDoNotLineUpWithTheTextPlaceNoParagraphBreak() {
        // The Engine reports the text and the timings separately, and a
        // Paragraph Break is placed between two particular words. Where the two
        // do not describe the same words, Cheppu does not guess which gap it is
        // holding: a newline in the wrong place is a paragraph the user has to
        // notice and undo.
        let disagreeing = RawTranscript(
            text: "one thought. the next",
            words: [
                WordTiming(word: "one", start: .zero, end: .milliseconds(300)),
                WordTiming(word: "thought.", start: .milliseconds(400), end: .milliseconds(700)),
                WordTiming(word: "next", start: .seconds(4), end: .milliseconds(4_300)),
            ]
        )

        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: disagreeing).text
                == "one thought. the next")
    }

    @Test("A Raw Transcript with no timings at all breaks no paragraphs")
    func aRawTranscriptWithNoTimingsAtAllBreaksNoParagraphs() {
        let untimed = RawTranscript(text: "one thought. the next", words: [])

        #expect(
            Cleanup(Self.onlyParagraphBreaks).finalText(from: untimed).text
                == "one thought. the next")
    }

    @Test("The pause a Paragraph Break is measured across is the whole silence the Filler Word sat in")
    func thePauseIsMeasuredAcrossARemovedFiller() {
        // Neither half of this pause is long enough on its own, and together
        // they are: the speaker stopped for two seconds and filled some of it
        // with an "um". What they did is start a new paragraph, and the Filler Word
        // they said while doing it does not change that.
        let heard = RawTranscript(
            text: "one thought. um the next",
            words: [
                WordTiming(word: "one", start: .zero, end: .milliseconds(300)),
                WordTiming(word: "thought.", start: .milliseconds(400), end: .milliseconds(700)),
                WordTiming(word: "um", start: .milliseconds(1_500), end: .milliseconds(1_700)),
                WordTiming(word: "the", start: .milliseconds(2_600), end: .milliseconds(2_800)),
                WordTiming(word: "next", start: .milliseconds(2_900), end: .milliseconds(3_200)),
            ]
        )

        let cleanup = Cleanup(
            CleanupRules(
                removesFillerWords: true, capitalisesSentences: false, breaksParagraphs: true))

        #expect(cleanup.finalText(from: heard).text == "one thought.\nthe next")
    }

    // MARK: - The three switches together

    @Test(
        "Every combination of the three switches reads the way its rules say it should",
        arguments: [
            // Off, which is the Raw Transcript and nothing else.
            (false, false, false, "um, that is one thought. the next one"),
            (true, false, false, "that is one thought. the next one"),
            (false, true, false, "Um, that is one thought. The next one"),
            (false, false, true, "um, that is one thought.\nthe next one"),
            (true, true, false, "That is one thought. The next one"),
            (true, false, true, "that is one thought.\nthe next one"),
            (false, true, true, "Um, that is one thought.\nThe next one"),
            (true, true, true, "That is one thought.\nThe next one"),
        ]
    )
    func everyCombinationOfTheThreeSwitches(
        combination: (fillers: Bool, capitals: Bool, breaks: Bool, reads: String)
    ) {
        // Each rule does its own work and none of the others'. A user who keeps
        // the ones that help and turns off the ones that do not gets exactly
        // what they asked for, and nothing decided for them by which other
        // switches they left on.
        let cleanup = Cleanup(
            CleanupRules(
                removesFillerWords: combination.fillers,
                capitalisesSentences: combination.capitals,
                breaksParagraphs: combination.breaks
            )
        )

        #expect(cleanup.finalText(from: ARawTranscript.saidWithAPause).text == combination.reads)
    }

    @Test("With every rule off, the Final Text is the Raw Transcript byte for byte")
    func withEveryRuleOffTheFinalTextIsTheRawTranscript() {
        // Everything the three rules would otherwise touch, in one transcript:
        // a Filler Word, a lower-case sentence start, and a pause long enough
        // to mean a new paragraph.
        let heard = RawTranscript(
            text: "  um, that is one thought.  the next one\n",
            words: [
                WordTiming(word: "um,", start: .zero, end: .milliseconds(200)),
                WordTiming(word: "that", start: .milliseconds(300), end: .milliseconds(500)),
                WordTiming(word: "is", start: .milliseconds(500), end: .milliseconds(700)),
                WordTiming(word: "one", start: .milliseconds(700), end: .milliseconds(900)),
                WordTiming(word: "thought.", start: .milliseconds(900), end: .milliseconds(1_400)),
                WordTiming(word: "the", start: .milliseconds(4_000), end: .milliseconds(4_200)),
                WordTiming(word: "next", start: .milliseconds(4_200), end: .milliseconds(4_500)),
                WordTiming(word: "one", start: .milliseconds(4_500), end: .milliseconds(4_800)),
            ]
        )

        // Off is a real option and not a softer version of on: not a space
        // moved, not a letter changed.
        #expect(Cleanup(.off).finalText(from: heard).text == heard.text)
    }

    @Test("Every rule reads back through the name it is set by")
    func everyRuleReadsBackThroughTheNameItIsSetBy() {
        // The name is how the Settings window asks which way a switch is set. A
        // name that pointed at the wrong field would be a row saying one thing
        // and showing another, and nothing the user could see would give it
        // away.
        for rule in CleanupRule.allCases {
            #expect(CleanupRules.all[rule])
            #expect(!CleanupRules.off[rule])
        }

        #expect(!Self.onlyCapitals[.removesFillerWords])
        #expect(Self.onlyCapitals[.capitalisesSentences])
        #expect(!Self.onlyCapitals[.breaksParagraphs])
    }
}
