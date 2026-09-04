import CheppuCore
import Foundation

/// The Hotkey port, over a real keyboard.
///
/// It watches the whole session's keyboard, so that the Hotkey works while any
/// other app has focus and the user never has to click on Cheppu first, and it
/// reports the two things it is looking for: the Hotkey going down on its own
/// and what became of that press, and Escape. Everything else passes it by
/// untouched and unrecorded — and so, in fact, do those two: the tap can read a
/// key and cannot take one (ADR-0006).
public actor HotkeyWatch: HotkeyPort {
    private let accessibility: any AccessibilityAccess
    private let keyboard: any Keyboard

    /// What is carrying strokes from the keyboard to the handler, while there
    /// is a handler to carry them to.
    private var arriving: AsyncStream<KeyStroke>.Continuation?

    /// Cheppu's keyboard.
    public init() {
        self.init(accessibility: SystemAccessibilityAccess(), keyboard: SystemKeyboard())
    }

    /// The seam the suite uses: an answer that is not the user's, and a
    /// keyboard that is not a keyboard. Nothing in the suite creates an event
    /// tap, which is also what stops running it from asking the terminal for
    /// Accessibility.
    init(accessibility: any AccessibilityAccess, keyboard: any Keyboard) {
        self.accessibility = accessibility
        self.keyboard = keyboard
    }

    public func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async throws {
        // Asked here, every time watching starts, rather than remembered from
        // launch: a grant taken away in System Settings is then something the
        // app can say out loud rather than a Hotkey that silently stopped
        // working (`docs/product-experience.md` §9).
        guard accessibility.isGranted else { throw HotkeyFailure.accessibilityDenied }

        // Nothing asks for this, but a watch left behind would be a second
        // reader of every key on the machine.
        stopWatching()

        // The system delivers events on a thread that cannot wait, and what
        // reads them is one gesture at a time. The stream is what stands
        // between the two: yielding never blocks, and what is yielded is read
        // in the order it was typed rather than in the order tasks happen to
        // run.
        let (strokes, arriving) = AsyncStream<KeyStroke>.makeStream(bufferingPolicy: .unbounded)

        do {
            try keyboard.watch { arriving.yield($0) }
        } catch {
            arriving.finish()
            throw error
        }

        Task {
            // The gesture belongs to this watch and to nothing else. A Hotkey
            // held while the handler was replaced then finishes its press
            // against the gesture that saw it begin, rather than arriving at
            // the new one as a release of a key it never saw pressed.
            var gesture = HotkeyGesture()
            for await stroke in strokes {
                if let reported = gesture.seeing(stroke) {
                    await handler(reported)
                }
            }
        }
        self.arriving = arriving
    }

    /// Stops watching, and lets go of the strokes still crossing.
    private func stopWatching() {
        guard let arriving else { return }
        self.arriving = nil

        keyboard.stop()
        // Finishing is what ends the task carrying strokes to the handler.
        // Nothing waits for it: the strokes still crossing are keys pressed
        // after Cheppu stopped watching, and they belong to the gesture that
        // saw them begin rather than to whoever is watching now.
        arriving.finish()
    }
}
