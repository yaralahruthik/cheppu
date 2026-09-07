import CheppuCore
import Foundation
import Synchronization

/// The Diagnostics Log, on the disk.
///
/// The whole of Cheppu's diagnostic story: one plain text file the user can
/// read before they decide to send it, holding what happened and never what was
/// said. There is no telemetry behind this, no crash reporter, no analytics
/// dependency, and no network path — nothing here talks to anything but a file
/// on the machine it is about.
///
/// A note is taken and let go of. `record(_:)` stamps it, puts it in a queue and
/// returns, and the writing happens on a task of its own, because notes are
/// taken on the path between somebody finishing a sentence and the words
/// appearing and nothing on that path may wait for a disk
/// (`docs/product-experience.md` §7). The stamp is taken where the note is,
/// which is what lets the file be timed to the millisecond by something that
/// was never waited for.
///
/// It is a queue rather than a task per note, so that lines land in the order
/// they happened: two unstructured tasks racing for the same file would be a
/// log that reordered the story it exists to tell.
public final class DiagnosticsLog: DiagnosticsPort {
    /// Notes taken and not yet written, and whether something is already
    /// writing them.
    private struct Waiting {
        var lines: [WrittenLine] = []
        var isBeingWritten = false

        /// How many notes were dropped for want of room and have not been
        /// owned up to in the file yet.
        var dropped = 0
    }

    /// How many notes may be waiting before the oldest of them are dropped.
    ///
    /// Notes, not bytes: this is the queue in memory, and `roomForOne` is how
    /// big a file on the disk gets. The two are near neighbours in name and
    /// measure different things.
    ///
    /// A bound rather than none, because the queue is the one part of this that
    /// lives in memory: a disk that has stopped answering must cost the user a
    /// gap in a log file rather than the app. A thousand is some hundreds of
    /// Dictations' worth, which no real stall reaches.
    ///
    /// The oldest go, because whoever is reading this is looking at what just
    /// happened.
    static let notesThatMayWait = 1_000

    private let waiting = Mutex(Waiting())
    private let file: TheLogOnDisk

    /// The log where Cheppu keeps it: one file in the user's own Application
    /// Support, alongside History and the Engine.
    public convenience init() {
        self.init(keptAt: { try DiagnosticsFile.defaultLocation() })
    }

    /// - Parameters:
    ///   - url: the file to keep the log in.
    ///   - roomForEach: how big one file gets before the next line starts a new
    ///     one.
    ///
    /// The suite uses this to write somewhere of its own, and to fill a file
    /// without writing a quarter of a megabyte. Cheppu itself passes neither,
    /// which is why it is not public.
    convenience init(keptAt url: URL, roomForEach: Int = DiagnosticsFile.roomForOne) {
        self.init(keptAt: { url }, roomForEach: roomForEach)
    }

    private init(
        keptAt locate: @escaping @Sendable () throws -> URL,
        roomForEach: Int = DiagnosticsFile.roomForOne
    ) {
        self.file = TheLogOnDisk(keptAt: locate, roomForEach: roomForEach)
    }

    public func record(_ note: DiagnosticNote) {
        let startWriting = waiting.withLock { waiting -> Bool in
            // Stamped here, where it happened rather than where it is written,
            // and inside the lock rather than in front of it: two notes taken
            // at once would otherwise be able to join the queue in one order
            // and carry moments in the other, which is a log that says a
            // Dictation finished before it started.
            waiting.lines.append(WrittenLine(note: note, at: Date()))

            // Room is made at the old end, because whoever reads this is
            // looking at what just happened. How many went is remembered, so
            // that the gap in the file is a line saying there is one rather
            // than a silence.
            if waiting.lines.count > Self.notesThatMayWait {
                let dropped = waiting.lines.count - Self.notesThatMayWait
                waiting.lines.removeFirst(dropped)
                waiting.dropped += dropped
            }

            guard !waiting.isBeingWritten else { return false }
            waiting.isBeingWritten = true
            return true
        }

        // One writer at a time, and it goes on until there is nothing left, so
        // the lines reach the file in the order they were taken.
        guard startWriting else { return }
        Task.detached { [self] in
            while let line = nextToWrite() {
                await file.append(line)
            }
        }
    }

    /// The next line waiting, or nothing — and where there is nothing, the
    /// writing is over and the next note taken starts a writer of its own.
    ///
    /// Both halves under one lock, so that a note taken between the queue
    /// emptying and the flag coming down cannot be one nobody ever writes.
    private func nextToWrite() -> WrittenLine? {
        waiting.withLock { waiting in
            guard let next = waiting.lines.first else {
                waiting.isBeingWritten = false
                return nil
            }

            // What was dropped is owned up to before the first line that
            // survived it, and stamped with that line's moment, so the hole in
            // the file is where the hole in the story is.
            guard waiting.dropped == 0 else {
                let howMany = waiting.dropped
                waiting.dropped = 0
                return WrittenLine(note: .notesWereDropped(howMany), at: next.at)
            }
            return waiting.lines.removeFirst()
        }
    }

    /// Returns once everything handed over has reached the disk.
    ///
    /// Nothing on a Dictation's path calls this, and nothing in Cheppu does at
    /// all: the whole point of the port is that a note is let go of rather than
    /// waited on. It is here for the suite, which has to read back a file that
    /// is written somewhere else.
    /// Nothing is left waiting once this returns, and nothing is still being
    /// written: the writer only puts the flag down inside the same lock that
    /// finds the queue empty, and it does that after the last line it took has
    /// finished being written.
    public func waitForTheDiskToCatchUp() async {
        while waiting.withLock({ $0.isBeingWritten || !$0.lines.isEmpty }) {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// The file itself: where it is, how big it is allowed to get, and what
/// happens when it gets there.
///
/// An actor because one line is written at a time and because the log must
/// never be two half-written files at once.
private actor TheLogOnDisk {
    private let locate: @Sendable () throws -> URL
    private let roomForEach: Int
    private var located: URL?

    /// When the line before this one happened, so that the gap can be written
    /// next to the one after it.
    private var previouslyWrittenAt: Date?

    init(keptAt locate: @escaping @Sendable () throws -> URL, roomForEach: Int) {
        self.locate = locate
        self.roomForEach = roomForEach
    }

    func append(_ line: WrittenLine) {
        // A log that cannot be written is a log that cannot be written. It is
        // the least important thing Cheppu does and it sits on the path of the
        // most important one, so a full disk costs the user a line in a file
        // they may never open rather than the Dictation they were in the middle
        // of.
        do {
            try write(line.text(since: previouslyWrittenAt))
        } catch {
            return
        }
        // Moved on only by a line that landed, so that the gap written next to
        // the line after it is measured from something somebody can read rather
        // than from a line that never arrived.
        previouslyWrittenAt = line.at
    }

    private func write(_ text: String) throws {
        let file = try locateOnce()
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // The folder is made no more open than the file in it, and closed on
        // every write rather than when it is made, for the same reason
        // History's is: it is usually the Engine Download that made it, and the
        // attributes handed to `createDirectory` are ignored for a folder that
        // is already there.
        //
        // Attempted rather than insisted on, which is the one place this parts
        // company with History. Closing a folder Cheppu did not make can be
        // refused — macOS protects some of them outright — and a log that gave
        // up on a folder it may not change would be a log that wrote nothing on
        // the machines most worth diagnosing. What actually keeps the lines to
        // their owner is the file's own permissions below, which are set as it
        // is created rather than after something has been written into it.
        try? FileManager.default.setAttributes(
            [.posixPermissions: DiagnosticsFile.aFolderOnlyTheUsersOwn],
            ofItemAtPath: folder.path)

        rotateIfItIsFull(file)

        let bytes = Data((text + "\n").utf8)
        guard let handle = try? FileHandle(forWritingTo: file) else {
            // The first line of a new file — the first ever, or the first after
            // a rotation moved the last one aside. It is created closed to
            // everybody but its owner, rather than created and closed
            // afterwards, so there is no moment at which it is a file another
            // account could open.
            FileManager.default.createFile(
                atPath: file.path, contents: bytes,
                attributes: [.posixPermissions: DiagnosticsFile.onlyTheUsersOwn])
            return
        }

        // Appended rather than rewritten. History rewrites its hundred lines
        // every time because a hundred lines is what it holds; a log that
        // rewrote itself would spend more of the disk on every line than the
        // line before it cost — and the permissions of a file that is never
        // replaced are the ones it was created with.
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: bytes)
    }

    /// Starts a new file where this one has filled up, keeping the one before it
    /// and dropping the one before that.
    ///
    /// This is the whole of the bound: at most two files, each of a known size,
    /// so the log cannot grow without end however long Cheppu runs and however
    /// much the user dictates.
    private func rotateIfItIsFull(_ file: URL) {
        let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        guard let size, size >= roomForEach else { return }

        let theOneBefore = DiagnosticsFile.theOneBefore(file)
        try? FileManager.default.removeItem(at: theOneBefore)
        try? FileManager.default.moveItem(at: file, to: theOneBefore)
    }

    private func locateOnce() throws -> URL {
        if let located { return located }
        let file = try locate()
        located = file
        return file
    }
}
