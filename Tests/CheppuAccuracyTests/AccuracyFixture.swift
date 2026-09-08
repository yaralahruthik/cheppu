import AVFoundation
import CheppuCore
import Foundation

/// One piece of the author speaking, and the words they actually said.
///
/// The author's own voice and vocabulary rather than a public benchmark set,
/// because what this measures is whether Cheppu hears *this* user — their
/// accent, the proper nouns they use, the technical terms they say all day. A
/// good score on somebody else's read-aloud corpus would say nothing about
/// whether the app is usable.
///
/// A fixture is two files sharing a name: `<name>.wav`, at exactly what
/// Parakeet hears in, and `<name>.txt`, the reference transcript. The audio is
/// read on demand rather than at load, so that checking the fixtures are
/// well-formed does not mean decoding minutes of speech.
struct AccuracyFixture: Sendable {
    /// What the fixture is called, which is what a failing run names.
    let name: String

    /// The audio itself.
    let audioFile: URL

    /// What was said, written down by the person who said it.
    let reference: String

    /// What Parakeet hears in, and what the fixtures are committed at, so that
    /// the measurement is of the Engine rather than of a resampler on the way
    /// to it.
    static let sampleRate: Double = 16_000

    enum Failure: Error, CustomStringConvertible {
        case noFixturesCommitted(URL)
        case audioWithoutAReference(String)
        case referenceWithoutAudio(String)
        case emptyReference(String)
        case wrongShape(name: String, sampleRate: Double, channels: UInt32)

        var description: String {
            switch self {
            case .noFixturesCommitted(let directory):
                return """
                    no accuracy fixtures are committed in \(directory.path). \
                    Add one with Scripts/add-an-accuracy-fixture.sh — the harness \
                    measures nothing without them.
                    """
            case .audioWithoutAReference(let name):
                return "\(name).wav has no \(name).txt saying what was said in it"
            case .referenceWithoutAudio(let name):
                return "\(name).txt has no \(name).wav to measure it against"
            case .emptyReference(let name):
                return "\(name).txt is empty, so there is nothing to measure against"
            case .wrongShape(let name, let sampleRate, let channels):
                return """
                    \(name).wav is \(Int(sampleRate)) Hz in \(channels) channel(s); \
                    fixtures are committed at \(Int(AccuracyFixture.sampleRate)) Hz mono so that \
                    what is measured is the Engine and not a resampler. \
                    Scripts/add-an-accuracy-fixture.sh converts a file to it.
                    """
            }
        }
    }

    /// Every fixture committed to the repository, in a fixed order so that two
    /// runs report the same thing in the same sequence.
    ///
    /// Throws rather than skips when a fixture is malformed: a pair that has
    /// lost half of itself is a fixture silently dropped from the corpus, and a
    /// corpus that quietly shrinks is a ceiling that quietly stops meaning
    /// anything.
    static func committed() throws -> [AccuracyFixture] {
        let directory = Self.directory
        let everything = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)

        let audio = Set(
            everything.filter { $0.pathExtension == "wav" }.map { $0.deletingPathExtension()
                .lastPathComponent })
        let references = Set(
            everything.filter { $0.pathExtension == "txt" }.map { $0.deletingPathExtension()
                .lastPathComponent })

        if audio.isEmpty, references.isEmpty { throw Failure.noFixturesCommitted(directory) }
        if let orphan = audio.subtracting(references).min() {
            throw Failure.audioWithoutAReference(orphan)
        }
        if let orphan = references.subtracting(audio).min() {
            throw Failure.referenceWithoutAudio(orphan)
        }

        return try audio.sorted().map { name in
            let reference = try String(
                contentsOf: directory.appending(path: "\(name).txt"), encoding: .utf8)
            guard !WordErrorRate.words(in: reference).isEmpty else {
                throw Failure.emptyReference(name)
            }
            return AccuracyFixture(
                name: name,
                audioFile: directory.appending(path: "\(name).wav"),
                reference: reference)
        }
    }

    /// Where the fixtures sit inside the built test bundle.
    static var directory: URL {
        Bundle.module.resourceURL!.appending(path: "Fixtures", directoryHint: .isDirectory)
    }

    /// The audio, as a Dictation would have handed it to the Engine.
    ///
    /// Refuses anything that is not already 16 kHz mono, so that a fixture
    /// added at 48 kHz cannot quietly change what the corpus measures.
    func audio() throws -> CapturedAudio {
        let file = try AVAudioFile(forReading: audioFile)
        let committed = file.fileFormat

        guard committed.sampleRate == Self.sampleRate, committed.channelCount == 1 else {
            throw Failure.wrongShape(
                name: name, sampleRate: committed.sampleRate, channels: committed.channelCount)
        }

        // Read as float32 whatever the file stores, which is what the microphone
        // hands the Engine and what the Engine reads.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: committed.sampleRate,
            channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)

        return CapturedAudio(
            samples: Array(
                UnsafeBufferPointer(
                    start: buffer.floatChannelData![0], count: Int(buffer.frameLength))),
            sampleRate: committed.sampleRate
        )
    }
}
