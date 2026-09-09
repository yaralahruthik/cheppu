import CheppuCore
import Foundation

/// The Spellings, on the disk.
///
/// The store holds them and hands them back; what order they come in, what
/// adding the same word twice means and what a Correction leaves behind are the
/// core's (`Spellings` and `Correction`), so that the promises the user was
/// made are not made again here in a different shape.
///
/// It is an actor for the reasons `HistoryStore` is: a Dictation reads it from
/// wherever the core is running while the History window writes to it from the
/// main thread, and the file must never be two half-written files at once.
public actor SpellingsStore: SpellingsPort {
    private let locate: @Sendable () throws -> URL
    private var located: URL?

    /// What the file holds, once it has been read.
    ///
    /// Kept in hand because the Engine asks for this on the stop-to-insert path
    /// of every Dictation made by somebody who has ever corrected a word
    /// (`docs/product-experience.md` §7).
    private var spellings: Spellings?

    /// The Spellings where Cheppu keeps them: one file in the user's own
    /// Application Support, beside History.
    public init() {
        self.locate = { try SpellingsFile.defaultLocation() }
    }

    /// - Parameter url: the file to keep them in. The suite uses this to write
    ///   somewhere of its own; Cheppu itself never passes it.
    public init(keptAt url: URL) {
        self.locate = { url }
    }

    /// Everything the user has taught Cheppu.
    ///
    /// A file that cannot be read is no Spellings rather than a failure: the
    /// Dictation asking is on its way to the Engine, and a word spelt the way
    /// the Engine hears it is a far smaller loss than a Dictation that failed.
    public func spellings() async -> Spellings {
        readIfNeeded()
    }

    /// Keeps what a Correction left behind.
    ///
    /// Nothing at all is not a write: a Correction outside a Spelling's bounds
    /// teaches nothing, silently, and a file rewritten to say exactly what it
    /// already said would be a disk touched for nothing.
    @discardableResult
    public func keep(_ more: [Spelling]) async throws -> Spellings {
        let kept = readIfNeeded().adding(more)
        guard kept != spellings else { return kept }

        try write(kept)
        spellings = kept
        return kept
    }

    /// Forgets one Spelling, which is what the user does about one they suspect
    /// of misfiring on a word they meant.
    @discardableResult
    public func forget(_ spelling: Spelling) async throws -> Spellings {
        let kept = readIfNeeded().removing(spelling)
        guard kept != spellings else { return kept }

        try write(kept)
        spellings = kept
        return kept
    }

    /// Forgets all of them, in the one action the Settings row is.
    ///
    /// The file is removed rather than emptied, for the reason History's is:
    /// what the user asked for is that Cheppu is no longer keeping these, and a
    /// file holding the shape of them is still keeping something.
    ///
    /// It empties Spellings and only Spellings. Emptying History does not
    /// perform this, and this does not perform that.
    public func forgetEverything() async throws {
        let file = try locateOnce()
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        spellings = Spellings()
    }

    private func locateOnce() throws -> URL {
        if let located { return located }
        let file = try locate()
        located = file
        return file
    }

    private func readIfNeeded() -> Spellings {
        if let spellings { return spellings }

        let kept = Spellings(onDisk())
        spellings = kept
        return kept
    }

    /// What the file holds, skipping any line that cannot be read — and any
    /// word that is no longer one Cheppu could ask the Engine to listen for,
    /// because the bounds belong to `Spelling` and a file edited by hand is
    /// held to them too.
    private func onDisk() -> [Spelling] {
        guard let file = try? locateOnce(),
            let contents = try? String(contentsOf: file, encoding: .utf8)
        else { return [] }

        return
            contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let bytes = line.data(using: .utf8),
                    let read = try? JSONDecoder().decode(SpellingsFile.Line.self, from: bytes)
                else { return nil }
                return read.spelling
            }
    }

    private func write(_ spellings: Spellings) throws {
        let file = try locateOnce()
        let folder = file.deletingLastPathComponent()

        // The folder is closed on every write for the reason History closes it:
        // it is usually not this file that made it, and the attributes handed
        // to `createDirectory` are ignored for a directory that is already
        // there.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: SpellingsFile.aFolderOnlyTheUsersOwn], ofItemAtPath: folder.path)

        let lines = try spellings.entries.map { spelling in
            String(decoding: try JSONEncoder().encode(SpellingsFile.Line(spelling)), as: UTF8.self)
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: file, options: .atomic)

        // Set every time rather than once: writing atomically replaces the
        // file, so the permissions of the one that was there are not
        // necessarily the permissions of the one that replaced it.
        try FileManager.default.setAttributes(
            [.posixPermissions: SpellingsFile.onlyTheUsersOwn], ofItemAtPath: file.path)
    }
}
