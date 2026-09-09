/// The user changing a word of a Final Text, inside Cheppu, to what they
/// actually said.
///
/// The only way Cheppu ever finds out it was wrong. Nothing is read out of the
/// Target App after Insertion — that is the one thing
/// `docs/product-experience.md` §10 says Cheppu structurally cannot do — so a
/// word fixed there is a word Cheppu never hears about, and this is what is
/// left: the entry in History, edited in place, read off as the difference
/// between what it said and what it says now.
///
/// A Correction is a value rather than something a store performs, so that what
/// an edit teaches is decided here and tested here, and the store is left with
/// the one thing it is for — putting it on the disk.
///
/// It changes the Final Text History keeps and nothing else. The timestamp does
/// not move, nothing is inserted again and the clipboard is not touched: the
/// words are already where they went, and a Correction is the user telling
/// Cheppu about it rather than asking for it again.
public struct Correction: Equatable, Sendable {
    /// What the entry says now, which is what History keeps from here.
    public let corrected: FinalText

    /// What the change left behind, which may be nothing.
    ///
    /// A change outside a Spelling's bounds — a sentence reworded, a row
    /// emptied, "to" made "too" — is still an edit of History and teaches
    /// nothing, silently, in the manner of a Discard. There is no way to say
    /// "that was not worth learning from" that is worth interrupting somebody
    /// mid-edit for.
    public let spellings: [Spelling]

    /// - Parameters:
    ///   - was: what the entry said before the user clicked into it.
    ///   - now: what it says now.
    public init(of was: FinalText, to now: FinalText) {
        let before = Self.words(of: was)
        let after = Self.words(of: now)

        self.corrected = now
        self.spellings = ChangedSpans.between(before, and: after).compactMap { span in
            // What the entry said there decides as much as what it says now.
            // A Spelling is put back only where the sound supports it, and what
            // was there is what occupies that sound; two letters swapped for
            // three is a typo being fixed rather than a word being taught. Read
            // at this moment and kept nowhere, which is the whole of what
            // `CONTEXT.md` allows a Correction to do with it.
            guard Spelling.isWithinTheBounds(before[span.was].joined(separator: " ")) else {
                return nil
            }
            return Spelling(after[span.now].joined(separator: " "))
        }
    }

    /// Whether the user changed anything at all, so that clicking into a row and
    /// out of it again is not a write.
    public func changes(_ was: FinalText) -> Bool {
        corrected != was
    }

    /// The Final Text as the words the difference is read in.
    ///
    /// The punctuation a word was written with travels with it, and a Spelling
    /// trims its own ends — which it can do knowing which end it is looking at,
    /// and this cannot.
    private static func words(of text: FinalText) -> [String] {
        ChangedSpans.words(in: text.text)
    }
}
