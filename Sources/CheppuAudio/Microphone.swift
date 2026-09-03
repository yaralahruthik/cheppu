import AVFoundation
import Foundation

/// Something has gone wrong with the microphone.
///
/// Three ways, and the user can tell them apart: they said no, there is nothing
/// to listen with, and Cheppu asked in the wrong order.
public enum MicrophoneFailure: Error, Equatable {
    /// Microphone access was refused, or granted once and taken away since.
    case accessDenied

    /// There is no input device to open — none attached, or the one that was
    /// there has gone.
    case noMicrophone

    /// Capture was stopped without having been started. Cheppu's own mistake
    /// rather than the user's, and said out loud rather than answered with an
    /// empty Dictation, which would look like a Dictation that heard nothing.
    case notCapturing
}

/// Whether Cheppu may listen.
///
/// A seam so that the suite can answer for the user — grant, refuse, or grant
/// and then take it back — without a real prompt and without the machine
/// running the tests ending up with a Microphone grant of its own.
protocol MicrophoneAccess: Sendable {
    /// Asks for Microphone access, answering whether Cheppu may listen.
    func request() async -> Bool
}

/// The audio device itself.
///
/// Narrow on purpose: open it, be handed what it hears, close it. Everything
/// else about capture — when access is asked for, what is kept, what is let go
/// of, and how loud it reads — sits above this line and is tested there.
protocol Microphone: Sendable {
    /// Opens the device, answering with the rate it opened at.
    ///
    /// Buffers arrive on whatever thread the system fills them on, which is one
    /// that cannot afford to wait, so the hand-over does not suspend.
    func open(_ heard: @escaping @Sendable ([Float]) -> Void) throws -> Double

    /// Closes the device.
    func close()
}

/// The Mac's microphone, by way of `AVAudioEngine`.
///
/// The engine and its tap are only ever touched from `MicrophoneCapture`, an
/// actor, which is what serializes them; the tap block that runs on the audio
/// thread touches nothing this class owns.
final class SystemMicrophone: Microphone, @unchecked Sendable {
    private let engine = AVAudioEngine()

    /// Frames per buffer. At the 48 kHz a Mac's microphone usually opens at
    /// this is 85 ms, which is about as often as a level is worth redrawing and
    /// far more often than the ear needs to be convinced the Pill is live.
    private static let bufferSize: AVAudioFrameCount = 4_096

    func open(_ heard: @escaping @Sendable ([Float]) -> Void) throws -> Double {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // A Mac with no input device answers with a format of no channels at no
        // rate rather than by failing, and starting the engine on that would be
        // a Dictation that listened to nothing and said nothing about it.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneFailure.noMicrophone
        }

        input.installTap(onBus: 0, bufferSize: Self.bufferSize, format: format) { buffer, _ in
            heard(Self.mono(buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        return format.sampleRate
    }

    func close() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    /// The buffer as the one channel a Dictation is made of.
    ///
    /// Averaged rather than taking the first channel, so that a stereo or
    /// aggregate input whose speech is on the second channel is not silence.
    /// The rate is left alone: what the microphone opened at is not what the
    /// Engine wants, and converting to the Engine's rate is the Engine's to do.
    private static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 1 else {
            return Array(UnsafeBufferPointer(start: channels[0], count: frames))
        }

        return (0..<frames).map { frame in
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += channels[channel][frame]
            }
            return sum / Float(channelCount)
        }
    }
}

/// Microphone access as macOS answers it.
struct SystemMicrophoneAccess: MicrophoneAccess {
    /// Prompts the first time, with the one sentence in `NSMicrophoneUsageDescription`
    /// saying why, and answers from the existing decision every time after —
    /// including answering no, without a prompt, for a grant the user has since
    /// taken away in System Settings.
    func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
