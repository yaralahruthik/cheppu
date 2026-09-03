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
