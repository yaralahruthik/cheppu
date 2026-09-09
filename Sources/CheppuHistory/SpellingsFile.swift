import CheppuCore
import Foundation

/// Where Spellings are kept, and what one line of the file looks like.
///
/// A file of their own beside `History.jsonl`, under the same discipline
/// (ADR-0009 and ADR-0014): one to a line, readable with `cat`, deletable with
/// `rm`, `0600` in a `0700` folder, in the user's own Application Support and
/// nowhere shared or synced.
///
/// Their own file rather than more of History because they outlive it.
/// Emptying History is the user asking Cheppu to forget what they said; the
/// Spellings are what they taught it, and are useful after the Dictations they
/// came from are gone. Each has an emptying action of its own, and neither
/// performs the other's.
enum SpellingsFile {
    /// One Spelling per line, for the reason History is one Dictation per line:
    /// whatever damages the file takes the lines it landed on and leaves the
    /// rest readable.
    static let name = "Spellings.jsonl"

    /// Readable and writable by its owner, and by nobody else. A word somebody
    /// has taught Cheppu is a word they say.
    static let onlyTheUsersOwn: Int = 0o600

    /// The same, for the folder around it — the one History and the Engine are
    /// already in.
    static let aFolderOnlyTheUsersOwn: Int = 0o700

    /// `~/Library/Application Support/Cheppu/Spellings.jsonl`.
    ///
    /// Application Support in the user's own domain, beside History and the
    /// Engine, for the reasons `HistoryFile` gives: it belongs to this account,
    /// is not shared with another, and is not synced off the machine the way
    /// Documents and Desktop are.
    static func defaultLocation() throws -> URL {
        try FileManager.default
            .url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                create: false
            )
            .appendingPathComponent("Cheppu", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// One line of the file: the word, and nothing else.
    ///
    /// One field, written out here, is what makes "a Spelling holds the word as
    /// the user wants it and nothing of what the Engine heard" a thing the
    /// compiler enforces rather than a thing the next person to touch this
    /// remembers (ADR-0014).
    struct Line: Codable {
        let text: String

        init(_ spelling: Spelling) {
            self.text = spelling.text
        }

        var spelling: Spelling? {
            Spelling(text)
        }
    }
}
