/// Every Dictation Cheppu still has, newest first.
///
/// The list is a type of its own rather than an array the store keeps, because
/// the two things that make History trustworthy — which end the newest
/// Dictation is at, and how many are kept — are decisions, and the core is
/// where decisions are made. A store that answered them for itself would be one
/// whose answers could only be checked by writing files.
///
/// It holds Final Text and a timestamp and nothing else: no audio, no Raw
/// Transcript, and no record of where the words were inserted. What Cheppu keeps
/// of a Dictation is what the user said, not what they were doing when they said
/// it (`docs/product-experience.md` §10).
public struct History: Equatable, Sendable {
    /// How many Dictations are kept.
    ///
    /// A hundred is far more than the "I said that into the wrong window" that
    /// History exists for, and far less than a transcript of someone's month.
    /// The bound is the privacy promise doing its work while nobody is looking:
    /// a store that only ever grew would quietly become the most sensitive file
    /// on the machine.
    public static let capacity = 100

    /// Newest first. What the user is looking for is nearly always the thing
    /// they just said; everything else is scrolling.
    public let entries: [HistoryEntry]

    /// - Parameter entries: what a store handed back, newest first. More than
    ///   the capacity is trimmed here as well as on the way in, so that a file
    ///   written by an older Cheppu — or edited by hand — cannot make History
    ///   bigger than it is allowed to be.
    public init(_ entries: [HistoryEntry] = []) {
        self.entries = Array(entries.prefix(Self.capacity))
    }

    /// The same History with one more Dictation in it, and the oldest dropped
    /// where that takes it past the capacity.
    public func appending(_ entry: HistoryEntry) -> History {
        History([entry] + entries)
    }
}
