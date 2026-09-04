import CheppuCore
import Foundation
import Testing

@testable import CheppuHistory

// These tests write real files, in a directory of their own that goes away
// afterwards. The user's own History is never opened, never read and never
// cleared by the suite: the store is told where to keep itself, which is the
// only reason it takes a location at all.
@Suite("History store")
struct HistoryStoreTests {
    private static let aTuesdayAfternoon = Date(timeIntervalSince1970: 1_700_000_000)

    private static func said(_ text: String, secondsIn: TimeInterval = 0) -> HistoryEntry {
        HistoryEntry(finalText: FinalText(text), recordedAt: aTuesdayAfternoon + secondsIn)
    }

    /// A directory nobody else is using, and the History file inside it. Torn
    /// down at the end of the test whatever happened in it.
    private struct ADirectoryOfItsOwn: ~Copyable {
        let directory: URL
        var file: URL { directory.appendingPathComponent("Cheppu/History.jsonl") }

        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cheppu-history-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test("A Dictation written to History is there to be read back")
    func aDictationWrittenToHistoryIsThereToBeReadBack() async throws {
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)

        try await store.append(Self.said("Hello there."))

        #expect(await store.read().entries == [Self.said("Hello there.")])
    }

    @Test("History outlives the launch that wrote it, newest first")
    func historyOutlivesTheLaunchThatWroteIt() async throws {
        // The whole promise is that nothing said is lost, and a crash is the
        // case it exists for. What one store wrote, the next one opens — in the
        // order `History` put it in rather than the order it was written.
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        try await store.append(Self.said("The first thing.", secondsIn: 0))
        try await store.append(Self.said("The second thing.", secondsIn: 30))

        let afterRelaunching = HistoryStore(keptAt: place.file)

        #expect(
            await afterRelaunching.read().entries
                == [Self.said("The second thing.", secondsIn: 30), Self.said("The first thing.")]
        )
    }

    @Test("Only the hundred most recent Dictations are kept, on the disk as well as in hand")
    func onlyTheHundredMostRecentDictationsAreKept() async throws {
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)

        for number in 1...(History.capacity + 20) {
            try await store.append(
                Self.said("Dictation \(number).", secondsIn: TimeInterval(number)))
        }

        #expect(await store.read().entries.count == History.capacity)
        #expect(await store.read().entries.first?.finalText == FinalText("Dictation 120."))

        // On the disk too, and not merely in what is handed back. A file that
        // went on growing would be a store that kept what the user was told it
        // had dropped.
        let written = try String(contentsOf: place.file, encoding: .utf8)
        #expect(written.split(separator: "\n").count == History.capacity)
        #expect(!written.contains("Dictation 20."))
    }

    @Test("Clearing leaves nothing behind")
    func clearingLeavesNothingBehind() async throws {
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        try await store.append(Self.said("Something private."))

        try await store.clear()

        #expect(await store.read().entries.isEmpty)
        // The file itself is gone, not emptied: what the user asked for is that
        // Cheppu is no longer keeping what they said, and a file holding the
        // shape of it is still keeping something.
        #expect(!FileManager.default.fileExists(atPath: place.file.path))
        // And what is cleared stays cleared for the next launch.
        #expect(await HistoryStore(keptAt: place.file).read().entries.isEmpty)
    }

    @Test("A clearing that could not happen is not shown as having happened")
    func aClearingThatCouldNotHappenIsNotShownAsHavingHappened() async throws {
        // The user pressed Clear and the file is still there. What History says
        // it holds has to go on being what it holds: a window that emptied over
        // words still on the disk would be the one lie History cannot afford.
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        try await store.append(Self.said("Something private."))

        let folder = place.file.deletingLastPathComponent()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }

        await #expect(throws: (any Error).self) {
            try await store.clear()
        }

        #expect(await store.read().entries == [Self.said("Something private.")])
    }

    @Test("Clearing a History nothing has been written to is not a failure")
    func clearingAHistoryNothingHasBeenWrittenToIsNotAFailure() async throws {
        let place = ADirectoryOfItsOwn()
        try await HistoryStore(keptAt: place.file).clear()
    }

    @Test("A History nobody has dictated into reads as empty")
    func aHistoryNobodyHasDictatedIntoReadsAsEmpty() async {
        let place = ADirectoryOfItsOwn()

        #expect(await HistoryStore(keptAt: place.file).read().entries.isEmpty)
    }

    @Test("What is kept of a Dictation is the words and the moment, and nothing else")
    func whatIsKeptIsTheWordsAndTheMomentAndNothingElse() async throws {
        // Read back as the file itself rather than through the store, because
        // this is a promise about what is on the user's disk: no audio, no Raw
        // Transcript, and nothing about which app the words went into
        // (`docs/product-experience.md` §10).
        let place = ADirectoryOfItsOwn()
        try await HistoryStore(keptAt: place.file).append(Self.said("Hello there."))

        let line = try Data(contentsOf: place.file)
        let kept = try #require(
            try JSONSerialization.jsonObject(with: line) as? [String: Any]
        )

        #expect(Set(kept.keys) == ["text", "recordedAt"])
        #expect(kept["text"] as? String == "Hello there.")
        #expect(kept["recordedAt"] as? Double == Self.aTuesdayAfternoon.timeIntervalSince1970)
    }

    @Test("History is readable by nobody but the user, in a folder nobody else can open")
    func historyIsReadableByNobodyButTheUser() async throws {
        // A file anyone with an account on the machine could read would be a
        // transcript of everything the user has said this week.
        let place = ADirectoryOfItsOwn()
        try await HistoryStore(keptAt: place.file).append(Self.said("Something private."))

        #expect(try Self.permissions(of: place.file) == 0o600)
        #expect(try Self.permissions(of: place.file.deletingLastPathComponent()) == 0o700)
    }

    @Test("A folder that was already there is closed too")
    func aFolderThatWasAlreadyThereIsClosedToo() async throws {
        // On a real machine `Cheppu/` is nearly always made by the Engine
        // Download, long before anybody has dictated anything — and the
        // permissions handed to `createDirectory` are ignored for a folder that
        // already exists. So History closes it rather than assuming it made it.
        let place = ADirectoryOfItsOwn()
        let folder = place.file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755])

        try await HistoryStore(keptAt: place.file).append(Self.said("Something private."))

        #expect(try Self.permissions(of: folder) == 0o700)
    }

    @Test("A Dictation written after the first does not loosen the file")
    func aDictationWrittenAfterTheFirstDoesNotLoosenTheFile() async throws {
        // Writing a file atomically means writing a new one and moving it into
        // place, and a new file is created as loosely as the account's umask
        // allows. So the permissions are set every time rather than once.
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)

        try await store.append(Self.said("The first thing.", secondsIn: 0))
        try await store.append(Self.said("The second thing.", secondsIn: 30))

        #expect(try Self.permissions(of: place.file) == 0o600)
    }

    @Test("A line that cannot be read does not take the rest of History with it")
    func aLineThatCannotBeReadDoesNotTakeTheRestOfHistoryWithIt() async throws {
        // One Dictation per line, so that a write cut short by a crash or a
        // full disk costs the user that Dictation rather than every Dictation.
        let place = ADirectoryOfItsOwn()
        let store = HistoryStore(keptAt: place.file)
        try await store.append(Self.said("The first thing.", secondsIn: 0))
        try await store.append(Self.said("The second thing.", secondsIn: 30))

        // The newest line, cut off halfway through — which is what a crash
        // during a write leaves behind.
        var lines = try String(contentsOf: place.file, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        lines[0] = String(lines[0].prefix(lines[0].count / 2))
        try lines.joined(separator: "\n").write(to: place.file, atomically: true, encoding: .utf8)

        #expect(
            await HistoryStore(keptAt: place.file).read().entries.map(\.finalText)
                == [FinalText("The first thing.")]
        )
    }

    @Test("Where History cannot be written, the Dictation says so rather than passing")
    func whereHistoryCannotBeWrittenTheDictationSaysSo() async throws {
        // A store that swallowed the failure would be one that told the user
        // their words were kept when they were not.
        //
        // Something that is not a folder where the folder has to go, which is
        // as close as a test can get to the full disk this is really about.
        let place = ADirectoryOfItsOwn()
        try Data().write(to: place.file.deletingLastPathComponent())

        await #expect(throws: (any Error).self) {
            try await HistoryStore(keptAt: place.file).append(Self.said("Hello there."))
        }
    }

    @Test("History is kept where only this user's own things are kept")
    func historyIsKeptWhereOnlyThisUsersOwnThingsAreKept() throws {
        // Application Support in the user's own Library: a folder that belongs
        // to this account, is not shared with another one, and is not synced
        // anywhere. Under `Cheppu/`, next to the Engine, so that everything
        // Cheppu put on the machine is in one place the user can delete.
        // Worked out, never made: asking where History goes creates no folder,
        // so the suite writes nowhere but the temporary directory above.
        let location = try HistoryFile.defaultLocation()

        #expect(location.path.hasPrefix(NSHomeDirectory() + "/Library/Application Support/Cheppu/"))
        #expect(location.lastPathComponent == "History.jsonl")
        #expect(!FileManager.default.fileExists(atPath: location.path))
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}
