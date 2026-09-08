import AVFoundation
import CheppuCore
import Foundation
import Testing

@testable import CheppuEngine

/// The Engine doing its actual job, with the real Parakeet on the machine.
///
/// Off by default, and off in CI, because it needs 480 MB fetched over the
/// network — the one thing the rest of the suite exists to avoid. It answers
/// the question the other tests structurally cannot: does a minute of speech
/// come back in well under a second. Whether the words are *right* is
/// `CheppuAccuracyTests`, which measures a word error rate against audio of the
/// author over there rather than guessing at it here.
///
///     CHEPPU_LIVE_ENGINE=1 swift test --filter LiveEngineTests
///
/// The speech is synthesised with `say` rather than committed, which is all a
/// timing needs: a stopwatch does not care whose voice it is. The audio in the
/// repository is the accuracy corpus, and it is the author's own.
@Suite(
    "Live Engine",
    .enabled(if: ProcessInfo.processInfo.environment["CHEPPU_LIVE_ENGINE"] != nil),
    .serialized
)
struct LiveEngineTests {
    private static let sentence =
        "the quick brown fox jumps over the lazy dog while the engine listens carefully"

    /// The Engine where a developer's machine already keeps it, so running this
    /// twice does not fetch it twice.
    private static func engine() throws -> ParakeetEngine {
        ParakeetEngine(
            directory: EngineFiles.directory(
                inApplicationSupport: try EngineFiles.defaultApplicationSupport()),
            configuration: .default
        )
    }

    /// Speech, made by the machine, at what Parakeet hears in.
    private static func speak(_ words: String) throws -> CapturedAudio {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "cheppu-said-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: file) }

        // Straight to what Parakeet hears in, so the fixture exercises the
        // Engine rather than the resampling on the way to it.
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = [
            "-o", file.path, "--file-format=WAVE", "--data-format=LEF32@16000", words,
        ]
        try say.run()
        say.waitUntilExit()
        try #require(say.terminationStatus == 0, "say could not record the fixture")

        let audio = try AVAudioFile(forReading: file)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: audio.fileFormat.sampleRate,
            channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.length))!
        try audio.read(into: buffer)

        return CapturedAudio(
            samples: Array(
                UnsafeBufferPointer(
                    start: buffer.floatChannelData![0], count: Int(buffer.frameLength))),
            sampleRate: audio.fileFormat.sampleRate
        )
    }

    @Test("The Engine downloads, and says how big it is while it does")
    func theEngineDownloadsAndSaysHowBigItIsWhileItDoes() async throws {
        let engine = try Self.engine()
        let reports = CollectedReports()

        try await engine.downloadEngine { reports.record($0) }

        #expect(await engine.isEngineDownloaded())
        let seen = reports.everything
        #expect(seen.first?.totalBytes ?? 0 > 400_000_000)
        #expect(seen.last?.fractionCompleted == 1)
    }

    @Test("Audio in, the words that were said out, with a timing for each")
    func audioInTheWordsThatWereSaidOut() async throws {
        let engine = try Self.engine()
        try await engine.downloadEngine { _ in }

        let heard = try await engine.transcribe(Self.speak(Self.sentence))

        let words = heard.text.lowercased().split(separator: " ").map(String.init)
        #expect(words.contains("fox"))
        #expect(words.contains("jumps"))
        #expect(!heard.words.isEmpty)

        // Cleanup places Paragraph Breaks on the gaps between these, so they have
        // to run forwards and in order.
        #expect(heard.words.allSatisfy { $0.start <= $0.end })
        #expect(zip(heard.words, heard.words.dropFirst()).allSatisfy { $0.start <= $1.start })
    }

    @Test("A minute of speech comes back in well under a second")
    func aMinuteOfSpeechComesBackInWellUnderASecond() async throws {
        let engine = try Self.engine()
        try await engine.downloadEngine { _ in }

        let audio = try Self.speak(String(repeating: Self.sentence + ". ", count: 14))
        #expect(audio.samples.count >= Int(audio.sampleRate * 55))

        // The first transcription of a run pays for loading the model; the
        // latency budget in docs/product-experience.md §7 is about the ones after
        // it, which is every Dictation the user actually feels.
        _ = try await engine.transcribe(audio)

        let started = ContinuousClock.now
        _ = try await engine.transcribe(audio)
        let took = ContinuousClock.now - started

        // Printed rather than only asserted: the margin is the interesting part,
        // and it is what tells whoever runs this on other hardware how much room
        // the latency budget still has.
        print("a minute of speech transcribed in \(took)")
        #expect(took < .seconds(1), "a minute of speech took \(took)")
    }
}

/// The progress reports a live download made, gathered from whichever thread the
/// bytes arrived on.
private final class CollectedReports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [EngineDownloadProgress] = []

    func record(_ report: EngineDownloadProgress) {
        lock.withLock { reports.append(report) }
    }

    var everything: [EngineDownloadProgress] {
        lock.withLock { reports }
    }
}
