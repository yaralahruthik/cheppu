import Foundation
import Testing

@testable import CheppuCore

// The order entries come back in and the number of them kept are decisions, so
// they are made here rather than by whoever is holding the file. A store that
// got either of them wrong would be one the user only found out about once
// something they said had already gone.
@Suite("History")
struct HistoryTests {
    private static let aTuesdayAfternoon = Date(timeIntervalSince1970: 1_700_000_000)

    /// One Dictation, said `secondsIn` seconds after the one before it.
    private static func said(_ text: String, secondsIn: TimeInterval = 0) -> HistoryEntry {
        HistoryEntry(finalText: FinalText(text), recordedAt: aTuesdayAfternoon + secondsIn)
    }

    @Test("A History nobody has dictated into is empty")
    func aHistoryNobodyHasDictatedIntoIsEmpty() {
        #expect(History().entries.isEmpty)
    }

    @Test("The newest Dictation is the first one read")
    func theNewestDictationIsTheFirstOneRead() {
        // What the user is looking for is nearly always the thing they just
        // said — they dictated into the wrong window a second ago and want it
        // back. Anything else is scrolling.
        let history = History()
            .appending(Self.said("The first thing.", secondsIn: 0))
            .appending(Self.said("The second thing.", secondsIn: 30))

        #expect(
            history.entries.map(\.finalText) == [
                FinalText("The second thing."), FinalText("The first thing."),
            ])
    }

    @Test("Only the hundred most recent Dictations are kept")
    func onlyTheHundredMostRecentDictationsAreKept() {
        var history = History()
        for number in 1...(History.capacity + 20) {
            history = history.appending(
                Self.said("Dictation \(number).", secondsIn: TimeInterval(number)))
        }

        #expect(history.entries.count == History.capacity)
        // The newest survives and the oldest is gone: a bound that dropped the
        // wrong end would keep a hundred Dictations nobody is looking for.
        #expect(history.entries.first?.finalText == FinalText("Dictation 120."))
        #expect(history.entries.last?.finalText == FinalText("Dictation 21."))
    }

    @Test("A store holding more than a hundred is read as the hundred most recent")
    func aStoreHoldingMoreThanAHundredIsReadAsTheHundredMostRecent() {
        // The bound is applied on the way in as well as on the way out, so that
        // a file written by an older Cheppu — or edited by hand — cannot make
        // History bigger than it is allowed to be.
        let tooMany = (1...(History.capacity + 5)).reversed().map {
            Self.said("Dictation \($0).", secondsIn: TimeInterval($0))
        }

        let history = History(tooMany)

        #expect(history.entries.count == History.capacity)
        #expect(history.entries.first?.finalText == FinalText("Dictation 105."))
    }

}
