import CheppuCore
import Foundation

/// The Audio capture port, over a real microphone.
///
/// It holds one Dictation's audio in memory, hands it to the Engine when the
/// Dictation stops, and lets go of it in the same breath. Nothing here opens a
/// file: audio never reaches the disk, which is a property of the code rather
/// than a promise about it, and `Scripts/check-no-audio-reaches-the-disk.sh`
/// keeps it that way.
public actor MicrophoneCapture: AudioCapturePort {
    private let access: any MicrophoneAccess
    private let microphone: any Microphone

    /// One Dictation's audio, and nothing before or after it.
    private var heard: [Float] = []
    private var sampleRate: Double = 0
    private var meter = InputLevelMeter()

    /// What is carrying buffers from the device into this actor, while there is
    /// a Dictation to carry them for.
    private var listening: Listening?

    /// Cheppu's microphone.
    public init() {
        self.init(access: SystemMicrophoneAccess(), microphone: SystemMicrophone())
    }

    /// The seam the suite uses: an answer that is not the user's, and a device
    /// that is not a device.
    init(access: any MicrophoneAccess, microphone: any Microphone) {
        self.access = access
        self.microphone = microphone
    }

    public func startCapturing(
        reporting report: @escaping @Sendable (InputLevel) async -> Void
    ) async throws {
        // Asked for here, at the moment a Dictation needs it, rather than at
        // launch — and asked again every Dictation rather than remembered, so
        // that a grant taken away in System Settings is refused at the next
        // attempt instead of failing somewhere further in
        // (`docs/product-experience.md` §9).
        guard await access.request() else { throw AudioCaptureFailure.accessDenied }

        // Nothing the machine does asks for this, but a device left open with no
        // Dictation behind it would be a microphone running unannounced.
        if listening != nil {
            await stopListening()
        }

        heard = []
        // A fresh meter, so a Dictation never opens still falling from the last
        // thing the one before it heard.
        meter = InputLevelMeter()

        // The device fills buffers on a thread that cannot wait, and the core
        // it is filling them for is an actor. The stream is what stands between
        // the two: yielding never blocks, and what is yielded arrives here in
        // the order it was heard rather than in the order tasks happen to run.
        let (buffers, arriving) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded)

        do {
            sampleRate = try microphone.open { arriving.yield($0) }
        } catch {
            arriving.finish()
            throw error
        }

        let carrying = Task { [weak self] in
            for await buffer in buffers {
                guard let level = await self?.take(buffer) else { return }
                await report(level)
            }
        }
        listening = Listening(arriving: arriving, carrying: carrying)
    }

    public func stopCapturing() async throws -> CapturedAudio {
        guard listening != nil else { throw AudioCaptureFailure.notCapturing }
        await stopListening()

        let spoken = CapturedAudio(samples: heard, sampleRate: sampleRate)
        // Let go of it as it is handed on. From here the audio exists in one
        // place, on its way to the Engine, and stops existing when that is done.
        heard = []
        return spoken
    }

    /// Closes the device and waits for everything it already handed over.
    ///
    /// The wait is what makes the end of a Dictation the end of a Dictation:
    /// buffers still in flight are the last thing the user said, and dropping
    /// them would cut the final word off.
    private func stopListening() async {
        guard let listening else { return }
        self.listening = nil

        microphone.close()
        listening.arriving.finish()
        await listening.carrying.value
    }

    /// Takes one buffer: keeps it, and reads how loud it was.
    private func take(_ buffer: [Float]) -> InputLevel {
        heard.append(contentsOf: buffer)
        return meter.hearing(buffer, at: sampleRate)
    }

    /// Whether a Dictation's audio is still being held here.
    ///
    /// Only the suite asks. It is the one way to state the promise that audio
    /// does not outlive the Dictation that produced it, rather than merely that
    /// the next Dictation cannot hear the last one.
    var isStillHoldingAudio: Bool { !heard.isEmpty }

    /// A Dictation's audio on its way in.
    private struct Listening {
        let arriving: AsyncStream<[Float]>.Continuation
        let carrying: Task<Void, Never>
    }
}
