import CheppuCore
import Foundation
import Testing

@testable import CheppuHistory

// These tests write real files, in a directory of their own that goes away
// afterwards. The user's own Spellings are never opened, never read and never
// forgotten by the suite: the store is told where to keep itself, which is the
// only reason it takes a location at all.
@Suite("Spellings store")
struct SpellingsStoreTests {
    private static func spelling(_ text: String) -> Spelling {
        Spelling(text)!
    }

    /// A directory nobody else is using, holding the two files Cheppu keeps
    /// beside each other. Torn down at the end of the test whatever happened
    /// in it.
    private struct ADirectoryOfItsOwn: ~Copyable {
        let directory: URL
        var spellings: URL { directory.appendingPathComponent("Cheppu/Spellings.jsonl") }
        var history: URL { directory.appendingPathComponent("Cheppu/History.jsonl") }

        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cheppu-spellings-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test("A Spelling kept is a Spelling read back")
    func aSpellingKeptIsASpellingReadBack() async throws {
        let place = ADirectoryOfItsOwn()
        let store = SpellingsStore(keptAt: place.spellings)

        try await store.keep([Self.spelling("Cheppu")])

        #expect(await store.spellings().entries == [Self.spelling("Cheppu")])
    }

    @Test("Spellings outlive the launch that taught them")
    func spellingsOutliveTheLaunchThatTaughtThem() async throws {
        let place = ADirectoryOfItsOwn()
        try await SpellingsStore(keptAt: place.spellings)
            .keep([Self.spelling("Cheppu"), Self.spelling("Hruthik")])

        let afterRelaunching = SpellingsStore(keptAt: place.spellings)

        #expect(
            await afterRelaunching.spellings().entries.map(\.text) == ["Cheppu", "Hruthik"])
    }

    @Test("One Spelling to a line, readable with cat")
    func oneSpellingToALineReadableWithCat() async throws {
        // A store that had to be trusted rather than looked at would be an odd
        // way to keep a promise about privacy (ADR-0009).
        let place = ADirectoryOfItsOwn()
        try await SpellingsStore(keptAt: place.spellings)
            .keep([Self.spelling("Cheppu"), Self.spelling("Hruthik")])

        let lines = try String(contentsOf: place.spellings, encoding: .utf8)
            .split(whereSeparator: \.isNewline)

        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.contains("\"text\"") })
    }

    @Test("A line holds the word and nothing else")
    func aLineHoldsTheWordAndNothingElse() async throws {
        // A Spelling has no memory of what it replaced. Nothing of what the
        // Engine heard is written anywhere, which is what stops a Spelling ever
        // becoming a rule that swaps one string for another (ADR-0014).
        let place = ADirectoryOfItsOwn()
        try await SpellingsStore(keptAt: place.spellings).keep([Self.spelling("Cheppu")])

        let line = try String(contentsOf: place.spellings, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let read = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])

        #expect(read.keys.sorted() == ["text"])
    }

    @Test("Spellings are kept beside History and nowhere else")
    func spellingsAreKeptBesideHistoryAndNowhereElse() async throws {
        // Two files in one folder, which is the folder the user deletes when
        // they are done with Cheppu (ADR-0009).
        #expect(
            try SpellingsFile.defaultLocation().deletingLastPathComponent()
                == HistoryFile.defaultLocation().deletingLastPathComponent())
    }

    @Test("Nobody but the user can read what they taught Cheppu")
    func nobodyButTheUserCanReadWhatTheyTaughtCheppu() async throws {
        let place = ADirectoryOfItsOwn()
        try await SpellingsStore(keptAt: place.spellings).keep([Self.spelling("Cheppu")])

        #expect(try Self.permissions(of: place.spellings) == 0o600)
        #expect(try Self.permissions(of: place.spellings.deletingLastPathComponent()) == 0o700)
    }

    @Test("A folder somebody else made is closed on the way past")
    func aFolderSomebodyElseMadeIsClosedOnTheWayPast() async throws {
        // On a real machine the Engine Download makes `Cheppu/` long before
        // anybody has corrected a word, and the attributes handed to
        // `createDirectory` are ignored for a folder that is already there.
        let place = ADirectoryOfItsOwn()
        let folder = place.spellings.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])

        try await SpellingsStore(keptAt: place.spellings).keep([Self.spelling("Cheppu")])

        #expect(try Self.permissions(of: folder) == 0o700)
    }

    @Test("A Spelling forgotten is gone from the file")
    func aSpellingForgottenIsGoneFromTheFile() async throws {
        let place = ADirectoryOfItsOwn()
        let store = SpellingsStore(keptAt: place.spellings)
        try await store.keep([Self.spelling("Cheppu"), Self.spelling("Hruthik")])

        try await store.forget(Self.spelling("Cheppu"))

        #expect(await store.spellings().entries == [Self.spelling("Hruthik")])
        #expect(!(try String(contentsOf: place.spellings, encoding: .utf8).contains("Cheppu")))
    }

    @Test("Forgetting them all leaves no file behind")
    func forgettingThemAllLeavesNoFileBehind() async throws {
        // The file is removed rather than emptied: a file holding the shape of
        // what the user asked Cheppu to forget is still keeping something.
        let place = ADirectoryOfItsOwn()
        let store = SpellingsStore(keptAt: place.spellings)
        try await store.keep([Self.spelling("Cheppu")])

        try await store.forgetEverything()

        #expect(await store.spellings().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: place.spellings.path))
    }

    @Test("Emptying History leaves the Spellings, and forgetting those leaves History")
    func emptyingHistoryLeavesTheSpellings() async throws {
        // They are two things the user holds and two actions, and one doing
        // both would be one of them forgotten by accident (ADR-0014).
        let place = ADirectoryOfItsOwn()
        let history = HistoryStore(keptAt: place.history)
        let spellings = SpellingsStore(keptAt: place.spellings)
        try await history.append(
            HistoryEntry(finalText: FinalText("I said Cheppu."), recordedAt: Date()))
        try await spellings.keep([Self.spelling("Cheppu")])

        try await history.clear()
        #expect(await spellings.spellings().count == 1)

        try await spellings.forgetEverything()
        try await history.append(
            HistoryEntry(finalText: FinalText("Something else."), recordedAt: Date()))
        try await history.clear()
        #expect(await history.read().entries.isEmpty)
    }

    @Test("A file edited by hand is held to the bounds a Correction is")
    func aFileEditedByHandIsHeldToTheBoundsACorrectionIs() async throws {
        let place = ADirectoryOfItsOwn()
        try FileManager.default.createDirectory(
            at: place.spellings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            """
            {"text":"Cheppu"}
            {"text":"or"}
            not json at all
            {"text":"a whole sentence somebody typed in"}
            """.utf8
        ).write(to: place.spellings)

        #expect(await SpellingsStore(keptAt: place.spellings).spellings().entries.map(\.text)
            == ["Cheppu"])
    }

    @Test("Spellings nobody has taught are none rather than a failure")
    func spellingsNobodyHasTaughtAreNoneRatherThanAFailure() async throws {
        let place = ADirectoryOfItsOwn()

        #expect(await SpellingsStore(keptAt: place.spellings).spellings().isEmpty)
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}

// A Correction changes what History keeps and moves nothing else.
@Suite("Correcting a History entry")
struct CorrectingAHistoryEntryTests {
    private struct ADirectoryOfItsOwn: ~Copyable {
        let directory: URL
        var file: URL { directory.appendingPathComponent("Cheppu/History.jsonl") }

        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cheppu-corrections-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let aTuesdayAfternoon = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The entry keeps the corrected text and the timestamp it already had")
    func theEntryKeepsTheCorrectedTextAndTheTimestampItAlreadyHad() async throws {
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        let said = HistoryEntry(
            finalText: FinalText("I said chepo."), recordedAt: Self.aTuesdayAfternoon)
        try await store.append(said)

        try await store.correct(said, to: FinalText("I said Cheppu."))

        let corrected = try #require(await store.read().entries.first)
        #expect(corrected.finalText == FinalText("I said Cheppu."))
        #expect(corrected.recordedAt == Self.aTuesdayAfternoon)
    }

    @Test("A Correction keeps the entry where it was")
    func aCorrectionKeepsTheEntryWhereItWas() async throws {
        // A Correction is the user telling Cheppu it misheard them, not a new
        // Dictation. A row that jumped to the top would be History reordering
        // itself around an edit.
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        let older = HistoryEntry(
            finalText: FinalText("chepo"), recordedAt: Self.aTuesdayAfternoon)
        let newer = HistoryEntry(
            finalText: FinalText("something else"), recordedAt: Self.aTuesdayAfternoon + 30)
        try await store.append(older)
        try await store.append(newer)

        try await store.correct(older, to: FinalText("Cheppu"))

        #expect(
            await store.read().entries.map(\.finalText.text) == ["something else", "Cheppu"])
    }

    @Test("A Correction outlives the launch that made it")
    func aCorrectionOutlivesTheLaunchThatMadeIt() async throws {
        let place = ADirectoryOfItsOwn()
        let said = HistoryEntry(
            finalText: FinalText("I said chepo."), recordedAt: Self.aTuesdayAfternoon)
        let store = HistoryStore(keptAt: place.file)
        try await store.append(said)
        try await store.correct(said, to: FinalText("I said Cheppu."))

        #expect(
            await HistoryStore(keptAt: place.file).read().entries.map(\.finalText.text)
                == ["I said Cheppu."])
    }

    @Test("Correcting a Dictation History no longer has changes nothing")
    func correctingADictationHistoryNoLongerHasChangesNothing() async throws {
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        let gone = HistoryEntry(
            finalText: FinalText("something History dropped"), recordedAt: Self.aTuesdayAfternoon)
        try await store.append(
            HistoryEntry(finalText: FinalText("the only one"), recordedAt: Self.aTuesdayAfternoon))

        try await store.correct(gone, to: FinalText("Cheppu"))

        #expect(await store.read().entries.map(\.finalText.text) == ["the only one"])
    }
}
