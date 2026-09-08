import AVFoundation
import CheppuCore
import Foundation

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
    /// A new engine per Dictation rather than one kept for the life of the app.
    ///
    /// An engine holds the configuration it was built against, and the default
    /// input can change between two Dictations — headphones plugged in, an
    /// interface woken up. Building it here is how the second Dictation opens
    /// the device the user is actually speaking into.
    private var engine: AVAudioEngine?

    /// Frames per buffer. At the 48 kHz a Mac's microphone usually opens at
    /// this is 85 ms, which is about as often as a level is worth redrawing and
    /// far more often than the ear needs to be convinced the Pill is live.
    private static let bufferSize: AVAudioFrameCount = 4_096

    func open(_ heard: @escaping @Sendable ([Float]) -> Void) throws -> Double {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // The node's output format, not its input format. They are usually the
        // same on a Mac, and when they are not, `installTap` raises an
        // Objective-C exception rather than throwing — which no `catch` here
        // could turn into a failure the core can act on. This is the format the
        // tap is defined against.
        let format = input.outputFormat(forBus: 0)

        // A Mac with no input device answers with a format of no channels at no
        // rate rather than by failing, and starting the engine on that would be
        // a Dictation that listened to nothing and said nothing about it.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureFailure.noMicrophone
        }

        input.installTap(onBus: 0, bufferSize: Self.bufferSize, format: format) { buffer, _ in
            heard(Self.mono(buffer))
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            // What AVFoundation says here is about a device that would not
            // open, and it says it in words no user could act on. The core is
            // told the one thing it can act on instead.
            throw AudioCaptureFailure.noMicrophone
        }

        self.engine = engine
        return format.sampleRate
    }

    func close() {
        guard let engine else { return }
        self.engine = nil

        // The tap comes off before the engine stops, so nothing is left
        // half-attached to an engine on its way down.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

/// Whether Cheppu may listen, as macOS has already answered it.
///
/// Public, and separate from asking, because Settings has to be able to say
/// whether the permission is there without a prompt appearing and without a
/// Dictation being started to find out (`docs/product-experience.md` §9).
/// Asking is the other half, below, and there are two moments worth doing it
/// in: the first launch, where it is the step the user is on, and every
/// Dictation, which asks on its way into the microphone rather than trusting an
/// answer given a month ago.
///
/// Never asked and refused are one answer here. They are a difference to macOS
/// and not to the user: either way Cheppu cannot hear them, and either way the
/// way out is the same pane.
public enum MicrophonePermission {
    public static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Asks for it, which is what puts the macOS prompt on screen the first
    /// time, and answers whether Cheppu may listen.
    ///
    /// Called by Onboarding, where asking is the whole of the step the user is
    /// on, and by nobody else: every Dictation asks for itself, on its way into
    /// the microphone. macOS shows the prompt once and answers from the
    /// decision on record ever afterwards — including answering no, silently,
    /// for a grant that has since been taken away — which is why what this
    /// returns is a screen that moves on rather than a screen that keeps
    /// offering a prompt nobody will see again.
    @discardableResult
    public static func request() async -> Bool {
        await SystemMicrophoneAccess().request()
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
