import CheppuCore
import Foundation
import Testing

@testable import CheppuDiagnostics

// These tests write a real file in a temporary folder of their own, and read
// back what a user would read — and what they would find if they searched it
// for something they had said.
@Suite("The Diagnostics Log")
struct DiagnosticsLogTests {
    /// A directory nobody else is using, and the log inside it. Torn down at
    /// the end of the test whatever happened in it, so that a suite run leaves
    /// nothing behind — and the user's own log is never opened, let alone
    /// written to.
    private struct ADirectoryOfItsOwn: ~Copyable {
        let directory: URL
        var file: URL { directory.appendingPathComponent(DiagnosticsFile.name) }

        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("cheppu-diagnostics-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Everything Cheppu has ever had to write down, at least one of each.
    ///
    /// A note that cannot appear here is a note that cannot be checked for what
    /// it says, so the list is the whole vocabulary rather than a sample of it.
    private static let everythingCheppuEverWritesDown: [DiagnosticNote] =
        [
            .watchingForTheHotkey,
            .theHotkeyCouldNotBeWatched(FailureName(of: HotkeyFailure.accessibilityDenied)),
            .somethingFailed(FailureName(of: AudioCaptureFailure.noMicrophone)),
            .permissionMissing(.microphone),
        ]
        + DiagnosticNote.WhatHappened.allCases.map {
            .dictationMoved(from: .listening, to: .transcribing, by: $0)
        }

    /// The words of a Dictation somebody would think twice about sending to a
    /// stranger, and which appear nowhere else in Cheppu.
    ///
    /// The same Dictation the core suite puts in the Engine's mouth, so that
    /// both suites are asking about the same words. Common ones would find
    /// themselves in "listening" and "the Hotkey went down" and prove nothing.
    private static let somethingWorthNotSharing = [
        "Priya", "mortgage", "Kalyani", "Nagar", "Thursday",
    ]

    private static func read(_ file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    @Test("What happened is written down, in the order it happened")
    func whatHappenedIsWrittenDownInTheOrderItHappened() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file)

        log.record(.watchingForTheHotkey)
        log.record(.dictationMoved(from: .idle, to: .listening, by: .theHotkeyWentDown))
        log.record(.dictationMoved(from: .listening, to: .transcribing, by: .theCapWasReached))
        await log.waitForTheDiskToCatchUp()

        let lines = try Self.read(place.file).split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix("watching for the Hotkey"))
        #expect(lines[1].hasSuffix("idle → listening, the Hotkey went down"))
        #expect(lines[2].hasSuffix("listening → transcribing, the Cap was reached"))
    }

    @Test("Every line says when it happened and how long after the one before it")
    func everyLineSaysWhenItHappenedAndHowLongAfterTheOneBefore() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file)

        log.record(.watchingForTheHotkey)
        log.record(.dictationMoved(from: .idle, to: .listening, by: .theHotkeyWentDown))
        await log.waitForTheDiskToCatchUp()

        // The moment, to the millisecond, with the machine's offset from UTC on
        // it — and the gap since the line before, which is the number somebody
        // reading the file is reading it for. Between them they are the whole of
        // what the log knows about timing (`docs/product-experience.md` §7).
        for line in try Self.read(place.file).split(separator: "\n") {
            #expect(
                line.wholeMatch(
                    of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}[Z+\-].*  \+\d+\.\d{3}s  .+/)
                    != nil)
        }
    }

    @Test("Nothing anybody said can be found anywhere in the file")
    func nothingAnybodySaidCanBeFoundAnywhereInTheFile() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file)

        for note in Self.everythingCheppuEverWritesDown {
            log.record(note)
        }
        await log.waitForTheDiskToCatchUp()

        // Every note Cheppu can write, written, and then the file searched for
        // the words of a Dictation. Nothing in the vocabulary can carry them —
        // that is what `DiagnosticNote` is for — and this is the file itself
        // being asked.
        let written = try Self.read(place.file)
        for word in Self.somethingWorthNotSharing {
            #expect(!written.localizedCaseInsensitiveContains(word))
        }
    }

    @Test("The log starts a new file when it fills up, and keeps the one before")
    func theLogStartsANewFileWhenItFillsUp() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file, roomForEach: 200)

        for _ in 0..<20 {
            log.record(.dictationMoved(from: .idle, to: .listening, by: .theHotkeyWentDown))
        }
        await log.waitForTheDiskToCatchUp()

        // Two files, each of a known size: the log Cheppu is writing now and the
        // one it filled up before it. Nothing else is left behind, which is the
        // whole of the bound.
        let left = try FileManager.default.contentsOfDirectory(atPath: place.directory.path)
            .sorted()
        #expect(left == ["Diagnostics.log", "Diagnostics.previous.log"])
    }

    @Test("However long Cheppu runs, the log cannot grow past what it is allowed")
    func theLogCannotGrowPastWhatItIsAllowed() async throws {
        let roomForEach = 200
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file, roomForEach: roomForEach)

        for _ in 0..<200 {
            log.record(.dictationMoved(from: .inserting, to: .idle, by: .theInsertionLanded))
        }
        await log.waitForTheDiskToCatchUp()

        // Two hundred lines through a file with room for one line and a bit:
        // what is on the disk is still two files, and each is still about the
        // size it was allowed to be. A log that could grow without end would be
        // the one thing on the machine that quietly got bigger for as long as
        // somebody used Cheppu.
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: place.directory.path)
            .map { place.directory.appendingPathComponent($0) }
            .compactMap { try FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int }
        #expect(onDisk.count == 2)
        // One line's worth of overshoot each: the size is checked before a line
        // is written rather than after it.
        #expect(onDisk.allSatisfy { $0 < roomForEach * 2 })
    }

    @Test("Notes taken faster than the disk will take them leave a line, not a silence")
    func notesTakenFasterThanTheDiskLeaveALineNotASilence() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file, roomForEach: DiagnosticsFile.roomForOne)

        // More notes at once than the queue has room for, and none of them
        // written yet: what is dropped is the old end, because whoever reads
        // this is looking at what just happened.
        let takenAtOnce = DiagnosticsLog.notesThatMayWait + 50
        for _ in 0..<takenAtOnce {
            log.record(.dictationMoved(from: .idle, to: .listening, by: .theHotkeyWentDown))
        }
        await log.waitForTheDiskToCatchUp()

        let lines = try Self.read(place.file).split(separator: "\n")
        let owningUp = lines.filter { $0.contains("notes were dropped") }
        let dropped = owningUp.compactMap { line in
            line.split(separator: "  ").last?.split(separator: " ").first.flatMap { Int($0) }
        }

        // Some of them reached the disk while the rest were still being taken —
        // how many is the disk's business and not something to assert. What is
        // asserted is that none of them went missing: every note is either a
        // line in the file or counted in one that says so. A log that quietly
        // skipped what it could not keep up with would send whoever reads it
        // looking for a Dictation that never failed.
        #expect(!owningUp.isEmpty)
        #expect(dropped.count == owningUp.count)
        #expect(dropped.reduce(0, +) + lines.count - owningUp.count == takenAtOnce)

    }

    @Test("Notes taken from everywhere at once still land in the order they happened")
    func notesTakenFromEverywhereAtOnceStillLandInOrder() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file)

        // A real Dictation takes its notes from one actor, but nothing in the
        // port says so, and a log whose lines could overtake each other would
        // reorder the story it exists to tell.
        await withTaskGroup(of: Void.self) { everyone in
            for _ in 0..<50 {
                everyone.addTask { log.record(.watchingForTheHotkey) }
            }
        }
        await log.waitForTheDiskToCatchUp()

        let moments = try Self.read(place.file)
            .split(separator: "\n")
            .map { $0.prefix(while: { $0 != " " }) }
        #expect(moments.count == 50)
        #expect(moments == moments.sorted())
    }

    @Test("Nobody but its owner can read it")
    func nobodyButItsOwnerCanReadIt() async throws {
        let place = ADirectoryOfItsOwn()
        let log = DiagnosticsLog(keptAt: place.file)

        log.record(.watchingForTheHotkey)
        await log.waitForTheDiskToCatchUp()

        // It holds none of the user's words and it still says how much they
        // dictate and when, which is not another account's business.
        #expect(try Self.permissions(of: place.file) == DiagnosticsFile.onlyTheUsersOwn)
        #expect(try Self.permissions(of: place.directory) == DiagnosticsFile.aFolderOnlyTheUsersOwn)
    }

    @Test("A folder Cheppu may not close is still a folder it writes the log in")
    func aFolderCheppuMayNotCloseIsStillAFolderItWritesTheLogIn() async throws {
        // macOS protects some folders from having their permissions changed at
        // all, and the one every Mac has is the temporary directory this suite
        // works in. A log that gave up on a folder it may not change would be a
        // log that wrote nothing on the machines most worth diagnosing — so the
        // folder is attempted and the file is what is insisted on.
        let inAProtectedFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheppuDiagnosticsTests-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: inAProtectedFolder) }

        let log = DiagnosticsLog(keptAt: inAProtectedFolder)
        log.record(.watchingForTheHotkey)
        await log.waitForTheDiskToCatchUp()

        #expect(
            try String(contentsOf: inAProtectedFolder, encoding: .utf8)
                .hasSuffix("watching for the Hotkey\n"))

        // And it is still closed to everybody but its owner, which is the half
        // that was never best-effort.
        #expect(try Self.permissions(of: inAProtectedFolder) == DiagnosticsFile.onlyTheUsersOwn)
    }

    @Test("The log is kept where only this user's own things are kept")
    func theLogIsKeptWhereOnlyThisUsersOwnThingsAreKept() throws {
        // Application Support in the user's own Library, under `Cheppu/` beside
        // History and the Engine, so that everything Cheppu has put on the
        // machine is in one folder they can read and drag to the Trash
        // (ADR-0009). Worked out, never made: asking where the log goes creates
        // nothing, so the suite writes nowhere but the directories above.
        let location = try DiagnosticsFile.defaultLocation()

        #expect(location.path.hasPrefix(NSHomeDirectory() + "/Library/Application Support/Cheppu/"))
        #expect(location.lastPathComponent == "Diagnostics.log")
        #expect(
            DiagnosticsFile.theOneBefore(location).lastPathComponent
                == "Diagnostics.previous.log")
    }

    @Test("A log that cannot be written costs the user nothing")
    func aLogThatCannotBeWrittenCostsTheUserNothing() async throws {
        // A file where a folder cannot be made: the log has nowhere to go, and
        // it is the least important thing Cheppu does sitting on the path of the
        // most important one.
        let nowhere = URL(fileURLWithPath: "/dev/null/nowhere/Diagnostics.log")
        let log = DiagnosticsLog(keptAt: nowhere)

        log.record(.watchingForTheHotkey)
        await log.waitForTheDiskToCatchUp()

        #expect(!FileManager.default.fileExists(atPath: nowhere.path))
    }
}
