import CheppuCore
import FluidAudio
import Foundation

/// The Engine: NVIDIA Parakeet TDT v3 on CoreML, behind the two ports that
/// describe it — one to put it on the machine, one to ask it what was said.
///
/// The models are loaded once and kept. Loading them takes seconds, and the
/// latency budget for a Dictation is a breath, so the cost is paid on the first
/// transcription of a run and never again.
public actor ParakeetEngine: EnginePort, EngineDownloadPort {
    public enum Failure: Error, Equatable {
        /// Asked to transcribe before the Engine was on the machine. The
        /// Onboarding ticket is what makes sure this never reaches a user; until
        /// then it is the honest answer rather than a silent 480 MB download in
        /// the middle of someone's sentence.
        case engineNotDownloaded
    }

    private let directory: URL
    private let configuration: URLSessionConfiguration

    private var manager: AsrManager?

    /// The Engine, reading and writing its files under Application Support.
    public init() throws {
        self.init(
            directory: EngineFiles.directory(
                inApplicationSupport: try EngineFiles.defaultApplicationSupport()),
            configuration: .ephemeral
        )
    }

    /// The seam the suite uses: a directory that is not the user's, and a session
    /// that is not the network.
    init(directory: URL, configuration: URLSessionConfiguration) {
        self.directory = directory
        self.configuration = configuration

        // FluidAudio will fetch a missing or corrupt model on its own unless it
        // is told not to. Cheppu's promise is that the Engine Download is the
        // only thing that ever reaches the network, and this is what makes that
        // enforceable rather than merely intended: past this line the dependency
        // has no outbound path left, whatever it finds on disk.
        ModelHub.offlineMode = true
    }

    private var download: EngineDownload {
        EngineDownload(directory: directory, configuration: configuration)
    }

    // MARK: - Putting the Engine on the machine

    public func isEngineDownloaded() async -> Bool {
        // Answered from what the last finished download recorded, on disk, so
        // that the ordinary launch — the Engine is already here — asks the
        // network nothing. Checking the directory's shape instead would call an
        // interrupted download finished: a bundle's folder is made before the
        // first byte of it arrives.
        EngineDownload.isEngineComplete(in: directory)
    }

    public func downloadEngine(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws {
        try await download.run(reporting: progress)
    }

    // MARK: - Asking it what was said

    public func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript {
        let manager = try await loadedManager()

        // Parakeet hears 16 kHz mono and nothing else. What the microphone
        // actually opened at is the Audio capture port's business, so the
        // conversion belongs here rather than in a promise made to it.
        let samples =
            audio.sampleRate == Self.engineSampleRate
            ? audio.samples
            : try AudioConverter().resample(audio.samples, from: audio.sampleRate)

        // A decoder state per Dictation, never carried between them: each
        // Dictation is transcribed whole, after it stopped, with no context from
        // the one before it (ADR-0002).
        var decoderState = try TdtDecoderState(decoderLayers: EngineFiles.version.decoderLayers)
        let heard = try await manager.transcribe(
            samples, decoderState: &decoderState, language: .english)

        return RawTranscript(text: heard.text, words: Self.wordTimings(of: heard))
    }

    /// The per-word timings Cleanup will need, from the per-token timings the
    /// Engine produces.
    ///
    /// Parakeet decodes sub-word pieces, so "paragraph" can arrive as three
    /// tokens with three separate spans. FluidAudio regroups them on the
    /// word-boundary markers it put there; doing that here would mean
    /// reimplementing its tokenizer's conventions.
    private static func wordTimings(of result: ASRResult) -> [CheppuCore.WordTiming] {
        buildWordTimings(from: result.tokenTimings ?? []).map { timing in
            CheppuCore.WordTiming(
                word: timing.word,
                start: .seconds(timing.startTime),
                end: .seconds(timing.endTime)
            )
        }
    }

    /// What Parakeet hears in.
    private static let engineSampleRate: Double = 16_000

    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        guard await isEngineDownloaded() else { throw Failure.engineNotDownloaded }

        let models = try await AsrModels.load(
            from: directory,
            version: EngineFiles.version,
            encoderPrecision: EngineFiles.encoderPrecision
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        self.manager = manager
        return manager
    }
}
