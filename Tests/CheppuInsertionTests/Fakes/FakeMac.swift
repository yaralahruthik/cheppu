import CheppuCore
import Foundation

@testable import CheppuInsertion

/// A pasteboard that is nobody's: it holds what the test put there, remembers
/// everything it was asked to hold, and is never the one the user copied into.
final class FakePasteboard: Pasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var held: PasteboardContents
    private var borrowedFor: [String] = []

    /// A pasteboard holding whatever the user last copied.
    init(holding contents: PasteboardContents = PasteboardContents(items: [])) {
        self.held = contents
    }

    func contents() -> PasteboardContents {
        lock.withLock { held }
    }

    func replace(with text: String) {
        lock.withLock {
            held = PasteboardContents(items: [[PasteboardContents.plainText: Data(text.utf8)]])
            borrowedFor.append(text)
        }
    }

    func restore(_ contents: PasteboardContents) {
        lock.withLock { held = contents }
    }

    /// Every Final Text the pasteboard was asked to carry, in order. Empty
    /// means the user's clipboard was never touched at all.
    var wasBorrowedFor: [String] { lock.withLock { borrowedFor } }
}

/// The keyboard Cheppu types on, unplugged: it records the paste rather than
/// sending it, so no suite ever types into the machine running it.
final class FakeKeystrokes: Keystrokes, @unchecked Sendable {
    private let lock = NSLock()
    private var pasted: [PasteboardContents] = []

    /// The pasteboard the Target App would read when the keystroke arrived.
    private let pasteboard: FakePasteboard

    /// Whether macOS refuses to synthesise the keystroke, which is what a
    /// revoked Accessibility grant looks like from here.
    private let refuses: Bool

    init(reading pasteboard: FakePasteboard, refuses: Bool = false) {
        self.pasteboard = pasteboard
        self.refuses = refuses
    }

    func paste() throws {
        if refuses { throw InsertionFailure.keystrokeRefused }
        // What the Target App pastes is whatever is on the pasteboard at the
        // instant the keystroke lands, so that is what is written down —
        // asserting on the paste alone would not show it arrived in time.
        lock.withLock { pasted.append(pasteboard.contents()) }
    }

    /// What the Target App would have pasted, once per keystroke.
    var pastedText: [String] {
        lock.withLock { pasted }.map(\.asPlainText)
    }
}

/// Where the keyboard is pointing, as the test says it is.
final class FakeFocus: Focus, @unchecked Sendable {
    private let lock = NSLock()
    private var app: TargetApp?

    init(on app: TargetApp?) {
        self.app = app
    }

    func focusedApp() async -> TargetApp? {
        lock.withLock { app }
    }

    /// The user clicks into another app.
    func moveTo(_ app: TargetApp?) {
        lock.withLock { self.app = app }
    }
}

extension PasteboardContents {
    /// What a person would read on the pasteboard, where it holds text at all.
    var asPlainText: String {
        guard let data = items.first?[Self.plainText] else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
