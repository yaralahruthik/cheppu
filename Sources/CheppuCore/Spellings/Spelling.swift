/// A word or phrase the user has shown they say, written the way they want it
/// written.
///
/// It holds the word and nothing else. What the Engine heard in its place is
/// used at the moment the Correction is read and kept nowhere, so a Spelling
/// cannot be turned back into a rule that swaps one string for another — which
/// is what ADR-0014 rejects, and what makes two Spellings for one sound
/// something the Engine chooses between rather than a conflict anybody has to
/// resolve.
///
/// Making one is failable, because a Spelling has bounds and they are the whole
/// of what tells a Correction that teaches from one that only edits History.
/// They live here rather than in `Correction` so that a word read back off the
/// disk is held to them too.
public struct Spelling: Equatable, Hashable, Sendable, Comparable {
    /// The word, as the user wants it written.
    public let text: String

    /// How many words a Spelling may be.
    ///
    /// Three, because a phrase the user says as one thing — "event tap", "Swift
    /// Package Manager" — is a phrase the Engine can be asked to hear, and a
    /// sentence is not: a whole line reworded is somebody rewriting what they
    /// said rather than telling Cheppu how a word is spelt.
    public static let mostWords = 3

    /// How few letters a Spelling may have.
    ///
    /// FluidAudio declines to spot a term shorter than three characters,
    /// because "or" would become "VR". This is that floor made into a rule the
    /// user can read rather than a threshold they would have to discover
    /// (ADR-0014).
    public static let fewestLetters = 3

    /// - Parameter text: the word as it now reads. Nothing where it is not a
    ///   word Cheppu could ask the Engine to listen for: no words at all, more
    ///   than three of them, or too little of it to spot.
    public init?(_ text: String) {
        let word = Self.trimmed(text)
        guard Self.isWithinTheBounds(word) else { return nil }
        self.text = word
    }

    /// Whether a span of a Correction is something the Engine could be asked to
    /// hear.
    ///
    /// Asked of what the entry said as well as of what it says now. A Spelling
    /// is put in only where the sound supports it, and what was there is what
    /// occupies that sound: two letters swapped for three is the "to" made
    /// "too" that `CONTEXT.md` says teaches nothing, however well-formed the
    /// word that replaced it. The old span is read at that moment and kept
    /// nowhere.
    public static func isWithinTheBounds(_ text: String) -> Bool {
        let word = trimmed(text)
        let words = word.split(whereSeparator: \.isWhitespace)
        guard (1...mostWords).contains(words.count) else { return false }
        return word.filter(\.isLetter).count >= fewestLetters
    }

    /// The word with the sentence it was lifted out of left behind: no
    /// whitespace at either end, and none of the punctuation that ended the
    /// clause it sat in.
    ///
    /// A Correction is read off a line of prose, so the span that changed
    /// arrives carrying whatever followed it — "Cheppu," where the user typed a
    /// name in the middle of a sentence. The comma belongs to the sentence and
    /// not to the word, and a Spelling holding one would be a Spelling the
    /// Engine is asked to hear the punctuation of.
    ///
    /// Apostrophes and hyphens stay wherever they are, including at an end:
    /// they are how words are spelt rather than how sentences are ended.
    private static func trimmed(_ text: String) -> String {
        guard let opening = text.firstIndex(where: isPartOfAWord),
            let closing = text.lastIndex(where: isPartOfAWord)
        else { return "" }
        return String(text[opening...closing])
    }

    private static func isPartOfAWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "-"
    }

    /// Alphabetical, so that a window listing Spellings lists them in an order
    /// the user can look a word up in rather than in the order they happened to
    /// correct things.
    public static func < (one: Spelling, other: Spelling) -> Bool {
        one.text.lowercased() < other.text.lowercased()
    }
}
