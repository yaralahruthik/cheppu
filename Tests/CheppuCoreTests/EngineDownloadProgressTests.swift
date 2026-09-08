import Testing

@testable import CheppuCore

// What a caller can rely on from a progress report, which is what a progress bar
// and a "213 MB of 483 MB" are both drawn from.
@Suite("Engine Download progress")
struct EngineDownloadProgressTests {
    @Test("Progress is the share of the total that has arrived")
    func progressIsTheShareOfTheTotalThatHasArrived() {
        let report = EngineDownloadProgress(downloadedBytes: 120, totalBytes: 480)

        #expect(report.fractionCompleted == 0.25)
    }

    @Test("Nothing to fetch reads as finished")
    func nothingToFetchReadsAsFinished() {
        // Not a division by zero, and not a bar stuck at the far left: an Engine
        // that weighs nothing is an Engine that is already here.
        #expect(EngineDownloadProgress(downloadedBytes: 0, totalBytes: 0).fractionCompleted == 1)
    }

    @Test("A report past its total is held at the end")
    func aReportPastItsTotalIsHeldAtTheEnd() {
        let report = EngineDownloadProgress(downloadedBytes: 600, totalBytes: 480)

        #expect(report.fractionCompleted == 1)
    }

    @Test("An empty download starts at the beginning")
    func anEmptyDownloadStartsAtTheBeginning() {
        #expect(EngineDownloadProgress(downloadedBytes: 0, totalBytes: 480).fractionCompleted == 0)
    }

    @Test("What has arrived is said in megabytes, with the total beside it")
    func whatHasArrivedIsSaidInMegabytesWithTheTotalBesideIt() {
        // A bare percentage reads the same whether the remainder is ten seconds
        // or ten minutes, which is how a 600 MB download comes to look like a
        // stall.
        let report = EngineDownloadProgress(
            downloadedBytes: 212_000_000, totalBytes: 604_000_000)

        #expect(report.howFarAlong == "212 MB of 604 MB")
    }

    @Test("A download that has not started still says what there is to fetch")
    func aDownloadThatHasNotStartedStillSaysWhatThereIsToFetch() {
        let report = EngineDownloadProgress(downloadedBytes: 0, totalBytes: 604_000_000)

        #expect(report.howFarAlong == "0 MB of 604 MB")
    }

    @Test("A download a byte short of the end does not read as a megabyte short")
    func aDownloadAByteShortOfTheEndDoesNotReadAsAMegabyteShort() {
        // Rounded rather than truncated: a bar at the far right beside a number
        // that is one behind is the app disagreeing with itself.
        let report = EngineDownloadProgress(
            downloadedBytes: 603_999_999, totalBytes: 604_000_000)

        #expect(report.howFarAlong == "604 MB of 604 MB")
    }
}
