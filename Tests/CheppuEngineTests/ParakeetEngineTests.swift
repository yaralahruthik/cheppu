import CheppuCore
import FluidAudio
import Foundation
import Testing

@testable import CheppuEngine

// What the Engine does before it has anything to run: what it says when the
// model is not on the machine, and what it does not do about that. Transcribing
// for real needs 480 MB of Parakeet, which is why it is not asserted here.
@Suite("Parakeet Engine")
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

    /// Puts the shape of a downloaded Engine on disk: the bundles as directories
    /// and the vocabulary as a file.
    private static func fakeADownloadedEngine(in directory: URL) throws {
        for bundle in EngineFiles.bundles {
            try FileManager.default.createDirectory(
                at: directory.appending(path: bundle), withIntermediateDirectories: true)
        }
        try Data().write(to: directory.appending(path: EngineFiles.vocabulary))
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

    @Test("An Engine missing its vocabulary is not ready")
    func anEngineMissingItsVocabularyIsNotReady() async throws {
        let directory = Self.emptyDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.fakeADownloadedEngine(in: directory)
        try FileManager.default.removeItem(at: directory.appending(path: EngineFiles.vocabulary))

        #expect(await Self.engine(in: directory).isEngineDownloaded() == false)
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
