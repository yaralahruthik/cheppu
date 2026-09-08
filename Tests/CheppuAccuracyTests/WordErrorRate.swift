import Foundation

/// How wrong the Engine was: the errors it made over the words that were
/// actually said.
///
/// The standard measure — substitutions plus deletions plus insertions, over
/// the length of the reference — computed by aligning what was heard against
/// what was said and counting what the alignment had to do. The denominator is
/// what was said rather than what was heard, so an Engine that invents a
/// hundred words is not rewarded with a bigger one.
///
/// The counts are kept and not just the rate, because they are three different
/// problems: an Engine dropping words is a different regression from one
/// mishearing them, and whoever reads a red run wants to know which.
struct WordErrorRate: Sendable {
    /// Which of the two questions this measurement is answering.
    ///
    /// They are different questions and the harness commits a ceiling for each,
    /// because a run that has gone red is only actionable if it says which one
    /// moved. Parakeet writing "core ML" where it used to write "CoreML" is not
    /// the same event as Parakeet no longer hearing the word.
    enum Counting: Sendable, Hashable, CaseIterable {
        /// What the Engine heard. The ways two faithful transcripts of the same
        /// sounds can be written differently are forgiven — a number in digits,
        /// a compound split in two, a contraction, an American spelling of a
        /// word the author spells the British way. What is left is the Engine
        /// getting a word wrong, which is the thing this project cannot ship
        /// without.
        ///
        /// This is what published speech-recognition numbers are measured
        /// under, which is the other reason to keep it: a rate here can be
        /// compared with a rate anywhere else.
        case asSpoken

        /// What the user reads. Nothing is forgiven: if the text differs from
        /// what they wrote down, it counts, because it is text they have to go
        /// back and fix.
        case asWritten
    }

    /// Words the Engine heard as some other word.
    let substitutions: Int

    /// Words that were said and are not in the transcript.
    let deletions: Int

    /// Words in the transcript that nobody said.
    let insertions: Int

    /// How many words were said — the denominator, and what lets two fixtures
    /// of different lengths be added together honestly.
    let referenceWords: Int

    var errors: Int { substitutions + deletions + insertions }

    /// The rate itself. A corpus with nothing in it has a rate of nothing
    /// rather than an arithmetic error; the harness refuses an empty reference
    /// long before this is asked.
    var rate: Double {
        referenceWords == 0 ? 0 : Double(errors) / Double(referenceWords)
    }

    /// A rate as a person reads it. Lives here rather than at each call site so
    /// that a rate and the ceiling it is compared against are never printed to
    /// different precisions.
    static func percentage(_ rate: Double) -> String {
        String(format: "%.2f%%", rate * 100)
    }

    /// What the Engine heard, measured against what was said.
    init(heard: String, against reference: String, counting: Counting = .asWritten) {
        self.init(
            aligning: Self.words(in: heard, counting: counting),
            with: Self.words(in: reference, counting: counting),
            counting: counting)
    }

    /// Several fixtures as one number: every error over every word said.
    ///
    /// Added by their counts rather than by averaging their rates, so that ten
    /// seconds of "testing one two three" cannot weigh as much as two minutes
    /// of real dictation.
    init(totalling parts: [WordErrorRate]) {
        substitutions = parts.reduce(0) { $0 + $1.substitutions }
        deletions = parts.reduce(0) { $0 + $1.deletions }
        insertions = parts.reduce(0) { $0 + $1.insertions }
        referenceWords = parts.reduce(0) { $0 + $1.referenceWords }
    }

    private init(substitutions: Int, deletions: Int, insertions: Int, referenceWords: Int) {
        self.substitutions = substitutions
        self.deletions = deletions
        self.insertions = insertions
        self.referenceWords = referenceWords
    }

    // MARK: - What counts as a word

    /// The words in a piece of text, as the measurement compares them.
    ///
    /// Everything erased here is something Cleanup owns and its own suite
    /// tests: case, punctuation, and the whitespace between sentences. Counting
    /// a comma as a misheard word would bury the ones the user actually has to
    /// go back and fix.
    ///
    /// A hyphen is a word boundary on both sides of the comparison, because
    /// whether the Engine wrote "twenty-one" or "twenty one" is a spelling
    /// choice rather than a word it failed to hear. An apostrophe inside a word
    /// stays, so that counting as written can see the difference between "dont"
    /// and "don't"; counting as spoken takes contractions apart afterwards.
    static func words(in text: String, counting: Counting = .asWritten) -> [String] {
        let split =
            text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { word in
                // An apostrophe that turned out to be a quotation mark is
                // punctuation after all.
                String(
                    word.drop(while: { $0 == "'" }).reversed().drop(while: { $0 == "'" })
                        .reversed())
            }
            .filter { !$0.isEmpty }

        guard counting == .asSpoken else { return split }
        return split.flatMap(Self.asSpoken)
    }

    /// One written word as the word or words it was said as.
    ///
    /// Applied to both sides of the comparison rather than to the transcript
    /// alone, so it canonicalises rather than corrects: "promise" becoming
    /// "promize" on both sides changes nothing, and two words that were always
    /// different stay different.
    private static func asSpoken(_ word: String) -> [String] {
        if let expanded = contractions[word] { return expanded }
        if let digits = numbers[word] { return [digits] }

        // The author writes British English and Parakeet writes American, so
        // every -ise in a fixture would otherwise be a permanent tax on the
        // rate that no regression could be read through.
        for ending in ["ise", "ised", "ises", "ising", "isation"]
        where word.count > ending.count + 2 && word.hasSuffix(ending) {
            return [word.dropLast(ending.count) + "iz" + ending.dropFirst(2)]
        }

        return [word]
    }

    /// Numbers said aloud, as the Engine writes them.
    ///
    /// Only the ones a person says as a single word. "Three hundred and
    /// twelve" is several words either way and is left alone: a table that
    /// tried to assemble it would be arithmetic, and arithmetic here would be
    /// one more place a real error could hide.
    private static let numbers: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "eleven": "11",
        "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15", "sixteen": "16",
        "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
        "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80",
        "ninety": "90", "hundred": "100", "thousand": "1000",
    ]

    /// Contractions, taken apart into the words they stand for.
    ///
    /// Both sides again: a reference that says "you are" and a transcript that
    /// says "you're" become the same two words, and a transcript that says
    /// "it is sweet" where the reference says "its suite" stays as wrong as it
    /// was.
    private static let contractions: [String: [String]] = [
        "you're": ["you", "are"], "we're": ["we", "are"], "they're": ["they", "are"],
        "it's": ["it", "is"], "that's": ["that", "is"], "there's": ["there", "is"],
        "what's": ["what", "is"], "here's": ["here", "is"], "let's": ["let", "us"],
        "i'm": ["i", "am"], "i've": ["i", "have"], "you've": ["you", "have"],
        "we've": ["we", "have"], "they've": ["they", "have"], "i'll": ["i", "will"],
        "you'll": ["you", "will"], "we'll": ["we", "will"], "they'll": ["they", "will"],
        "don't": ["do", "not"], "doesn't": ["does", "not"], "didn't": ["did", "not"],
        "isn't": ["is", "not"], "aren't": ["are", "not"], "wasn't": ["was", "not"],
        "weren't": ["were", "not"], "can't": ["can", "not"], "cannot": ["can", "not"],
        "won't": ["will", "not"], "wouldn't": ["would", "not"], "couldn't": ["could", "not"],
        "shouldn't": ["should", "not"], "hasn't": ["has", "not"], "haven't": ["have", "not"],
        "hadn't": ["had", "not"],
    ]

    // MARK: - Alignment

    /// How many words either side of a boundary the alignment will try to join
    /// back together.
    ///
    /// Three is enough for every compound anybody writes without a space —
    /// "superwhisper", "fluidinference", "mac os x" — and small enough that the
    /// table stays a table rather than a search.
    ///
    /// One side of such a join is always a single word: a compound is one word
    /// written as several, or several written as one. Letting both sides be
    /// runs would buy nothing anybody has written down and would let the
    /// alignment rearrange words across a boundary to hide an error.
    private static let longestCompound = 3

    /// The cheapest way to turn what was said into what was heard, and what it
    /// cost in each of the three kinds of error.
    ///
    /// Levenshtein over words, relaxed forwards so that one more move can sit
    /// beside the usual three: counting as spoken, a run of words on one side
    /// may be matched free against a run on the other when the letters are the
    /// same with the spaces taken out, which is what makes "core ml" and
    /// "coreml" one word rather than two errors. The move taken into each cell
    /// is kept, so the path can be walked back afterwards: the total distance
    /// alone would say how wrong the Engine was without saying how, and the how
    /// is the useful part.
    ///
    /// Fixtures are minutes of speech rather than books, so a table of said ×
    /// heard is a few hundred thousand entries at worst.
    private init(aligning heard: [String], with said: [String], counting: Counting) {
        /// What the alignment did to get into a cell, and where it came from.
        enum Move {
            case matched(back: Int, across: Int)
            case substituted
            case deleted
            case inserted
        }

        let unreachable = Int.max / 2
        var cost = Array(
            repeating: Array(repeating: unreachable, count: heard.count + 1), count: said.count + 1)
        var move = Array(
            repeating: Array(repeating: Move?.none, count: heard.count + 1), count: said.count + 1)
        cost[0][0] = 0

        // Every move lands on a cell further down, further right, or both, so a
        // single pass in reading order reaches each cell only after everything
        // that could lead to it.
        for row in 0...said.count {
            for column in 0...heard.count {
                let here = cost[row][column]
                if here == unreachable { continue }

                func relax(_ toRow: Int, _ toColumn: Int, _ price: Int, _ taken: Move) {
                    guard here + price < cost[toRow][toColumn] else { return }
                    cost[toRow][toColumn] = here + price
                    move[toRow][toColumn] = taken
                }

                if row < said.count, column < heard.count {
                    let same = said[row] == heard[column]
                    relax(
                        row + 1, column + 1, same ? 0 : 1,
                        same ? .matched(back: 1, across: 1) : .substituted)
                }
                if row < said.count { relax(row + 1, column, 1, .deleted) }
                if column < heard.count { relax(row, column + 1, 1, .inserted) }

                guard counting == .asSpoken else { continue }

                // The same letters on both sides with the spaces somewhere
                // else. Free, and only ever reaching a cell the plain moves
                // could reach too, so it can shorten a path and never invent one.
                for back in 1...Self.longestCompound where row + back <= said.count {
                    for across in 1...Self.longestCompound where column + across <= heard.count {
                        if back == 1 && across == 1 { continue }
                        if back > 1 && across > 1 { continue }
                        guard
                            said[row..<(row + back)].joined()
                                == heard[column..<(column + across)].joined()
                        else { continue }
                        relax(
                            row + back, column + across, 0, .matched(back: back, across: across))
                    }
                }
            }
        }

        var substitutions = 0
        var deletions = 0
        var insertions = 0
        var row = said.count
        var column = heard.count

        while row > 0 || column > 0 {
            // Nothing can relax into the corner it started from, so the only
            // cell without a move is (0, 0) and it is where this stops. Stated
            // as a precondition rather than as a `while let`, because a nil
            // anywhere else would be a bug in the relaxation above and silently
            // returning a short count is the one way it could go unnoticed.
            guard let taken = move[row][column] else {
                preconditionFailure("no way back from (\(row), \(column)) in the alignment")
            }

            switch taken {
            case .matched(let back, let across):
                row -= back
                column -= across
            case .substituted:
                substitutions += 1
                row -= 1
                column -= 1
            case .deleted:
                deletions += 1
                row -= 1
            case .inserted:
                insertions += 1
                column -= 1
            }
        }

        self.init(
            substitutions: substitutions,
            deletions: deletions,
            insertions: insertions,
            referenceWords: said.count
        )
    }
}

extension WordErrorRate: CustomStringConvertible {
    /// What a run prints, so that a rate anyone reads comes with the three
    /// numbers it was made of.
    var description: String {
        return
            "\(Self.percentage(rate)) — \(substitutions) misheard, \(deletions) missed, "
            + "\(insertions) invented, over \(referenceWords) words"
    }
}
