/// The deterministic transformation of a Raw Transcript into Final Text.
///
/// A pure function: the words the Engine heard and when it heard them go in,
/// and what the user reads comes out. No clock, no file, no network, and never
/// a language model — Cleanup is a set of rules a user can predict from a
/// one-line description (`docs/product-experience.md` §8), which is what lets
/// them stop re-reading what Cheppu inserted.
///
/// It never rewrites, summarises or fixes grammar. Every rule either drops
/// something the user did not mean to say or changes whitespace and case, so
/// what is inserted can only ever be what they said.
public struct Cleanup: Sendable {
    /// The Filler Words Cleanup drops, committed here rather than made a
    /// setting (#1): a list the user could edit is one they would have to keep
    /// in their head to know what Cheppu did to their words.
    ///
    /// Only hesitation is on it. "hmm", "ah" and "eh" are not, and neither are
    /// "like" and "you know": each of those carries meaning, and a Cleanup that
    /// dropped one would turn what the user said into something they did not.
    /// The list errs towards leaving one in, because a Filler Word that
    /// survives is a word the user can delete and a word wrongly dropped is one
    /// they have to notice first.
    public static let fillerWords: Set<String> = [
        "um", "umm", "ummm", "uh", "uhh", "uhhh", "uhm", "erm",
    ]

    /// How long a silence after a finished sentence means the speaker started a
    /// new paragraph.
    ///
    /// A fixed constant rather than a setting (#1). A full second is longer
    /// than the breath anyone draws between two sentences of the same paragraph
    /// and shorter than the stop someone makes when they have finished a
    /// thought, so neither has to be performed carefully to be read correctly.
    ///
    /// It has to be exceeded rather than merely reached, which is what puts a
    /// speaker who is exactly on it in the paragraph they are already writing.
    public static let paragraphGap: Duration = .seconds(1)

    private let rules: CleanupRules

    public init(_ rules: CleanupRules) {
        self.rules = rules
    }

    /// What the user reads, from what the Engine heard.
    ///
    /// The rules run in a fixed order rather than in whichever order their
    /// switches happen to be listed: Filler Words go first, so that the
    /// sentence the next rule capitalises starts at the first word the user
    /// meant and the pause the third one measures is the whole of the silence a
    /// filler was said into.
    public func finalText(from transcript: RawTranscript) -> FinalText {
        var inPieces = RawTranscriptInPieces(transcript)
        if rules.removesFillerWords { removeFillerWords(from: &inPieces) }
        if rules.capitalisesSentences { capitaliseSentences(in: &inPieces) }
        if rules.breaksParagraphs { breakParagraphs(in: &inPieces) }
        return FinalText(inPieces.text)
    }

    /// Drops every Filler Word, and the space it left behind with it.
    ///
    /// The space that goes is the one after the word, so that the words either
    /// side of a filler are separated exactly as they would have been had it
    /// never been said. At the very end of a Dictation there is no word after
    /// it to be separated from, so the word before takes over whatever the
    /// filler was carrying — the Engine's trailing newline, usually — and no
    /// space is left dangling.
    private func removeFillerWords(from transcript: inout RawTranscriptInPieces) {
        for index in transcript.words.indices.reversed()
        where Cleanup.fillerWords.contains(transcript.words[index].spoken.lowercased()) {
            let filler = transcript.words[index]

            // A sentence that ended where the filler was said still ended
            // there. Its full stop moves back onto the word the user actually
            // finished on, in place of the comma the Engine wrote for the
            // pause, so that dropping a filler never costs the next sentence
            // its capital or the paragraph its break. One rule must not be able
            // to switch off the other two.
            if filler.endsASentence, index > 0, !transcript.words[index - 1].endsASentence {
                transcript.words[index - 1].endSentence(with: filler.closing)
            }

            if index == transcript.words.count - 1 && index > 0 {
                transcript.words[index - 1].following = filler.following
            }

            transcript.words.remove(at: index)
        }
    }

    /// Puts a capital letter on the first word of every sentence.
    ///
    /// A sentence starts at the first word of the Dictation and after every
    /// word that ended one. That is the whole rule, which is what makes it
    /// predictable: Cleanup is not reading the words, so "e.g." starts a
    /// sentence here and a name mid-sentence is left in whatever case it was
    /// heard. Nothing else about the word is touched — the letters after the
    /// first are the Engine's, so "iPhone" survives being at the front of a
    /// sentence.
    private func capitaliseSentences(in transcript: inout RawTranscriptInPieces) {
        var startsASentence = true
        for index in transcript.words.indices {
            if startsASentence { transcript.words[index].capitaliseFirstLetter() }
            startsASentence = transcript.words[index].endsASentence
        }
    }

    /// Turns the space after a finished sentence into a newline, where the
    /// speaker stopped there for longer than `paragraphGap`.
    ///
    /// Both halves are needed, and the sentence is the half that matters: a
    /// long silence is someone thinking as often as it is someone starting
    /// again, and only one that comes after a finished sentence is a paragraph.
    /// So a speaker who stops for four seconds in the middle of a sentence
    /// finishes it in the paragraph they started it in.
    ///
    /// The space between the two sentences becomes the break rather than being
    /// added to, which is what makes a Paragraph Break a newline and not a
    /// newline with a space hanging off it.
    private func breakParagraphs(in transcript: inout RawTranscriptInPieces) {
        for index in transcript.words.indices.dropLast() {
            guard
                let ending = transcript.words[index].timing,
                let beginning = transcript.words[index + 1].timing,
                beginning.start - ending.end > Cleanup.paragraphGap,
                transcript.words[index].endsASentence
            else { continue }

            transcript.words[index].following = "\n"
        }
    }
}

/// Which of the three Cleanup rules are on.
///
/// Each is a switch of its own, because a user who wants their Filler Words
/// dropped does not necessarily want their paragraphs broken, and either one
/// being wrong for them must not cost them the other two
/// (`docs/product-experience.md` §8).
public struct CleanupRules: Equatable, Sendable {
    /// Every rule on: what a Dictation does unless the user says otherwise.
    public static let all = CleanupRules(
        removesFillerWords: true, capitalisesSentences: true, breaksParagraphs: true)

    /// Every rule off, which leaves the Raw Transcript exactly as the Engine
    /// produced it.
    public static let off = CleanupRules(
        removesFillerWords: false, capitalisesSentences: false, breaksParagraphs: false)

    public let removesFillerWords: Bool
    public let capitalisesSentences: Bool
    public let breaksParagraphs: Bool

    public init(removesFillerWords: Bool, capitalisesSentences: Bool, breaksParagraphs: Bool) {
        self.removesFillerWords = removesFillerWords
        self.capitalisesSentences = capitalisesSentences
        self.breaksParagraphs = breaksParagraphs
    }
}

/// A Raw Transcript taken apart into the pieces the rules edit, and able to be
/// put back together again.
///
/// The rules edit this rather than rebuilding the text out of the Engine's word
/// list, which is what makes every rule an edit at the place it applies and
/// nowhere else. A rule that is off makes no edit, so a Cleanup with every rule
/// off hands back the bytes it was given — down to the Engine's leading space
/// and trailing newline.
struct RawTranscriptInPieces {
    /// Whatever came before the first word — the Engine's leading space, most
    /// often.
    private let opening: String

    /// The words, each carrying the whitespace that followed it in the Raw
    /// Transcript. The last one carries the Engine's trailing newline.
    var words: [Word]

    /// One word of the Raw Transcript, with what separated it from the next and
    /// when the Engine heard it.
    struct Word {
        /// The characters the Engine may hang on either end of a word, which
        /// are its punctuation rather than part of the word itself.
        private static let closers = "\"'\u{201D}\u{2019})]}\u{00BB}"
        private static let terminators = ".!?\u{2026}"

        /// The word as it appears in the Raw Transcript, punctuation and all.
        var text: String

        /// Whatever separated it from the word after it.
        var following: String

        /// When the Engine heard it. Nothing, where the word list it reported
        /// did not line up with the text it reported.
        var timing: WordTiming?

        /// The word with whatever punctuation the Engine hung on either end set
        /// aside, which is what was actually said.
        var spoken: String {
            let opened = text.drop(while: \.isPunctuationOrSymbol)
            return String(opened.reversed().drop(while: \.isPunctuationOrSymbol).reversed())
        }

        /// The punctuation the Engine hung on the end of it.
        var closing: String {
            String(text.reversed().prefix(while: \.isPunctuationOrSymbol).reversed())
        }

        /// Whether this word ended a sentence.
        ///
        /// Closing quotation marks and brackets are stepped over, so that a
        /// sentence which ended inside quotation marks still ended.
        var endsASentence: Bool {
            let closed = text.reversed().drop { Word.closers.contains($0) }
            guard let ending = closed.first else { return false }
            return Word.terminators.contains(ending)
        }

        /// Puts a capital on the word's first letter, where it has one to put a
        /// capital on.
        ///
        /// Quotation marks and brackets are stepped over, because the letter is
        /// what carries the case. A word that opens with a digit is left as it
        /// was heard: there is no capital form of "3", and going looking for
        /// the next word that has one would be Cleanup writing a sentence the
        /// user did not say.
        mutating func capitaliseFirstLetter() {
            let opening = text.prefix(while: \.isPunctuationOrSymbol)
            let rest = text.dropFirst(opening.count)
            guard let first = rest.first, first.isLetter else { return }
            text = String(opening) + String(first).uppercased() + String(rest.dropFirst())
        }

        /// Ends this word's sentence with punctuation a dropped Filler Word was
        /// carrying, in place of the comma the Engine wrote for the pause.
        mutating func endSentence(with closing: String) {
            text = String(text.reversed().drop { $0 == "," }.reversed()) + closing
        }
    }

    init(_ transcript: RawTranscript) {
        var opening = ""
        var words: [Word] = []

        // Read the Raw Transcript once, alternating between a run of whitespace
        // and a run of everything else. Every character lands in exactly one
        // place, which is the whole of the promise that putting it back
        // together gives back what came in.
        var rest = Substring(transcript.text)
        while !rest.isEmpty {
            let space = rest.prefix(while: \.isWhitespace)
            if !space.isEmpty {
                if words.isEmpty {
                    opening += space
                } else {
                    words[words.count - 1].following += space
                }
                rest = rest.dropFirst(space.count)
            }

            let word = rest.prefix { !$0.isWhitespace }
            if !word.isEmpty {
                words.append(Word(text: String(word), following: "", timing: nil))
                rest = rest.dropFirst(word.count)
            }
        }

        // The Engine reports the text and the word timings separately, and a
        // Paragraph Break is placed between two particular words — so the
        // timings are taken up only where the two describe the same words, one
        // for one. Where they disagree, no word carries a timing and no
        // Paragraph Break is placed: a newline in the wrong place is a
        // paragraph the user has to notice and undo, and the other two rules do
        // not look at a timing at all.
        //
        // Compared on letters and digits alone, because the two are the same
        // words whether or not the Engine wrote the comma into both.
        let lineUp =
            words.count == transcript.words.count
            && zip(words, transcript.words).allSatisfy {
                RawTranscriptInPieces.spelling(of: $0.text)
                    == RawTranscriptInPieces.spelling(of: $1.word)
            }
        if lineUp {
            for index in words.indices {
                words[index].timing = transcript.words[index]
            }
        }

        self.opening = opening
        self.words = words
    }

    /// A word reduced to what was said, so that the Engine's two reports of it
    /// can be compared without the punctuation and case each of them chose.
    private static func spelling(of word: String) -> String {
        word.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    /// The words put back together, which is the Final Text.
    var text: String {
        words.reduce(into: opening) { text, word in
            text += word.text + word.following
        }
    }
}

extension Character {
    /// Whether this is punctuation the Engine hung around a word rather than
    /// part of the word itself.
    fileprivate var isPunctuationOrSymbol: Bool { isPunctuation || isSymbol }
}
