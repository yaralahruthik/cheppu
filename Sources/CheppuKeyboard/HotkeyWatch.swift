import CheppuCore
import Foundation

/// The Hotkey port, over a real keyboard.
///
/// It watches the whole session's keyboard, so that the Hotkey works while any
/// other app has focus and the user never has to click on Cheppu first, and it
/// reports the two things it is looking for: the Hotkey going down and what
/// became of that press, and Escape. Everything else passes it by untouched and
/// unrecorded — and so, in fact, do those two: the tap can read a key and
/// cannot take one (ADR-0006).
///
/// Which key it is watching for is the user's, read at the moment watching
/// starts rather than held from launch (ADR-0010). Watching again with a Hotkey
/// they have just chosen is the whole of changing it: the tap is remade around
/// the new key and the next press is theirs.
public actor HotkeyWatch: HotkeyPort {
    private let accessibility: any AccessibilityAccess
    private let inputMonitoring: any InputMonitoringAccess
    private let keyboard: any Keyboard
    private let choice: any HotkeyChoice

    /// What is carrying strokes from the keyboard to the handler, while there
    /// is a handler to carry them to.
    private var arriving: AsyncStream<KeyStroke>.Continuation?

    /// Cheppu's keyboard, watching for whichever key the user chose.
    public init(watchingFor choice: any HotkeyChoice) {
        self.init(
            accessibility: SystemAccessibilityAccess(),
            inputMonitoring: SystemInputMonitoringAccess(),
            keyboard: SystemKeyboard(),
            choice: choice
        )
    }

    /// The seam the suite uses: answers that are not the user's, and a keyboard
    /// that is not a keyboard. Nothing in the suite creates an event tap, which
    /// is also what stops running it from asking the terminal for
    /// Accessibility.
    init(
        accessibility: any AccessibilityAccess,
        inputMonitoring: any InputMonitoringAccess,
        keyboard: any Keyboard,
        choice: any HotkeyChoice
    ) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.keyboard = keyboard
        self.choice = choice
    }

    public func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async throws {
        let hotkey = await choice.hotkey()

        // Asked here, every time watching starts, rather than remembered from
        // launch: a grant taken away in System Settings is then something the
        // app can say out loud rather than a Hotkey that silently stopped
        // working (`docs/product-experience.md` §9).
        guard accessibility.isGranted else { throw HotkeyFailure.accessibilityDenied }

        // Asked only where the chosen key needs it. A Hotkey that is not the
        // Globe key never reaches this line, and the user is never asked for a
        // permission their own choice does not cost them.
        guard !hotkey.needsInputMonitoring || inputMonitoring.isGranted else {
            throw HotkeyFailure.inputMonitoringDenied
        }

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
            // The key is the whole of what the keyboard is told about the
            // Hotkey. Everything else about it — which modifiers, and whether
            // what just happened was a tap — is decided above that line.
            try keyboard.watch(tellingApart: hotkey.key) { arriving.yield($0) }
        } catch {
            arriving.finish()
            throw error
        }

        Task {
            // The gesture belongs to this watch and to nothing else. A Hotkey
            // held while the handler was replaced then finishes its press
            // against the gesture that saw it begin, rather than arriving at
            // the new one as a release of a key it never saw pressed.
            var gesture = HotkeyGesture(watchingFor: hotkey)
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
