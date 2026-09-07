import AppKit
import CheppuAudio
import CheppuCore
import CheppuEngine
import CheppuFeedback
import CheppuHistory
import CheppuInsertion
import CheppuKeyboard
import CheppuSettings

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

    /// The attempt to start watching, which goes on trying for as long as the
    /// permission it needs is missing. Held so that choosing a different Hotkey
    /// can replace it rather than race it.
    private var watching: Task<Void, Never>?

    /// Everything Cheppu still has of what the user said, and the window they
    /// read it in. Held here rather than made when the menu item is picked, so
    /// that the Dictation writing to History and the window reading it are the
    /// same store.
    private let history = HistoryStore()
    private lazy var historyWindow = HistoryWindow(reading: history)

    /// The permission standing between Cheppu and the Hotkey, or nothing where
    /// it is being watched. Everything the menu says about a Hotkey that does
    /// not work hangs off this, and which permission it is depends on the key
    /// the user chose.
    private var missingForTheHotkey: Permission?

    /// Everything the user has set, and the window they set it in.
    ///
    /// One `Preferences` for the whole app rather than one per reader: the menu
    /// shows the Cue switch, the Settings window moves it, and a Dictation
    /// reads it and the three Cleanup switches on its way past. All of them are
    /// reading the same preferences domain, so none of them can come to
    /// disagree with what a Dictation actually does (ADR-0010).
    private let preferences = Preferences()
    private lazy var settingsWindow = SettingsWindow(
        setting: preferences,
        asking: SystemPermissions(),
        clearingHistory: { [weak self] in self?.emptyHistory() },
        // The Cue switch is in two places at once. Redrawing the menu is what
        // keeps the tick in it saying what the window just did.
        whenTheCuesMove: { [weak self] in self?.showMenu() },
        // A Hotkey chosen in the window is watched for by the next press, with
        // no relaunch: the watch reads the key where it uses it, so all that is
        // needed is to watch again (ADR-0010).
        whenTheHotkeyMoves: { [weak self] in self?.watchForTheHotkeyAgain() }
    )

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
            // Read at each Dictation rather than handed over once: a rule
            // turned off in Settings is off for the next thing the user says,
            // with nothing restarted and nothing told (ADR-0010).
            cleaningWith: preferences,
            // The key it watches for is read from the same preferences the
            // window writes, at the moment watching starts.
            hotkey: HotkeyWatch(watchingFor: preferences),
            audio: MicrophoneCapture(),
            engine: engine,
            insertion: PasteInsertion(),
            clipboard: SystemClipboard(),
            history: history,
            feedback: PillAndCues(when: preferences),
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
    /// Hotkey does nothing has nowhere else to look. Which reason it is depends
    /// on the key they chose: every Hotkey needs Accessibility, and the Globe
    /// key needs Input Monitoring on top of it.
    private func watchForTheHotkey(with dictations: DictationCore, sayingWhy: Bool = true) {
        watching?.cancel()
        watching = Task { [weak self] in
            var hasSaidWhy = !sayingWhy
            while let self, !Task.isCancelled {
                do {
                    try await dictations.watchForActivations()
                    missingForTheHotkey = nil
                    showMenu()
                    return
                } catch {
                    // A failure Cheppu has no name for is answered as the one
                    // it does: without Accessibility no Hotkey works at all, so
                    // it is the thing to say to somebody whose key is doing
                    // nothing.
                    let missing = (error as? HotkeyFailure)?.permission ?? .accessibility
                    missingForTheHotkey = missing
                    showMenu()
                    if !hasSaidWhy {
                        hasSaidWhy = true
                        PermissionRequest.ask(for: missing, toWatch: preferences.hotkey())
                    }
                    try? await Task.sleep(for: Self.whileWaitingForAccessibility)
                }
            }
        }
    }

    /// Watches again, for the Hotkey the user has just chosen.
    ///
    /// The whole of changing it: the watch reads the key where it uses it, so
    /// there is nothing to hand over and nothing to keep in step (ADR-0010). It
    /// replaces the attempt already under way, so a user who has just moved off
    /// a key that needed a permission they never granted is not left behind a
    /// loop still waiting for it.
    ///
    /// Nothing is said this time. The user is looking at the Settings window,
    /// which has already told them what the key they picked costs and is
    /// showing them the row for it; an alert on top of that is Cheppu saying it
    /// twice.
    private func watchForTheHotkeyAgain() {
        guard let dictations else { return }
        watchForTheHotkey(with: dictations, sayingWhy: false)
    }

    private func showMenu() {
        statusItem?.menu = menu(
            for: MenuBarMenu(
                missingForTheHotkey: missingForTheHotkey, areCuesOn: preferences.areCuesOn()))
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

    /// Empties History, from the button in the Settings window.
    ///
    /// The store is the same one a Dictation writes to and the same one the
    /// History window reads, so what the user asked to be forgotten is
    /// forgotten everywhere at once.
    private func emptyHistory() {
        Task {
            try? await history.clear()
            // The History window, if the user has it open behind Settings, is
            // still listing what they have just asked Cheppu to forget.
            historyWindow.redrawIfShowing()
        }
    }

    @objc private func menuBarItemPicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        switch item {
        case .allowPermission(let permission):
            PermissionRequest.ask(for: permission, toWatch: preferences.hotkey())
        case .history:
            historyWindow.show()
        case .settings:
            settingsWindow.show()
        case .cues(let areOn):
            preferences.turnCues(on: !areOn)
            showMenu()
            // The same switch is a line in the Settings window, which may be
            // open behind the menu.
            settingsWindow.redrawIfShowing()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
