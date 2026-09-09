/// Every Spelling the user has left behind, in the order a window lists them.
///
/// A type of its own rather than an array the store keeps, for the reason
/// `History` is one: what order they come in and what adding one twice means
/// are decisions, and the core is where decisions are made.
///
/// A set of words with no memory of what each replaced, so two Spellings cannot
/// conflict. Where the user has left two behind for one sound, both are here
/// and the Engine takes the closer; the other is removed by hand, in the
/// History window, and never by Cheppu deciding between them.
public struct Spellings: Equatable, Sendable {
    /// Alphabetical, because this is a list the user looks a word up in rather
    /// than a record of when they corrected things. Newest-first is History's
    /// order and belongs to History: a Dictation is looked for by "the thing I
    /// just said", and a Spelling by "did I teach it that".
    public let entries: [Spelling]

    /// - Parameter entries: what a store handed back. The same word twice is
    ///   one Spelling — a user correcting the same mishearing on a second
    ///   Dictation has not taught Cheppu anything new — and the order is
    ///   settled here rather than by whoever wrote the file.
    public init(_ entries: [Spelling] = []) {
        var seen: Set<Spelling> = []
        self.entries = entries.filter { seen.insert($0).inserted }.sorted()
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// The same Spellings with more of them in it, and nothing added twice.
    public func adding(_ more: [Spelling]) -> Spellings {
        Spellings(entries + more)
    }

    /// The same Spellings with one gone, which is what a user does about a
    /// Spelling they suspect of misfiring on a word they meant.
    public func removing(_ spelling: Spelling) -> Spellings {
        Spellings(entries.filter { $0 != spelling })
    }
}
