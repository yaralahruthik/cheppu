/// Where two sequences of words differ, span by span.
///
/// A Correction is read off as the difference between what a History entry said
/// and what it says now, and the Engine re-attaches its word timings to a
/// transcript a Spelling has changed — both of which are the same question
/// asked twice, so it is answered once here.
///
/// Words are compared exactly, because case and punctuation are what a
/// Correction is often about: somebody writing "Cheppu" over "chepo" has
/// changed that word, and a comparison that forgave the difference would be one
/// that never noticed.
public enum ChangedSpans {
    /// One place the two disagree: what it was, and what it is now.
    ///
    /// Either range may be empty — words struck out, or words put in where
    /// there were none — which is how a caller tells a replacement from an
    /// insertion without being told.
    public struct Span: Equatable, Sendable {
        public let was: Range<Int>
        public let now: Range<Int>

        public init(was: Range<Int>, now: Range<Int>) {
            self.was = was
            self.now = now
        }
    }

    /// How big a pair of middles may get before they are answered with one span
    /// covering the whole of both.
    ///
    /// The table below is one entry per pair of words. A History entry is at
    /// most five minutes of speech, so this is never reached by anything a user
    /// produced; it is here so that a file edited by hand cannot turn a window
    /// redraw into a gigabyte.
    private static let asLargeAsItIsWorthComparing = 1_000_000

    /// A text as the words a difference between two of them is read in.
    ///
    /// Split on whitespace and nothing else, so that every character is in
    /// exactly one word and the punctuation a word was written with travels
    /// with it. Here rather than at each caller, so that the Correction read
    /// off a History entry and the Engine re-attaching its timings to a
    /// transcript a Spelling changed are counting the same words.
    public static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every place the two disagree, left to right.
    ///
    /// Nothing where they are the same sequence, which is the answer for a
    /// History entry somebody clicked into and clicked out of again.
    public static func between(_ was: [String], and now: [String]) -> [Span] {
        // The ends first. Nearly every Correction is one word inside a line
        // that is otherwise untouched, and trimming what matches is what keeps
        // the table below the size of the change rather than the size of the
        // Dictation.
        var opening = 0
        while opening < was.count, opening < now.count, was[opening] == now[opening] {
            opening += 1
        }

        var closingWas = was.count
        var closingNow = now.count
        while closingWas > opening, closingNow > opening, was[closingWas - 1] == now[closingNow - 1] {
            closingWas -= 1
            closingNow -= 1
        }

        let middleWas = Array(was[opening..<closingWas])
        let middleNow = Array(now[opening..<closingNow])
        if middleWas.isEmpty, middleNow.isEmpty { return [] }

        guard middleWas.count * middleNow.count <= asLargeAsItIsWorthComparing else {
            return [Span(was: opening..<closingWas, now: opening..<closingNow)]
        }

        return spans(
            around: matches(middleWas, middleNow),
            over: middleWas.count, and: middleNow.count, from: opening)
    }

    /// The words the two middles have in common, as pairs of positions.
    ///
    /// A longest-common-subsequence walk rather than a word-by-word comparison,
    /// so that a word put in or taken out shifts everything after it by one
    /// without turning the rest of the line into a change.
    private static func matches(_ was: [String], _ now: [String]) -> [(was: Int, now: Int)] {
        var common = [[Int]](
            repeating: [Int](repeating: 0, count: now.count + 1), count: was.count + 1)
        for one in stride(from: was.count - 1, through: 0, by: -1) {
            for other in stride(from: now.count - 1, through: 0, by: -1) {
                common[one][other] =
                    was[one] == now[other]
                    ? common[one + 1][other + 1] + 1
                    : max(common[one + 1][other], common[one][other + 1])
            }
        }

        var pairs: [(was: Int, now: Int)] = []
        var one = 0
        var other = 0
        while one < was.count, other < now.count {
            if was[one] == now[other] {
                pairs.append((one, other))
                one += 1
                other += 1
            } else if common[one + 1][other] >= common[one][other + 1] {
                one += 1
            } else {
                other += 1
            }
        }
        return pairs
    }

    /// The gaps between the words the two have in common, which is what changed.
    private static func spans(
        around matched: [(was: Int, now: Int)], over was: Int, and now: Int, from opening: Int
    ) -> [Span] {
        var spans: [Span] = []
        var lastWas = 0
        var lastNow = 0

        func take(upTo endWas: Int, and endNow: Int) {
            guard endWas > lastWas || endNow > lastNow else { return }
            spans.append(
                Span(
                    was: (opening + lastWas)..<(opening + endWas),
                    now: (opening + lastNow)..<(opening + endNow)))
        }

        for pair in matched {
            take(upTo: pair.was, and: pair.now)
            lastWas = pair.was + 1
            lastNow = pair.now + 1
        }
        take(upTo: was, and: now)

        return spans
    }
}
