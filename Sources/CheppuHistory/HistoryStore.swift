import CheppuCore
import Foundation

/// History, on the disk.
///
/// The store holds what was said and hands it back; which end the newest
/// Dictation is at and how many are kept are the core's (`History`), so that
/// the promises the user was made are not made again here in a different shape.
///
/// It is an actor because a Dictation writes to it from wherever the core is
/// running while the window reads from the main thread, and because the file
/// must never be two half-written files at once.
public actor HistoryStore: HistoryPort {
    /// Where the file is, or a way of working it out the first time it is
    /// needed.
    ///
    /// Worked out lazily rather than at launch so that a machine with no
    /// Application Support — which is the only way this can fail — still gets
    /// an app, a Hotkey and a menu, and fails at the Dictation that tries to
    /// write, where there is somebody to tell. An app that would not start
    /// because it could not find a folder is the one outcome
    /// `docs/product-experience.md` §4 rules out.
    private let locate: @Sendable () throws -> URL
    private var located: URL?

    /// What the file holds, once it has been read.
    ///
    /// Kept in hand because a Dictation writes History before it inserts, so
    /// the write is on the path between the user finishing a sentence and the
    /// words appearing (`docs/product-experience.md` §7). Reading a hundred
    /// lines back off the disk to add one to them would put a file read on
    /// every Dictation for nothing.
    private var history: History?

    /// History where Cheppu keeps it: one file in the user's own Application
    /// Support, alongside the Engine.
    public init() {
        self.locate = { try HistoryFile.defaultLocation() }
    }

    /// - Parameter url: the file to keep History in. The suite uses this to
    ///   write somewhere of its own; Cheppu itself never passes it.
    public init(keptAt url: URL) {
        self.locate = { url }
    }

    /// Adds one Dictation, and drops the oldest where that takes History past
    /// what it keeps.
    ///
    /// Throwing means the words are not on the disk, which the Dictation passes
    /// on rather than swallowing: a store that reported success it had not had
    /// would be one that told the user their words were kept when they were not.
    public func append(_ entry: HistoryEntry) async throws {
        let kept = readIfNeeded().appending(entry)
        try write(kept)
        history = kept
    }

    /// Everything Cheppu still has, newest first.
    ///
    /// A History that cannot be read is an empty one rather than a failure:
    /// there is nothing the user could do about it and nothing they would want
    /// instead, and the window saying "nothing yet" is the truth about what
    /// Cheppu can give them back.
    public func read() async -> History {
        readIfNeeded()
    }

    /// Empties the whole store, in one action.
    ///
    /// The file is removed rather than emptied: what the user asked for is that
    /// Cheppu is no longer keeping what they said, and a file holding the shape
    /// of it is still keeping something.
    ///
    /// Nothing to clear is not a failure — the user asked for an empty History
    /// and has one.
    /// The file goes first and what is held in hand goes after it, so that a
    /// clearing that could not happen is not one the user is shown as having
    /// happened. A window that emptied while the words were still on the disk
    /// would be the one lie History cannot afford to tell.
    public func clear() async throws {
        let file = try locateOnce()
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        history = History()
    }

    private func locateOnce() throws -> URL {
        if let located { return located }
        let file = try locate()
        located = file
        return file
    }

    private func readIfNeeded() -> History {
        if let history { return history }

        let kept = History(entriesOnDisk())
        history = kept
        return kept
    }

    /// What the file holds, skipping any line that cannot be read.
    ///
    /// A damaged line costs the user that Dictation and no others, which is the
    /// whole reason there is one Dictation per line rather than one document
    /// holding all of them.
    private func entriesOnDisk() -> [HistoryEntry] {
        guard let file = try? locateOnce(),
            let contents = try? String(contentsOf: file, encoding: .utf8)
        else { return [] }

        return
            contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let bytes = line.data(using: .utf8),
                    let read = try? JSONDecoder().decode(HistoryFile.Line.self, from: bytes)
                else { return nil }
                return read.entry
            }
    }

    private func write(_ history: History) throws {
        let file = try locateOnce()
        let folder = file.deletingLastPathComponent()

        // The folder is made no more open than the file inside it: a directory
        // another account can list is one that says how much the user dictates
        // and when, without ever being read.
        //
        // Closed every time rather than at the moment it is made, because it is
        // usually not Cheppu's History that made it. The Engine Download gets
        // there first on nearly every machine — Onboarding fetches 480 MB into
        // `Cheppu/Engine` before anybody has dictated anything — and the
        // attributes handed to `createDirectory` are ignored for a directory
        // that is already there.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: HistoryFile.aFolderOnlyTheUsersOwn], ofItemAtPath: folder.path)

        let lines = try history.entries.map { entry in
            String(decoding: try JSONEncoder().encode(HistoryFile.Line(entry)), as: UTF8.self)
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file, options: .atomic)

        // Set every time rather than once. Writing atomically means writing a
        // new file and moving it into place, so the permissions of the one that
        // was there are not necessarily the permissions of the one that
        // replaced it.
        try FileManager.default.setAttributes(
            [.posixPermissions: HistoryFile.onlyTheUsersOwn], ofItemAtPath: file.path)
    }
}
