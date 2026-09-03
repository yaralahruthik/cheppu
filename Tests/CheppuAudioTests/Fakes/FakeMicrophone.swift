import CheppuCore
import Foundation

@testable import CheppuAudio

/// A microphone that hears what the test says it hears, when the test says so.
///
/// A real one fills buffers on an audio thread, so this hands them over from
/// whatever thread called `hears(_:)` rather than pretending the hand-over is
/// orderly. What is asserted is that everything handed over arrives, in order,
/// however it was delivered.
final class FakeMicrophone: Microphone, @unchecked Sendable {
    /// A device that is there but will not open — unplugged mid-Dictation, or
    /// taken exclusively by something else.
    struct WillNotOpen: Error, Equatable {}

    private let lock = NSLock()
    private var heard: (@Sendable ([Float]) -> Void)?
    private var opened = 0
    private var open = false

    /// The rate this microphone opens at, which is the rate the Dictation is
    /// handed back at.
    let opensAt: Double

    /// Whether opening fails.
    let refuses: Bool

    init(opensAt: Double = 48_000, refuses: Bool = false) {
        self.opensAt = opensAt
        self.refuses = refuses
    }

    func open(_ heard: @escaping @Sendable ([Float]) -> Void) throws -> Double {
        if refuses { throw WillNotOpen() }
        lock.withLock {
            self.heard = heard
            open = true
            opened += 1
        }
        return opensAt
    }

    func close() {
        lock.withLock {
            heard = nil
            open = false
        }
    }

    /// The microphone hears one buffer.
    func hears(_ samples: [Float]) {
        lock.withLock { heard }?(samples)
    }

    var isOpen: Bool { lock.withLock { open } }
    var timesOpened: Int { lock.withLock { opened } }
}

/// The user's answer to the Microphone prompt, and a count of how often they
/// were asked for it.
actor FakeMicrophoneAccess: MicrophoneAccess {
    /// One answer per request, so a test can grant access once and then revoke
    /// it the way System Settings does between two Dictations. The last answer
    /// stands for every request after it.
    private var answers: [Bool]
    private(set) var timesAsked = 0

    init(answering answers: [Bool]) {
        self.answers = answers
    }

    func request() async -> Bool {
        timesAsked += 1
        return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
}

/// Every level the microphone reported, in the order it reported them.
actor ReportedLevels {
    private(set) var levels: [InputLevel] = []

    /// How many of them `nextLevel()` has handed back, and whoever is waiting
    /// for one that has not arrived yet.
    private var delivered = 0
    private var waiting: CheckedContinuation<InputLevel, Never>?

    func record(_ level: InputLevel) {
        levels.append(level)
        if let waiting {
            self.waiting = nil
            delivered += 1
            waiting.resume(returning: level)
        }
    }

    /// The next level reported, waiting for it if it has not arrived.
    ///
    /// What lets a test assert on a level *while* the Dictation is still
    /// listening rather than reading them all back once it has stopped, which
    /// would prove they arrived but not that they arrived in time to be shown.
    func nextLevel() async -> InputLevel {
        if delivered < levels.count {
            defer { delivered += 1 }
            return levels[delivered]
        }
        return await withCheckedContinuation { continuation in
            waiting = continuation
        }
    }

    /// The report as `MicrophoneCapture` wants it.
    nonisolated var report: @Sendable (InputLevel) async -> Void {
        { await self.record($0) }
    }
}
