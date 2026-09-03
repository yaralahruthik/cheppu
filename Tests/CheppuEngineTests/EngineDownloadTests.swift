import CheppuCore
import Foundation
import Testing

@testable import CheppuEngine

// These tests drive the Engine Download the way a first launch does — ask what
// the Engine weighs, fetch it, be interrupted, come back — against a repository
// that answers from memory. Nothing here opens a connection or writes anywhere
// but a directory the test made.
@Suite("Engine Download")
struct EngineDownloadTests {
    /// A repository holding a small Engine, a directory to assemble it in, and
    /// the download that joins them.
    private struct Scenario {
        let repository = FakeRepository()
        let directory: URL

        init() {
            directory = FileManager.default.temporaryDirectory
                .appending(path: "cheppu-engine-\(UUID().uuidString)")

            // The files FluidAudio will open, at a size a test can hold.
            for bundle in EngineFiles.bundles.sorted() {
                repository.publish("\(bundle)/coremldata.bin", bytes: 64)
                repository.publish("\(bundle)/model.mil", bytes: 4_096)
            }
            repository.publish(EngineFiles.vocabulary, bytes: 512)

            // What else the repository carries: the other precisions, the other
            // joints, and the sources they were compiled from.
            repository.publish("EncoderInt4.mlmodelc/model.mil", bytes: 100_000)
            repository.publish("mlpackages/Encoder.mlpackage/Manifest.json", bytes: 100_000)
            repository.publish("README.md", bytes: 1_000)
        }

        func download(reportEvery: Int64 = 1_000_000) -> EngineDownload {
            EngineDownload(
                directory: directory,
                configuration: repository.configuration,
                host: repository.host,
                reportEvery: reportEvery
            )
        }

        /// Everything the download reported, in order.
        @discardableResult
        func run(_ download: EngineDownload) async throws -> [EngineDownloadProgress] {
            let reports = Reports()
            try await download.run { reports.append($0) }
            return reports.everything
        }

        func onDisk(_ path: String) -> Data? {
            try? Data(contentsOf: directory.appending(path: path))
        }

        func isEngineComplete() async -> Bool {
            EngineDownload.isEngineComplete(in: directory)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// The reports a download made. A class because the download hands them over
    /// from whichever thread the bytes arrived on.
    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var reports: [EngineDownloadProgress] = []

        func append(_ report: EngineDownloadProgress) {
            lock.withLock { reports.append(report) }
        }

        var everything: [EngineDownloadProgress] {
            lock.withLock { reports }
        }
    }

    private static let engineBytes = Int64(
        EngineFiles.bundles.count * (64 + 4_096) + 512)

    @Test("The total is what the Engine weighs, not what the repository holds")
    func theTotalIsWhatTheEngineWeighs() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        let files = try await scenario.download().filesOnOffer()

        #expect(files.reduce(0) { $0 + $1.bytes } == Self.engineBytes)
        #expect(!files.contains { $0.path.hasPrefix("EncoderInt4") })
        #expect(!files.contains { $0.path.hasPrefix("mlpackages") })
        #expect(!files.contains { $0.path == "README.md" })
    }

    @Test("A download puts every file the Engine needs on the machine")
    func aDownloadPutsEveryFileTheEngineNeedsOnTheMachine() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        try await scenario.run(scenario.download())

        for bundle in EngineFiles.bundles {
            #expect(scenario.onDisk("\(bundle)/model.mil") == scenario.repository.body(of: "\(bundle)/model.mil"))
        }
        #expect(
            scenario.onDisk(EngineFiles.vocabulary)
                == scenario.repository.body(of: EngineFiles.vocabulary))
    }

    @Test("Nothing the Engine does not open is fetched")
    func nothingTheEngineDoesNotOpenIsFetched() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        try await scenario.run(scenario.download())

        #expect(scenario.onDisk("EncoderInt4.mlmodelc/model.mil") == nil)
        #expect(scenario.onDisk("README.md") == nil)
    }

    @Test("Progress runs from nothing to the whole Engine")
    func progressRunsFromNothingToTheWholeEngine() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        let reports = try await scenario.run(scenario.download(reportEvery: 1))

        #expect(reports.first == EngineDownloadProgress(downloadedBytes: 0, totalBytes: Self.engineBytes))
        #expect(
            reports.last
                == EngineDownloadProgress(
                    downloadedBytes: Self.engineBytes, totalBytes: Self.engineBytes))
        #expect(reports.allSatisfy { $0.totalBytes == Self.engineBytes })
    }

    @Test("Progress never goes backwards")
    func progressNeverGoesBackwards() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        let reports = try await scenario.run(scenario.download(reportEvery: 1))

        let bytes = reports.map(\.downloadedBytes)
        #expect(bytes == bytes.sorted())
    }

    @Test("A download interrupted partway resumes from where it stopped")
    func aDownloadInterruptedPartwayResumesFromWhereItStopped() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        // Every body ends after 1 kB, which the largest of these files is four
        // times over. A body that ends rather than a connection that fails, so
        // that what is left to resume from is exactly what was sent and the
        // test can name the byte the next attempt has to ask from — see
        // `FakeRepository.truncatesAfter`.
        scenario.repository.truncatesAfter = 1_000
        await #expect(throws: (any Error).self) {
            try await scenario.run(scenario.download())
        }

        let interrupted = scenario.repository.everythingAsked
        scenario.repository.truncatesAfter = nil
        try await scenario.run(scenario.download())

        // Whatever the first attempt was in the middle of is asked for again
        // from the byte it stopped at, not from the beginning.
        let resumed = scenario.repository.everythingAsked.dropFirst(interrupted.count)
        #expect(resumed.contains { $0.range == "bytes=1000-" })

        for bundle in EngineFiles.bundles {
            let path = "\(bundle)/model.mil"
            #expect(scenario.onDisk(path) == scenario.repository.body(of: path))
        }
    }

    @Test("Bytes an interrupted attempt fetched are not fetched again")
    func bytesAnInterruptedAttemptFetchedAreNotFetchedAgain() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())

        let asked = scenario.repository.everythingAsked.count
        let landed = try await scenario.download().filesOnOffer()
            .filter { scenario.onDisk($0.path)?.count == Int($0.bytes) }

        scenario.repository.dropsAfter = nil
        try await scenario.run(scenario.download())

        // What did arrive whole before the connection dropped is on disk
        // already, so the second attempt does not spend the bytes again.
        #expect(!landed.isEmpty)
        let askedAgain = Set(scenario.repository.everythingAsked.dropFirst(asked).map(\.path))
        #expect(landed.allSatisfy { !askedAgain.contains($0.path) })
    }

    @Test("A repository that answers a resume with the whole file still lands the right bytes")
    func aRepositoryThatIgnoresARangeStillLandsTheRightBytes() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())

        // The second attempt asks to carry on and is handed the file from the
        // top. Believing the request rather than the answer would leave the
        // first kilobyte in the file twice.
        scenario.repository.dropsAfter = nil
        scenario.repository.honoursRange = false
        try await scenario.run(scenario.download())

        for bundle in EngineFiles.bundles {
            let path = "\(bundle)/model.mil"
            #expect(scenario.onDisk(path) == scenario.repository.body(of: path))
        }
    }

    @Test("A second launch with the Engine already here fetches nothing")
    func aSecondLaunchWithTheEngineAlreadyHereFetchesNothing() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        try await scenario.run(scenario.download())
        let asked = scenario.repository.everythingAsked.count

        try await scenario.run(scenario.download())

        #expect(scenario.repository.everythingAsked.count == asked)
    }

    @Test("Half-written bytes are never left where a finished file goes")
    func halfWrittenBytesAreNeverLeftWhereAFinishedFileGoes() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())

        // The interrupted file exists only under `.partial`. A crash at any
        // moment therefore leaves either a whole file or no file, never a short
        // one wearing a finished name.
        for bundle in EngineFiles.bundles {
            let path = "\(bundle)/model.mil"
            let landed = scenario.onDisk(path)
            #expect(landed == nil || landed == scenario.repository.body(of: path))
        }
    }

    @Test("Leftover bytes that outgrow the file they belong to are started over")
    func leftoverBytesThatOutgrowTheFileTheyBelongToAreStartedOver() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        // A `.partial` longer than the file it is going to means the leftover is
        // from an older version of it, or from a repository that answered with
        // the wrong length. Either way, carrying on from the end of it would
        // never converge on the right file.
        let path = "\(EngineFiles.bundles.sorted()[0])/model.mil"
        let destination = scenario.directory.appending(path: path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 9_000)
            .write(to: destination.appendingPathExtension("partial"))

        try await scenario.run(scenario.download())

        #expect(scenario.repository.everythingAsked.first { $0.path == path }?.range == nil)
        #expect(scenario.onDisk(path) == scenario.repository.body(of: path))
    }

    @Test("A download cancelled mid-transfer stops rather than hanging")
    func aDownloadCancelledMidTransferStopsRatherThanHanging() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        // The repository goes quiet partway through a file, so the only thing
        // that can end this transfer is the cancellation — which is what happens
        // when someone closes Onboarding while it is downloading.
        scenario.repository.stallsAfter = 100
        let running = Task { try await scenario.run(scenario.download()) }

        // The first file is smaller than the stall point and finishes; the
        // second is the one left hanging, and the one the cancel has to reach.
        while scenario.repository.everythingAsked.count < 2 {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(50))
        running.cancel()

        #expect(await finishes(running), "a cancelled download never returned")
    }

    /// Whether a task is done inside a few seconds, rather than never.
    private func finishes(_ task: Task<some Sendable, some Error>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await task.result
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test("A download killed as its last byte lands is not fetched all over again")
    func aDownloadKilledAsItsLastByteLandsIsNotFetchedAllOverAgain() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        // A `.partial` holding the whole file is a download killed in the moment
        // between the last byte landing and the file being given its name. What
        // it needs is the name — asking for 445 MB again would be the opposite
        // of resuming from where it stopped.
        let path = "\(EngineFiles.bundles.sorted()[0])/model.mil"
        let destination = scenario.directory.appending(path: path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try scenario.repository.body(of: path)
            .write(to: destination.appendingPathExtension("partial"))

        try await scenario.run(scenario.download())

        #expect(!scenario.repository.everythingAsked.contains { $0.path == path })
        #expect(scenario.onDisk(path) == scenario.repository.body(of: path))
    }

    @Test("A resumed download opens where it stopped rather than at nothing")
    func aResumedDownloadOpensWhereItStoppedRatherThanAtNothing() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())

        scenario.repository.dropsAfter = nil
        let reports = try await scenario.run(scenario.download())

        // A bar that restarts at zero on every attempt tells the user their
        // last attempt bought them nothing, which is the opposite of true.
        #expect((reports.first?.downloadedBytes ?? 0) > 0)
    }

    @Test("Progress never goes backwards, even when a resume is answered with the whole file")
    func progressNeverGoesBackwardsEvenWhenAResumeIsAnsweredWithTheWholeFile() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())

        scenario.repository.dropsAfter = nil
        scenario.repository.honoursRange = false
        let reports = try await scenario.run(scenario.download(reportEvery: 1))

        let bytes = reports.map(\.downloadedBytes)
        #expect(bytes == bytes.sorted())
    }

    @Test("A file whose bytes are not the bytes that were published is refused")
    func aFileWhoseBytesAreNotTheBytesThatWerePublishedIsRefused() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        // Cheppu runs these bytes as a model. The right length is not enough:
        // a proxy or a mirror that serves something else of the same size must
        // not be able to put it where the Engine will load it from.
        scenario.repository.corruptsBodies = true

        await #expect(throws: (any Error).self) {
            try await scenario.run(scenario.download())
        }
        #expect(await scenario.isEngineComplete() == false)
    }

    @Test("An Engine is only complete once a download has finished recording it")
    func anEngineIsOnlyCompleteOnceADownloadHasFinishedRecordingIt() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        scenario.repository.dropsAfter = 1_000
        _ = try? await scenario.run(scenario.download())
        #expect(await scenario.isEngineComplete() == false)

        scenario.repository.dropsAfter = nil
        try await scenario.run(scenario.download())
        #expect(await scenario.isEngineComplete())
    }

    @Test("A repository that has stopped publishing the Engine says so")
    func aRepositoryThatHasStoppedPublishingTheEngineSaysSo() async throws {
        let scenario = Scenario()
        defer { scenario.cleanUp() }

        let elsewhere = FakeRepository()
        elsewhere.publish("README.md", bytes: 10)
        let download = EngineDownload(
            directory: scenario.directory,
            configuration: elsewhere.configuration,
            host: elsewhere.host
        )

        await #expect(throws: EngineDownload.Failure.engineNotInRepository) {
            _ = try await download.filesOnOffer()
        }
    }
}
