import CheppuCore
import Foundation

/// Where History is kept, and what one line of it looks like.
enum HistoryFile {
    /// One Dictation per line, rather than one document holding all of them.
    ///
    /// Whatever damages the file — a bad block, a backup restored halfway, a
    /// copy that stopped — takes the lines it landed on and leaves the rest
    /// readable. A single JSON document is one syntax error away from being no
    /// History at all, and History is the thing that is meant to survive the
    /// moments nothing else did (`docs/product-experience.md` §4).
    ///
    /// It is also a format the user can read with `cat` and delete with `rm`.
    /// A store that had to be trusted, rather than looked at, would be an odd
    /// way to keep a promise about privacy.
    static let name = "History.jsonl"

    /// Readable and writable by its owner, and by nobody else. A History anyone
    /// with an account on the machine could open would be a transcript of
    /// everything the user has said this week.
    static let onlyTheUsersOwn: Int = 0o600

    /// The same, for the folder around it: no other account may list it, let
    /// alone read what is inside.
    static let aFolderOnlyTheUsersOwn: Int = 0o700

    /// `~/Library/Application Support/Cheppu/History.jsonl`.
    ///
    /// Application Support in the user's own domain, which is a folder that
    /// belongs to this account, is not shared with another one, and is not
    /// synced anywhere — unlike Documents or Desktop, which on a machine with
    /// iCloud Drive switched on are copied off it. Under `Cheppu/`, alongside
    /// the Engine, so that everything Cheppu has put on the machine sits in one
    /// place the user can find and delete.
    /// Worked out rather than made: nothing is created by asking where History
    /// goes. The folder is made by the write that needs it, which is also where
    /// it is closed to everybody but its owner.
    static func defaultLocation() throws -> URL {
        try FileManager.default
            .url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: false
            )
            .appendingPathComponent("Cheppu", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// One line of the file: what was said, and when.
    ///
    /// A shape of its own rather than the core's `HistoryEntry` made Codable,
    /// because it is what ends up on the user's disk. Two fields, written out
    /// here, is what makes "no audio, no Raw Transcript, and nothing about
    /// which app the words went into" a thing the compiler enforces rather than
    /// a thing the next person to touch this remembers.
    struct Line: Codable {
        let text: String
        let recordedAt: TimeInterval

        init(_ entry: HistoryEntry) {
            self.text = entry.finalText.text
            self.recordedAt = entry.recordedAt.timeIntervalSince1970
        }

        var entry: HistoryEntry {
            HistoryEntry(
                finalText: FinalText(text),
                recordedAt: Date(timeIntervalSince1970: recordedAt)
            )
        }
    }
}
