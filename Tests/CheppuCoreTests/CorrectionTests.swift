import Testing

@testable import CheppuCore

// What a Correction teaches, and what it deliberately does not. This is the
// whole of the diff — the Engine is not here, no file is written, and nothing
// is downloaded — because what a changed span is worth is a decision, and the
// core is where decisions are made (ADR-0014).
@Suite("Correction")
struct CorrectionTests {
    private static func correcting(_ was: String, to now: String) -> Correction {
        Correction(of: FinalText(was), to: FinalText(now))
    }

    private static func spellings(_ was: String, _ now: String) -> [String] {
        correcting(was, to: now).spellings.map(\.text)
    }

    @Test("The entry keeps what the user typed")
    func theEntryKeepsWhatTheUserTyped() {
        let correction = Self.correcting("I said chepo again.", to: "I said Cheppu again.")

        #expect(correction.corrected == FinalText("I said Cheppu again."))
    }

    @Test("Clicking into a row and out of it again changes nothing and teaches nothing")
    func clickingIntoARowAndOutOfItAgainChangesNothingAndTeachesNothing() {
        let said = FinalText("I said Cheppu again.")
        let correction = Correction(of: said, to: said)

        #expect(!correction.changes(said))
        #expect(correction.spellings.isEmpty)
    }

    @Test("One word fixed is one Spelling, written the way the user wants it")
    func oneWordFixedIsOneSpelling() {
        // The word every user of this app will say, and the one the bare Engine
        // gets wrong in two fixtures out of three.
        #expect(Self.spellings("I said chepo again.", "I said Cheppu again.") == ["Cheppu"])
    }

    @Test("A Spelling keeps the word and not the sentence it was lifted out of")
    func aSpellingKeepsTheWordAndNotTheSentenceItWasLiftedOutOf() {
        // The span the user changed carries whatever punctuation ended the
        // clause it sat in. The comma belongs to the sentence.
        #expect(Self.spellings("Well, chepo, obviously.", "Well, Cheppu, obviously.") == ["Cheppu"])
    }

    @Test("A phrase of up to three words is one Spelling")
    func aPhraseOfUpToThreeWordsIsOneSpelling() {
        #expect(
            Self.spellings("I use chip you daily.", "I use Cheppu daily.") == ["Cheppu"])
        #expect(
            Self.spellings("the swift package manager", "the Swift Package Manager")
                == ["Swift Package Manager"])
    }

    @Test("Two words fixed in one edit are two Spellings")
    func twoWordsFixedInOneEditAreTwoSpellings() {
        #expect(
            Self.spellings("ruthik wrote chepo", "Hruthik wrote Cheppu")
                == ["Hruthik", "Cheppu"])
    }

    @Test("A sentence reworded teaches nothing")
    func aSentenceRewordedTeachesNothing() {
        // Four words for four. Somebody rewriting what they said is not
        // somebody telling Cheppu how a word is spelt.
        #expect(
            Self.spellings(
                "I will be there in a minute", "I am on my way over now"
            ).isEmpty)
    }

    @Test("A row emptied teaches nothing")
    func aRowEmptiedTeachesNothing() {
        #expect(Self.spellings("Something I would rather forget.", "").isEmpty)
    }

    @Test("Words put in where there were none teach nothing")
    func wordsPutInWhereThereWereNoneTeachNothing() {
        // There is no sound in the audio for a word the Engine never heard, so
        // there is nothing for the second pass to find. A Spelling here would
        // be a word Cheppu was waiting for and would never place.
        #expect(Self.spellings("I said it.", "I said it yesterday.").isEmpty)
    }

    @Test("A word too short to spot teaches nothing")
    func aWordTooShortToSpotTeachesNothing() {
        // Both sides are measured. FluidAudio declines to spot a term shorter
        // than three characters, and "to" made "too" is the user fixing a typo
        // rather than teaching Cheppu a word (ADR-0014).
        #expect(Self.spellings("I went to far.", "I went too far.").isEmpty)
        #expect(Self.spellings("or it does.", "VR it does.").isEmpty)
    }

    @Test("A Spelling of three letters is worth keeping")
    func aSpellingOfThreeLettersIsWorthKeeping() {
        #expect(Self.spellings("the sea es of it", "the SES of it") == ["SES"])
    }

    @Test("Nothing of what the Engine heard survives the Correction")
    func nothingOfWhatTheEngineHeardSurvivesTheCorrection() {
        // A Spelling holds the word the user wants and no memory of what it
        // replaced, which is what stops it ever becoming a rule that swaps one
        // string for another (ADR-0014).
        let correction = Self.correcting("I said chepo again.", to: "I said Cheppu again.")

        #expect(correction.spellings.map(\.text) == ["Cheppu"])
        #expect(!correction.corrected.text.contains("chepo"))
    }

    @Test("A Correction in the middle of a long entry reads only what moved")
    func aCorrectionInTheMiddleOfALongEntryReadsOnlyWhatMoved() {
        let long = Array(repeating: "the engine heard every word of this", count: 40)
            .joined(separator: " ")

        #expect(Self.spellings("\(long) chepo \(long)", "\(long) Cheppu \(long)") == ["Cheppu"])
    }
}

// The bounds on what a Correction may leave behind, asked of the word itself.
// They live on `Spelling` rather than in the diff so that a word read back off
// the disk is held to them too.
@Suite("Spelling")
struct SpellingTests {
    @Test("A word Cheppu could listen for is a Spelling")
    func aWordCheppuCouldListenForIsASpelling() {
        #expect(Spelling("Cheppu")?.text == "Cheppu")
        #expect(Spelling("event tap")?.text == "event tap")
        #expect(Spelling("Swift Package Manager")?.text == "Swift Package Manager")
    }

    @Test("A Spelling is trimmed of everything that is not the word")
    func aSpellingIsTrimmedOfEverythingThatIsNotTheWord() {
        #expect(Spelling("  Cheppu,  ")?.text == "Cheppu")
        #expect(Spelling("“Cheppu”")?.text == "Cheppu")
        #expect(Spelling("don't")?.text == "don't")
        #expect(Spelling("hand-off")?.text == "hand-off")
    }

    @Test("Nothing Cheppu could not ask the Engine to hear is a Spelling")
    func nothingCheppuCouldNotAskTheEngineToHearIsASpelling() {
        #expect(Spelling("") == nil)
        #expect(Spelling("  ") == nil)
        #expect(Spelling(",") == nil)
        #expect(Spelling("or") == nil)
        #expect(Spelling("a whole sentence of words") == nil)
    }
}

// A set of words with no memory of what each replaced, which is what makes two
// Spellings for one sound something the Engine chooses between rather than a
// conflict anybody has to resolve.
@Suite("Spellings")
struct SpellingsTests {
    private static func spelling(_ text: String) -> Spelling {
        Spelling(text)!
    }

    @Test("A user who has never corrected anything has no Spellings")
    func aUserWhoHasNeverCorrectedAnythingHasNoSpellings() {
        #expect(Spellings().isEmpty)
    }

    @Test("Spellings are listed in an order a word can be looked up in")
    func spellingsAreListedInAnOrderAWordCanBeLookedUpIn() {
        let spellings = Spellings().adding(
            [Self.spelling("Cheppu"), Self.spelling("altimeter"), Self.spelling("Hruthik")])

        #expect(spellings.entries.map(\.text) == ["altimeter", "Cheppu", "Hruthik"])
    }

    @Test("Teaching Cheppu the same word twice teaches it once")
    func teachingCheppuTheSameWordTwiceTeachesItOnce() {
        let spellings = Spellings()
            .adding([Self.spelling("Cheppu")])
            .adding([Self.spelling("Cheppu")])

        #expect(spellings.count == 1)
    }

    @Test("Two Spellings for one sound both exist, and neither is a conflict")
    func twoSpellingsForOneSoundBothExist() {
        // The Engine takes the closer; the user removes the other. Nothing here
        // detects or reports anything (ADR-0014).
        let spellings = Spellings().adding([Self.spelling("Cheppu"), Self.spelling("Cheppo")])

        #expect(spellings.count == 2)
    }

    @Test("A Spelling suspected of misfiring is removed one at a time")
    func aSpellingSuspectedOfMisfiringIsRemovedOneAtATime() {
        let spellings = Spellings()
            .adding([Self.spelling("Cheppu"), Self.spelling("Hruthik")])
            .removing(Self.spelling("Cheppu"))

        #expect(spellings.entries.map(\.text) == ["Hruthik"])
    }
}
