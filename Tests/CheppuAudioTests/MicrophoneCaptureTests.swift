import CheppuCore
import Foundation
import Testing

@testable import CheppuAudio

// What the Audio capture port does around the device: when it asks to listen,
// what it hands on, what it lets go of, and what it says when it cannot listen
// at all. No microphone is opened here, which is also what stops running the
// suite from asking the terminal for Microphone access.
@Suite("Microphone capture")
struct MicrophoneCaptureTests {
    private static func capture(
        _ microphone: FakeMicrophone,
        access: FakeMicrophoneAccess = FakeMicrophoneAccess(grants: true)
    ) -> MicrophoneCapture {
        MicrophoneCapture(access: access, microphone: microphone)
    }

    /// A buffer of a constant amplitude, long enough to read as itself.
    private static func buffer(at amplitude: Float, frames: Int = 4_096) -> [Float] {
        (0..<frames).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
    }

    // MARK: - Asking to listen

    @Test("Microphone access is asked for when capture is first needed, and not before")
    func microphoneAccessIsAskedForWhenCaptureIsFirstNeededAndNotBefore() async throws {
        let access = FakeMicrophoneAccess(grants: true)
        let capture = Self.capture(FakeMicrophone(), access: access)

        // Nothing has been asked for by building the thing that will ask. The
        // prompt belongs to the first Dictation, not to launch.
        #expect(await access.timesAsked == 0)

        try await capture.startCapturing { _ in }

        #expect(await access.timesAsked == 1)
    }

    @Test("A refused Microphone is a failure the core can act on, not a silent nothing")
    func aRefusedMicrophoneIsAFailureTheCoreCanActOn() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone, access: FakeMicrophoneAccess(grants: false))

        await #expect(throws: MicrophoneFailure.accessDenied) {
            try await capture.startCapturing { _ in }
        }

        // And no device was opened behind the refusal.
        #expect(microphone.timesOpened == 0)
    }

    @Test("Access revoked between Dictations is refused at the next one, not the one after")
    func accessRevokedBetweenDictationsIsRefusedAtTheNextOne() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone, access: FakeMicrophoneAccess(answering: [true, false]))

        try await capture.startCapturing { _ in }
        _ = try await capture.stopCapturing()

        // Access is asked for again every Dictation rather than remembered, so
        // a grant taken away in System Settings is noticed at the next attempt.
        await #expect(throws: MicrophoneFailure.accessDenied) {
            try await capture.startCapturing { _ in }
        }
        #expect(microphone.timesOpened == 1)
    }

    @Test("A microphone that will not open takes the Dictation down with it")
    func aMicrophoneThatWillNotOpenTakesTheDictationDownWithIt() async throws {
        let capture = Self.capture(FakeMicrophone(refuses: true))

        await #expect(throws: FakeMicrophone.WillNotOpen.self) {
            try await capture.startCapturing { _ in }
        }

        // And nothing is left half-open behind it.
        await #expect(throws: MicrophoneFailure.notCapturing) {
            _ = try await capture.stopCapturing()
        }
    }

    // MARK: - What is handed on

    @Test("What the microphone heard is what the Dictation hands on")
    func whatTheMicrophoneHeardIsWhatTheDictationHandsOn() async throws {
        let microphone = FakeMicrophone(opensAt: 44_100)
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        microphone.hears([0.1, -0.2])
        microphone.hears([0.3])
        microphone.hears([-0.4, 0.5])
        let spoken = try await capture.stopCapturing()

        #expect(spoken == CapturedAudio(samples: [0.1, -0.2, 0.3, -0.4, 0.5], sampleRate: 44_100))
    }

    @Test("A Dictation that heard nothing still hands back the rate the microphone opened at")
    func aDictationThatHeardNothingStillHandsBackTheRate() async throws {
        let capture = Self.capture(FakeMicrophone(opensAt: 48_000))

        try await capture.startCapturing { _ in }
        let spoken = try await capture.stopCapturing()

        #expect(spoken == CapturedAudio(samples: [], sampleRate: 48_000))
    }

    @Test("The microphone is closed once the Dictation has stopped")
    func theMicrophoneIsClosedOnceTheDictationHasStopped() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        #expect(microphone.isOpen)

        _ = try await capture.stopCapturing()
        #expect(!microphone.isOpen)
    }

    @Test("A Dictation hears nothing of the one before it")
    func aDictationHearsNothingOfTheOneBeforeIt() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        microphone.hears([0.1, 0.2])
        _ = try await capture.stopCapturing()

        try await capture.startCapturing { _ in }
        microphone.hears([0.9])
        let second = try await capture.stopCapturing()

        // The audio was let go of when it was handed on, so the second
        // Dictation cannot be carrying the first one's words.
        #expect(second.samples == [0.9])
    }

    @Test("The audio is let go of as it is handed on, not at the start of the next Dictation")
    func theAudioIsLetGoOfAsItIsHandedOn() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        microphone.hears([0.1, 0.2])
        let spoken = try await capture.stopCapturing()

        // It had the audio, and now the Dictation on its way to the Engine is
        // the only copy of it. Waiting until the next Dictation to let go would
        // leave several minutes of someone's speech in memory for as long as
        // Cheppu is left alone.
        #expect(spoken.samples == [0.1, 0.2])
        #expect(await !capture.isStillHoldingAudio)
    }

    @Test("Stopping when nothing is capturing says so rather than handing back silence")
    func stoppingWhenNothingIsCapturingSaysSo() async throws {
        let capture = Self.capture(FakeMicrophone())

        await #expect(throws: MicrophoneFailure.notCapturing) {
            _ = try await capture.stopCapturing()
        }
    }

    @Test("Starting again while capturing closes the microphone that was already open")
    func startingAgainWhileCapturingClosesTheMicrophoneThatWasAlreadyOpen() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        microphone.hears([0.1])
        try await capture.startCapturing { _ in }
        microphone.hears([0.9])
        let spoken = try await capture.stopCapturing()

        // The machine never asks for this. If something ever does, an open
        // device left behind would be a microphone running with no Dictation.
        #expect(microphone.timesOpened == 2)
        #expect(spoken.samples == [0.9])
    }

    // MARK: - The level

    @Test("A level is reported for every buffer the microphone heard")
    func aLevelIsReportedForEveryBufferTheMicrophoneHeard() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)
        let reported = ReportedLevels()

        try await capture.startCapturing(reportingLevel: reported.report)
        for _ in 0..<5 {
            microphone.hears(Self.buffer(at: 0.2))
        }
        _ = try await capture.stopCapturing()

        // Continuously, so the Pill is never left holding a reading from a
        // moment ago.
        #expect(await reported.levels.count == 5)
    }

    @Test("The level tracks what is actually being said")
    func theLevelTracksWhatIsActuallyBeingSaid() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)
        let reported = ReportedLevels()

        try await capture.startCapturing(reportingLevel: reported.report)
        microphone.hears(Self.buffer(at: 0.0001))
        microphone.hears(Self.buffer(at: 0.4))
        _ = try await capture.stopCapturing()

        let levels = await reported.levels
        #expect(levels.first == .silent)
        #expect(try #require(levels.last).value > 0.5)
    }

    @Test("Every buffer heard before the Dictation stopped is counted, however late it arrived")
    func everyBufferHeardBeforeTheDictationStoppedIsCounted() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)
        let reported = ReportedLevels()

        try await capture.startCapturing(reportingLevel: reported.report)
        for _ in 0..<200 {
            microphone.hears(Self.buffer(at: 0.2, frames: 512))
        }
        let spoken = try await capture.stopCapturing()

        // Stopping waits for what the device already handed over rather than
        // dropping the tail of the Dictation on the floor.
        #expect(spoken.samples.count == 200 * 512)
        #expect(await reported.levels.count == 200)
    }

    @Test("A Dictation that starts loud does not open on the level of the one before it")
    func aDictationDoesNotOpenOnTheLevelOfTheOneBeforeIt() async throws {
        let microphone = FakeMicrophone()
        let capture = Self.capture(microphone)

        try await capture.startCapturing { _ in }
        microphone.hears(Self.buffer(at: 1))
        _ = try await capture.stopCapturing()

        let reported = ReportedLevels()
        try await capture.startCapturing(reportingLevel: reported.report)
        microphone.hears(Self.buffer(at: 0))
        _ = try await capture.stopCapturing()

        #expect(await reported.levels == [.silent])
    }
}
