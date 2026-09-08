/// How far the Engine Download has got.
///
/// Bytes on both sides rather than a fraction alone, because the question a
/// 600 MB download provokes is "how much longer", and only a total can answer
/// it. A bare percentage reads the same whether the remainder is ten seconds or
/// ten minutes, which is how a download comes to look like a stall.
public struct EngineDownloadProgress: Equatable, Sendable {
    /// What is on the machine so far, counting whatever an interrupted attempt
    /// left behind.
    public let downloadedBytes: Int64

    /// What the whole Engine weighs.
    public let totalBytes: Int64

    public init(downloadedBytes: Int64, totalBytes: Int64) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    /// What has arrived and what there is, in the words the user reads under
    /// the bar: "212 MB of 604 MB".
    ///
    /// Megabytes of a million bytes, as the Finder and the App Store count
    /// them, and whole ones: a first decimal place moving ten times a second is
    /// noise, and the question this answers is "how much longer" rather than
    /// "exactly how far".
    ///
    /// Spelled out here rather than by `ByteCountFormatter`, which is the
    /// obvious way to write this and the wrong one twice over: it belongs to a
    /// framework the core does not import, and what it produces depends on the
    /// machine's locale, which would make this sentence something the suite
    /// could only assert about the machine it happened to run on.
    public var howFarAlong: String {
        "\(Self.megabytes(downloadedBytes)) MB of \(Self.megabytes(totalBytes)) MB"
    }

    /// Bytes, to the nearest megabyte. Rounded rather than truncated, so that a
    /// download one byte short of its total does not read as a megabyte short
    /// of it.
    private static func megabytes(_ bytes: Int64) -> Int64 {
        (bytes + 500_000) / 1_000_000
    }

    /// How far along, in [0, 1].
    ///
    /// Nothing to fetch reads as finished rather than as a division by zero, and
    /// a report that overshoots its total is held at 1 — a progress bar that
    /// goes backwards or past the end costs more trust than the precision is
    /// worth.
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 1 }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }
}
