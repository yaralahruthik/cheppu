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
    /// Named in full in the Diagnostics Log rather than by the type it is
    /// (`FailureSafeToName`): the cases carry nothing, so there is nothing in
    /// one of them that could be something the user said, and "the Engine is
    /// not on the machine" is worth far more to somebody reading a log than the
    /// name of the enumeration it came out of.
    public enum Failure: Error, Equatable, FailureSafeToName {
        /// Asked to transcribe before the Engine was on the machine. The first
        /// launch is what makes sure a user does not meet this — it has them
        /// fetch the Engine before it has them dictate — and this is what is
        /// left for the machine whose Engine has since been deleted: the honest
        /// answer, rather than a silent 480 MB download in the middle of
        /// someone's sentence.
        case engineNotDownloaded
    }

    private let directory: URL
    private let configuration: URLSessionConfiguration

    /// Where the second part of the Engine is, and the second time the audio is
    /// heard through it — where there is a Spelling to listen for and that part
    /// is on the machine.
    private let spellingsDirectory: URL
    private let spellingsPass: SpellingsPass

    /// What the user has taught Cheppu, and whether Cheppu is listening for it.
    ///
    /// Both read at the Dictation rather than held from launch, exactly as the
    /// Cleanup switches are (ADR-0010): a Spelling left behind a moment ago is
    /// read by the very next thing the user says.
    ///
    /// Nothing on a machine that has never had a Correction on it, which is
    /// what makes the stop-to-insert path of a user who never corrects
    /// unchanged: with no Spellings there is no second pass to skip, and the
    /// question costs one read of a file the store already has in hand.
    private let spellings: (any SpellingsPort)?
    private let switchedOn: (any SpellingsSwitch)?

    /// Where how long the second pass took is written down. Told rather than
    /// asked, like every other note.
    private let diagnostics: (any DiagnosticsPort)?

    private var manager: AsrManager?

    /// The Engine, reading and writing its files under Application Support.
    ///
    /// - Parameters:
    ///   - spellings: what the user has taught Cheppu. Nothing means an Engine
    ///     that never hears anything twice, which is what the suites and the
    ///     Accuracy Corpus use: both Ceilings measure the bare Engine, and a
    ///     Spelling that made the Corpus score better would be a test that had
    ///     stopped measuring the Engine (ADR-0014).
    ///   - switchedOn: whether Spellings are read at all.
    ///   - diagnostics: where how long the second pass took is written down.
    public init(
        readingSpellings spellings: (any SpellingsPort)? = nil,
        when switchedOn: (any SpellingsSwitch)? = nil,
        writingDownTo diagnostics: (any DiagnosticsPort)? = nil
    ) throws {
        let applicationSupport = try EngineFiles.defaultApplicationSupport()
        self.init(
            directory: EngineFiles.directory(inApplicationSupport: applicationSupport),
            spellingsDirectory: EngineFiles.spellingsDirectory(
                inApplicationSupport: applicationSupport),
            configuration: .ephemeral,
            readingSpellings: spellings,
            when: switchedOn,
            writingDownTo: diagnostics
        )
    }

    /// The seam the suite uses: a directory that is not the user's, and a session
    /// that is not the network.
    ///
    /// - Parameter spellingsDirectory: where the second part of the Engine
    ///   lives. Beside the first by default, which is where it lives on a real
    ///   machine; passed separately by a suite whose first part is in a
    ///   temporary directory of its own.
    init(
        directory: URL,
        spellingsDirectory: URL? = nil,
        configuration: URLSessionConfiguration,
        readingSpellings spellings: (any SpellingsPort)? = nil,
        when switchedOn: (any SpellingsSwitch)? = nil,
        writingDownTo diagnostics: (any DiagnosticsPort)? = nil
    ) {
        self.directory = directory
        self.configuration = configuration
        self.spellings = spellings
        self.switchedOn = switchedOn
        self.diagnostics = diagnostics
        let secondPart =
            spellingsDirectory ?? EngineFiles.spellingsDirectory(besideTheFirstPartAt: directory)
        self.spellingsDirectory = secondPart
        self.spellingsPass = SpellingsPass(directory: secondPart)

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

    private var spellingsDownload: EngineDownload {
        EngineDownload(
            directory: spellingsDirectory,
            configuration: configuration,
            part: .onlySpellingsNeedIt)
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

    public func isTheSpellingsPartDownloaded() async -> Bool {
        spellingsPass.isOnTheMachine()
    }

    public func downloadTheSpellingsPart(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws {
        try await spellingsDownload.run(reporting: progress)
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

        let words = Self.wordTimings(of: heard)
        guard let spelt = await readingSpellings(into: heard, over: samples) else {
            return RawTranscript(text: heard.text, words: words)
        }
        return RawTranscript(
            text: spelt, words: Self.wordTimings(words, nowReading: heard.text, as: spelt))
    }

    /// The transcript with the user's Spellings put in where the sound supports
    /// them, or nothing where there was no second pass to run.
    ///
    /// Nothing is the ordinary answer. The pass runs only where the user has
    /// left a Spelling behind, has the switch on, and has the part of the
    /// Engine that can hear one — so the stop-to-insert path of a user who
    /// never corrects is exactly what it was, and the question costs the
    /// Dictation two reads of things already in hand (ADR-0014).
    private func readingSpellings(into heard: ASRResult, over samples: [Float]) async -> String? {
        guard let spellings, await switchedOn?.areSpellingsRead() ?? true else { return nil }

        let taught = await spellings.spellings()
        guard !taught.isEmpty, spellingsPass.isOnTheMachine() else { return nil }

        // Timed rather than left to the gap between two lines: the pass happens
        // inside one move from Transcribing to Inserting, so a stop-to-insert
        // budget that has been missed would otherwise say only that the Engine
        // was slow (ADR-0012, ADR-0014).
        let started = ContinuousClock.now
        let spelt = await spellingsPass.rescoring(
            heard.text, tokenTimings: heard.tokenTimings ?? [], audio: samples, against: taught)
        diagnostics?.record(.spellingsWereRead(ContinuousClock.now - started))

        return spelt
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

    /// The word timings, moved onto the words a Spelling changed.
    ///
    /// Cleanup places a Paragraph Break between two particular words, and takes
    /// the timings up only where its own reading of the text and the Engine's
    /// list of words line up one for one. A Spelling put into the text and not
    /// into the timings would break that line-up and cost the user every
    /// Paragraph Break in the Dictation — for the sake of one word being spelt
    /// right, which is not a trade worth making.
    ///
    /// Each replaced word takes the time of the words it replaced, which is
    /// where it was said. Where the two do not line up to begin with there is
    /// nothing to move: the timings are handed back untouched, and Cleanup goes
    /// on placing no Paragraph Break, exactly as it would have without a
    /// Spelling.
    private static func wordTimings(
        _ timings: [CheppuCore.WordTiming], nowReading was: String, as now: String
    ) -> [CheppuCore.WordTiming] {
        let before = ChangedSpans.words(in: was)
        let after = ChangedSpans.words(in: now)
        guard before.count == timings.count else { return timings }

        var moved: [CheppuCore.WordTiming] = []
        var taken = 0

        for span in ChangedSpans.between(before, and: after) {
            moved += timings[taken..<span.was.lowerBound]
            taken = span.was.upperBound

            // Where the span replaced nothing there is no time it was said at,
            // so it is given the instant the words around it meet.
            let at = timings[span.was].first?.start ?? moved.last?.end ?? .zero
            let until = timings[span.was].last?.end ?? at
            moved += after[span.now].map {
                CheppuCore.WordTiming(word: $0, start: at, end: until)
            }
        }

        return moved + timings[taken...]
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
