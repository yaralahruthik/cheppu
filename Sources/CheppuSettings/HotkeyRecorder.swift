import AppKit
import CheppuCore

/// Listening, at the Settings window, for the key the user wants to dictate
/// with.
///
/// The one place in Cheppu that reads a key the user pressed at a window of
/// Cheppu's own. It needs no permission and can hear nothing outside this app:
/// a local monitor is handed only the events already on their way to Cheppu,
/// which is exactly the difference between somebody telling the app a key and
/// the app watching them type (ADR-0011).
///
/// The events are swallowed while it listens, so that Command-Q pressed on the
/// way to a chord chooses a Hotkey rather than quitting. That is this window's
/// own keyboard and nobody else's — the watch on everyone else's keyboard
/// cannot swallow a keystroke and never will (ADR-0006).
///
/// What counts as a Hotkey is `HotkeyRecording`'s, in the core, and is tested
/// there. This is the glue that feeds it.
@MainActor
final class HotkeyRecorder {
    /// Escape. It stops the recording rather than becoming a Hotkey: it Cancels
    /// a Dictation (ADR-0006), and a key that did both would mean two things at
    /// the same moment.
    private static let escape: UInt16 = 53

    /// Said once, with the Hotkey the user chose, or with nothing where they
    /// pressed Escape.
    private let chosen: (Hotkey?) -> Void

    private var recording = HotkeyRecording()
    private var listening: Any?

    init(whenChosen chosen: @escaping (Hotkey?) -> Void) {
        self.chosen = chosen
    }

    /// Whether the window is waiting for a key this instant.
    var isListening: Bool { listening != nil }

    /// Starts listening. Nothing happens until the user presses something.
    func listen() {
        guard listening == nil else { return }
        recording = HotkeyRecording()

        listening = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            // Swallowed, whatever it was: while this window is listening, every
            // key on it is an answer to the question it asked.
            saw(event)
            return nil
        }
    }

    /// Stops listening, without choosing anything.
    func stopListening() {
        guard let listening else { return }
        self.listening = nil
        NSEvent.removeMonitor(listening)
    }

    private func saw(_ event: NSEvent) {
        if event.type == .flagsChanged {
            // The device-dependent bits are what say which side of the keyboard
            // a modifier was pressed on, and `NSEvent` carries them exactly as
            // the event tap does — so both keyboards Cheppu reads answer
            // "which Option key was that?" the same way.
            let held = Modifier.held(inFlags: UInt64(event.modifierFlags.rawValue))
            finish(with: recording.sawModifiers(held))
            return
        }

        // Asked once, and the answer is compared against the two keys that mean
        // something here: Escape, which stops the recording, and whichever key
        // this turns out to be, if it is one a Hotkey may be built on.
        let position = event.keyCode

        if position == Self.escape {
            finish(with: nil, chosen: true)
            return
        }

        // A key Cheppu has no name for is one it could not show the user
        // afterwards, so it is let go of rather than recorded.
        guard let key = Key(code: position) else { return }
        finish(with: recording.sawKey(key))
    }

    /// Ends the recording where there is something to end it with.
    private func finish(with hotkey: Hotkey?, chosen hasChosen: Bool = false) {
        guard hotkey != nil || hasChosen else { return }
        stopListening()
        chosen(hotkey)
    }
}
