import AppKit
import CheppuAudio
import CheppuCore
import CheppuEngine
import CheppuFeedback
import CheppuHistory
import CheppuInsertion
import CheppuKeyboard

/// Renders the core's `MenuBarMenu` as a status item, performs the action behind
/// whichever item the user picks, wires a Dictation to the machine it runs on,
/// and keeps Cheppu watching for the Hotkey.
///
/// This is glue: what it does is assemble and render. The one thing it decides
/// for itself — fetching the Engine at launch, with nothing shown — is a
/// placeholder that Onboarding takes over (#20). That is why it is not tested.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    /// The Dictation, and every port it is wired to. Held here for the life of
    /// the app: the Hotkey watch reports to it weakly, so a core nobody keeps
    /// is a Hotkey that does nothing.
    private var dictations: DictationCore?

    /// Everything Cheppu still has of what the user said, and the window they
    /// read it in. Held here rather than made when the menu item is picked, so
    /// that the Dictation writing to History and the window reading it are the
    /// same store.
    private let history = HistoryStore()
    private lazy var historyWindow = HistoryWindow(reading: history)

    /// Whether the Hotkey is being watched. Everything the menu says about
    /// Accessibility hangs off this.
    private var canSeeTheHotkey = false

    /// The switch in front of the Cues, which the menu both shows and moves.
    ///
    /// Read from here rather than remembered, so that the menu cannot come to
    /// disagree with what a Dictation actually does.
    private let cues = SystemCueSwitch()

    /// How long to leave between asking macOS again whether Cheppu may watch
    /// the keyboard. Accessibility is granted by hand in System Settings and
    /// nothing tells an app when that happens, so the alternative to asking
    /// again is a Hotkey that only starts working at the next launch.
    private static let whileWaitingForAccessibility: Duration = .seconds(2)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        self.statusItem = statusItem
        showMenu()

        runDictations()
    }

    /// Wires a Dictation to the machine it runs on, and sets it going.
    ///
    /// This is the whole of Cheppu in one place: the keyboard the Hotkey is
    /// watched on, the microphone it listens through, the Engine that hears it,
    /// the pasteboard the words are put where the cursor is with, and the Pill
    /// and Cues that say which of those is happening.
    private func runDictations() {
        let parakeet = try? ParakeetEngine()
        // A machine with nowhere to keep the Engine still gets a Hotkey, and
        // is still asked for Accessibility. What it does not get is a Dictation
        // that can be transcribed, and that is said where it happens rather
        // than by the app never starting.
        let engine: any EnginePort = parakeet ?? EngineWithNowhereToLive()

        let dictations = DictationCore(
            // Every Cleanup rule on, which is what a Dictation does until the
            // Settings window (#15) gives the user the three switches.
            cleaningWith: .all,
            hotkey: HotkeyWatch(),
            audio: MicrophoneCapture(),
            engine: engine,
            insertion: PasteInsertion(),
            clipboard: SystemClipboard(),
            history: history,
            feedback: PillAndCues(),
            clock: SystemClock()
        )
        self.dictations = dictations

        if let parakeet { putTheEngineOnTheMachine(parakeet) }
        watchForTheHotkey(with: dictations)
    }

    /// Fetches the Engine if it is not here yet, so that the first Dictation
    /// has something to be transcribed by.
    ///
    /// Silent, and at launch rather than when the user asks: Onboarding is
    /// where a 480 MB download gets a face — a size, real progress, and a first
    /// Dictation to end on (#20). Until then this is the difference between a
    /// fresh machine that dictates and one whose Hotkey works and whose words
    /// go nowhere.
    private func putTheEngineOnTheMachine(_ engine: ParakeetEngine) {
        Task {
            guard await !engine.isEngineDownloaded() else { return }
            // What an interrupted download leaves behind is picked up by the
            // next attempt rather than started over, so a failure here costs
            // the next launch nothing.
            try? await engine.downloadEngine { _ in }
        }
    }

    /// Starts watching for the Hotkey, and says why it cannot if it cannot.
    ///
    /// The reason is given once, when Cheppu first finds it cannot watch; the
    /// menu goes on saying it for as long as it is true, because a user whose
    /// Hotkey does nothing has nowhere else to look.
    private func watchForTheHotkey(with dictations: DictationCore) {
        Task { [weak self] in
            var hasSaidWhy = false
            while let self, !Task.isCancelled {
                do {
                    try await dictations.watchForActivations()
                    canSeeTheHotkey = true
                    showMenu()
                    return
                } catch {
                    canSeeTheHotkey = false
                    showMenu()
                    if !hasSaidWhy {
                        hasSaidWhy = true
                        AccessibilityRequest.ask()
                    }
                    try? await Task.sleep(for: Self.whileWaitingForAccessibility)
                }
            }
        }
    }

    private func showMenu() {
        statusItem?.menu = menu(
            for: MenuBarMenu(canSeeTheHotkey: canSeeTheHotkey, areCuesOn: cues.areCuesOn())
        )
    }

    private func menu(for menuBarMenu: MenuBarMenu) -> NSMenu {
        let menu = NSMenu()
        for item in menuBarMenu.items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(menuBarItemPicked(_:)),
                keyEquivalent: item.shortcutKey ?? ""
            )
            menuItem.target = self
            menuItem.representedObject = item
            menuItem.state = item.isTicked ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    @objc private func menuBarItemPicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        switch item {
        case .allowAccessibility:
            AccessibilityRequest.ask()
        case .history:
            historyWindow.show()
        case .cues(let areOn):
            cues.turnCues(on: !areOn)
            showMenu()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
