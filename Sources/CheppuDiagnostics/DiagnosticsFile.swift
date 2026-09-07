import Foundation

/// Where the Diagnostics Log is kept, and how much of it there is.
enum DiagnosticsFile {
    /// A plain text file, one thing that happened per line.
    ///
    /// Not JSON, and not a format anything has to be installed to read. The
    /// whole reason the log exists is that a user can look at it before they
    /// decide to send it to somebody, and a file that has to be trusted rather
    /// than read would be asking for exactly the thing Cheppu does not ask for
    /// (`docs/product-experience.md` §10).
    static let name = "Diagnostics.log"

    /// How big one file gets before the next line starts a new one.
    ///
    /// A quarter of a megabyte is some thousands of lines, which is weeks of
    /// ordinary use — far more than anybody diagnosing this morning's problem
    /// needs, and small enough to be attached to a message.
    static let roomForOne = 256 * 1024

    /// Readable and writable by its owner, and by nobody else, exactly as
    /// History is. The log holds none of the user's words, and it still says
    /// how much somebody dictates and when, which is not another account's
    /// business.
    static let onlyTheUsersOwn: Int = 0o600

    /// The same, for the folder around it.
    static let aFolderOnlyTheUsersOwn: Int = 0o700

    /// `~/Library/Application Support/Cheppu/Diagnostics.log`.
    ///
    /// Next to History and the Engine, so that everything Cheppu has put on the
    /// machine is in one folder the user can find, read and drag to the Trash
    /// (ADR-0009). In the user's own domain, which is not shared with a second
    /// account and is not synced off the machine by iCloud Drive.
    ///
    /// Worked out rather than made: nothing is created by asking where the log
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

    /// The log before this one: `Diagnostics.previous.log`, beside it.
    ///
    /// Two files rather than one is what makes the log bounded without making
    /// it forgetful. A single file that was emptied when it filled up would
    /// lose the morning at the moment it filled, which is exactly when
    /// somebody is likely to be looking for it; keeping the one before means
    /// there is always at least a file's worth of history behind the newest
    /// line, and never more than two files' worth on the disk.
    static func theOneBefore(_ file: URL) -> URL {
        file
            .deletingPathExtension()
            .appendingPathExtension("previous")
            .appendingPathExtension(file.pathExtension)
    }
}
