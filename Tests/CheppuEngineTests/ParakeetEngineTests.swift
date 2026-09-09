import CheppuCore
import FluidAudio
import Foundation
import Testing

@testable import CheppuEngine

// What the Engine does before it has anything to run: what it says when the
// model is not on the machine, and what it does not do about that. Transcribing
// for real needs 480 MB of Parakeet, which is why it is not asserted here.
// `ModelHub.offlineMode` is FluidAudio's own global, so the tests that read it
// run one at a time rather than alongside each other.
@Suite("Parakeet Engine", .serialized)
struct ParakeetEngineTests {
    private static func engine(in directory: URL) -> ParakeetEngine {
        ParakeetEngine(directory: directory, configuration: .ephemeral)
    }

    private static func emptyDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cheppu-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Puts a finished Engine on disk: a file inside each bundle, the
    /// vocabulary, and the manifest a finished download leaves behind.
    @discardableResult
    private static func fakeADownloadedEngine(in directory: URL) throws -> [String] {
        let paths = EngineFiles.bundles.sorted().map { "\($0)/model.mil" } + [EngineFiles.vocabulary]
        let body = Data(repeating: 3, count: 128)

        for path in paths {
            let file = directory.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: file)
        }

        let recorded = paths.map { #"{"path":"\#($0)","bytes":\#(body.count)}"# }
        try Data("[\(recorded.joined(separator: ","))]".utf8)
            .write(to: directory.appending(path: EngineDownload.manifestName))
        return paths
    }

    @Test("Making the Engine takes FluidAudio's own network path away")
    func makingTheEngineTakesFluidAudiosOwnNetworkPathAway() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        ModelHub.offlineMode = false
        _ = Self.engine(in: directory)

        // The Engine Download is the only thing in Cheppu that reaches the
        // network. FluidAudio would otherwise fetch a missing or corrupt model
        // itself, from a path no script of ours can see.
        #expect(ModelHub.offlineMode)
    }

    @Test("An Engine that has not been downloaded says so")
    func anEngineThatHasNotBeenDownloadedSaysSo() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(await Self.engine(in: directory).isEngineDownloaded() == false)
    }

    @Test("An Engine whose files are all present is ready")
    func anEngineWhoseFilesAreAllPresentIsReady() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.fakeADownloadedEngine(in: directory)

        #expect(await Self.engine(in: directory).isEngineDownloaded())
    }

    @Test("An Engine missing one of its files is not ready")
    func anEngineMissingOneOfItsFilesIsNotReady() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.fakeADownloadedEngine(in: directory)
        try FileManager.default.removeItem(at: directory.appending(path: EngineFiles.vocabulary))

        #expect(await Self.engine(in: directory).isEngineDownloaded() == false)
    }

    @Test("An Engine whose folders exist but whose files never arrived is not ready")
    func anEngineWhoseFoldersExistButWhoseFilesNeverArrivedIsNotReady() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // What an interrupted download leaves: every bundle's folder made, and
        // nothing inside it. Reading the directory's shape would call this
        // finished and then fail confusingly on the first Dictation.
        for bundle in EngineFiles.bundles {
            try FileManager.default.createDirectory(
                at: directory.appending(path: bundle), withIntermediateDirectories: true)
        }
        try Data().write(to: directory.appending(path: EngineFiles.vocabulary))

        #expect(await Self.engine(in: directory).isEngineDownloaded() == false)
    }

    @Test("An Engine whose files are short of what was recorded is not ready")
    func anEngineWhoseFilesAreShortOfWhatWasRecordedIsNotReady() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = try Self.fakeADownloadedEngine(in: directory)
        try Data(repeating: 3, count: 8).write(to: directory.appending(path: paths[0]))

        #expect(await Self.engine(in: directory).isEngineDownloaded() == false)
    }

    @Test("The part only Spellings need is a folder of its own, beside the first")
    func thePartOnlySpellingsNeedIsAFolderOfItsOwnBesideTheFirst() throws {
        // Everything Cheppu put on the machine is still one folder, so that
        // what the user deletes when they are done with it is still one drag
        // (ADR-0009, ADR-0014).
        let applicationSupport = URL(filePath: "/tmp/somebodys-application-support")
        let first = EngineFiles.directory(inApplicationSupport: applicationSupport)
        let second = EngineFiles.spellingsDirectory(inApplicationSupport: applicationSupport)

        #expect(first.deletingLastPathComponent() == second.deletingLastPathComponent())
        #expect(first.deletingLastPathComponent().lastPathComponent == "Engine")
        #expect(first != second)
    }

    @Test("An Engine without the part that reads Spellings says so")
    func anEngineWithoutThePartThatReadsSpellingsSaysSo() async throws {
        let directory = Self.emptyDirectory()
        let spellings = Self.emptyDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: spellings)
        }
        try Self.fakeADownloadedEngine(in: directory)

        // The first part being here says nothing about the second: it is a
        // different repository, fetched at a different moment, and only where
        // somebody pressed a button.
        let engine = ParakeetEngine(
            directory: directory, spellingsDirectory: spellings, configuration: .ephemeral)

        #expect(await engine.isEngineDownloaded())
        #expect(await engine.isTheSpellingsPartDownloaded() == false)
    }

    @Test("Asking an Engine that is not here to transcribe says so rather than downloading it")
    func askingAnEngineThatIsNotHereToTranscribeSaysSo() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = Self.engine(in: directory)

        // A Dictation must never turn into a silent 480 MB download in the
        // middle of someone's sentence.
        await #expect(throws: ParakeetEngine.Failure.engineNotDownloaded) {
            _ = try await engine.transcribe(
                CapturedAudio(samples: [0.1, -0.2, 0.3], sampleRate: 16_000))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
