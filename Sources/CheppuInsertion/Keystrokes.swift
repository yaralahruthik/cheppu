import CheppuCore
import CoreGraphics

/// The keyboard Cheppu types on.
///
/// Narrow on purpose, and narrow for a reason: Cheppu synthesises exactly one
/// keystroke, ever. An app that watches the whole keyboard and can also type on
/// it has to be trusted twice over, and the smallest thing that can be said
/// here is the strongest promise.
protocol Keystrokes: Sendable {
    /// Synthesises the paste, as if the user had pressed Command-V themselves.
    ///
    /// Throwing means macOS would not let Cheppu type it, which is
    /// `InsertionFailure.keystrokeRefused`.
    func paste() throws
}

/// Command-V, by way of `CGEvent`.
///
/// Insertion is a paste rather than the Final Text typed out character by
/// character: typing multi-sentence text one key at a time is slow enough for
/// the user to watch it happen, and lossy in every app that autocompletes or
/// reformats as you go. A paste is one event, and it is the same one event in a
/// native app, an Electron app, a browser and a terminal.
///
/// This needs the same Accessibility grant the Hotkey does. Nothing checks for
/// it here: a Dictation can only reach an Insertion by way of a Hotkey that is
/// already being watched, and watching is refused without it. A grant taken
/// away mid-session arrives here as a refusal instead, which is #17's to say
/// out loud.
struct SystemKeystrokes: Keystrokes {
    /// V. Virtual key codes are positions on the keyboard rather than letters,
    /// and this is the position macOS calls `kVK_ANSI_V`.
    private static let v: CGKeyCode = 9

    func paste() throws {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let pressed = CGEvent(keyboardEventSource: source, virtualKey: Self.v, keyDown: true),
            let released = CGEvent(keyboardEventSource: source, virtualKey: Self.v, keyDown: false)
        else {
            throw InsertionFailure.keystrokeRefused
        }

        // Posting an event suppresses the user's own for a moment afterwards
        // unless the source is told not to. Cheppu inserts into the app someone
        // is typing in, so a quarter of a second of their own keystrokes going
        // missing is exactly the cost this must not have.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Said outright rather than inherited: the flags an event is born with
        // include whatever the user is holding down at the time, and a paste
        // that arrives as Shift-Command-V, or Option-Command-V, is a different
        // command in a great many apps.
        pressed.flags = .maskCommand
        released.flags = .maskCommand

        // Posted where a real keystroke enters, so that the app with focus
        // receives it exactly as it would the user's own. Cheppu's own watch
        // sees it too, as one more key it was not sent — which is a key that
        // spoils a Hotkey press in progress, and there is none: the Hotkey is
        // what ended this Dictation, a moment ago.
        pressed.post(tap: .cghidEventTap)
        released.post(tap: .cghidEventTap)
    }
}
