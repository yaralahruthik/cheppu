import CheppuCore
import Foundation

@testable import CheppuKeyboard

/// A keyboard that is typed on when the test says so.
///
/// A real one is handed events by the system on a thread of its own, so this
/// hands them over from whatever thread struck them rather than pretending the
/// hand-over is orderly. What is asserted is that everything struck arrives, in
/// order, however it was delivered.
final class FakeKeyboard: Keyboard, @unchecked Sendable {
    /// A keyboard that cannot be watched for a reason of the system's own —
    /// the tap refused for anything other than a missing grant.
    struct WillNotWatch: Error, Equatable {}

    private let lock = NSLock()
    private var struck: (@Sendable (KeyStroke) -> Void)?
    private var watched = 0

    /// Whether watching fails.
    let refuses: Bool

    init(refuses: Bool = false) {
        self.refuses = refuses
    }

    func watch(_ struck: @escaping @Sendable (KeyStroke) -> Void) throws {
        if refuses { throw WillNotWatch() }
        lock.withLock {
            self.struck = struck
            watched += 1
        }
    }

    func stop() {
        lock.withLock { struck = nil }
    }

    /// The user types, in this order.
    func strikes(_ strokes: KeyStroke...) {
        for stroke in strokes {
            lock.withLock { struck }?(stroke)
        }
    }

    var isBeingWatched: Bool { lock.withLock { struck != nil } }
    var timesWatched: Int { lock.withLock { watched } }
}

/// The Accessibility switch, and a count of how often it was read.
final class FakeAccessibilityAccess: AccessibilityAccess, @unchecked Sendable {
    private let lock = NSLock()

    /// One answer per reading, so a test can refuse and then grant the way a
    /// user does in System Settings while the app is running. The last answer
    /// stands for every reading after it.
    private var answers: [Bool]
    private var readings = 0

    init(answering answers: [Bool]) {
        self.answers = answers
    }

    var isGranted: Bool {
        lock.withLock {
            readings += 1
            return answers.count > 1 ? answers.removeFirst() : answers[0]
        }
    }

    var timesRead: Int { lock.withLock { readings } }
}

/// Everything the Hotkey reported, in the order it reported it.
actor ReportedGestures {
    private(set) var gestures: [HotkeyEvent] = []

    /// How many of them `nextGesture()` has handed back, and whoever is waiting
    /// for one that has not arrived yet.
    private var delivered = 0
    private var waiting: CheckedContinuation<HotkeyEvent, Never>?

    func record(_ gesture: HotkeyEvent) {
        gestures.append(gesture)
        if let waiting {
            self.waiting = nil
            delivered += 1
            waiting.resume(returning: gesture)
        }
    }

    /// The next gesture reported, waiting for it if it has not arrived.
    ///
    /// What lets a test assert on a press without waiting a fixed length of
    /// time for a keyboard that crosses into an actor on its own schedule.
    func nextGesture() async -> HotkeyEvent {
        if delivered < gestures.count {
            defer { delivered += 1 }
            return gestures[delivered]
        }
        return await withCheckedContinuation { continuation in
            waiting = continuation
        }
    }

    /// The report as `HotkeyWatch` wants it.
    nonisolated var report: @Sendable (HotkeyEvent) async -> Void {
        { await self.record($0) }
    }
}
