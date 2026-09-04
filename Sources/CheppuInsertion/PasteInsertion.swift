import CheppuCore
import Foundation

/// The Insertion port, over the Mac's pasteboard and one synthesised keystroke.
///
/// The Final Text goes onto the pasteboard, Command-V is typed as the user
/// would have typed it, and what was on the pasteboard before goes back. The
/// borrowing is the whole difficulty: a clipboard the user finds changed after
/// a Dictation is a Dictation that cost them something, so everything here is
/// arranged so that the pasteboard is either put back or never touched.
public actor PasteInsertion: InsertionPort {
    private let focus: any Focus
    private let pasteboard: any Pasteboard
    private let keystrokes: any Keystrokes

    /// How long the Final Text stays on the pasteboard before what was there
    /// goes back.
    ///
    /// The keystroke is delivered to the Target App, which then reads the
    /// pasteboard when it gets to it. Nothing tells Cheppu when that has
    /// happened — a paste does not change the pasteboard, so there is nothing
    /// to watch for — so this is the one place a length of time is guessed
    /// rather than measured. It is set for the slowest of the four targets that
    /// have to work: an Electron app with a busy main thread.
    ///
    /// It is not spent from the latency budget: the words are already on screen
    /// when it starts, and what waits for it is the pasteboard going back and
    /// the Pill coming down.
    private let whileTheTargetAppPastes: Duration

    /// Cheppu's pasteboard and Cheppu's one keystroke.
    public init() {
        self.init(
            focus: SystemFocus(),
            pasteboard: SystemPasteboard(),
            keystrokes: SystemKeystrokes()
        )
    }

    /// The seam the suite uses: a pasteboard that is nobody's, a keyboard that
    /// is unplugged, and a focus the test moves by hand.
    init(
        focus: any Focus,
        pasteboard: any Pasteboard,
        keystrokes: any Keystrokes,
        whileTheTargetAppPastes: Duration = .milliseconds(200)
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.whileTheTargetAppPastes = whileTheTargetAppPastes
    }

    public func focusedApp() async -> TargetApp? {
        await focus.focusedApp()
    }

    public func insert(_ finalText: FinalText, into targetApp: TargetApp) async throws {
        // Checked before the pasteboard is touched, so that a Dictation the
        // user has walked away from leaves their clipboard exactly as they left
        // it. What remains between here and the keystroke is a few microseconds
        // of the same process, which is as close as anything can get to sending
        // a keystroke and knowing where it went.
        guard await focus.focusedApp() == targetApp else { throw InsertionFailure.focusMoved }

        let borrowed = pasteboard.contents()
        pasteboard.replace(with: finalText.text)

        do {
            try keystrokes.paste()
        } catch {
            pasteboard.restore(borrowed)
            throw error
        }

        try? await Task.sleep(for: whileTheTargetAppPastes)
        pasteboard.restore(borrowed)
    }
}
