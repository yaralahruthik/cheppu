import AppKit
import CheppuAudio
import CheppuCore
import CheppuDiagnostics
import CheppuEngine
import CheppuFeedback
import CheppuHistory
import CheppuInsertion
import CheppuKeyboard
import CheppuSettings

/// Renders the core's `MenuBarMenu` as a status item, performs the action behind
/// whichever item the user picks, wires a Dictation to the machine it runs on,
/// keeps Cheppu watching for the Hotkey, and puts the first launch on the screen
/// the one time it is owed.
///
/// This is glue: what it does is assemble and render. The one thing it decides
/// for itself is which of the two errands a launch is — the first one, walked
/// through in a window, or every one after it, where a missing Engine is
/// fetched quietly behind a Hotkey that already works (ADR-0013). That is why
/// it is not tested.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    /// The menu behind the icon. One menu for the life of the app, filled again
    /// every time it is opened: what it offers depends on which permissions
    /// macOS says Cheppu has this instant, and nothing tells an app when one is
    /// taken away (ADR-0010).
    private let menu = NSMenu()

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

    /// What the user has taught Cheppu by correcting a word, and where it is
    /// kept. Held here for the reason History is: the Engine reads this store
    /// and the History window writes to it, and they have to be the same one.
    private let spellings = SpellingsStore()

    /// What both windows ask when they draw the Spellings row. One closure
    /// rather than one each, so the two cannot come to ask different things.
    private lazy var theSpellingsRow: @Sendable () async -> SpellingsRow = {
        [weak self] in await self?.whatTheSpellingsRowSays() ?? .thePartIsMissing
    }

    private lazy var historyWindow = HistoryWindow(
        reading: history,
        teaching: spellings,
        showingTheSpellingsRow: theSpellingsRow,
        fetchingTheSpellingsPart: { [weak self] in self?.fetchTheSpellingsPart() },
        // The Settings row counts the Spellings, and may be open behind this
        // window while the user corrects a word.
        whenSpellingsMove: { [weak self] in self?.settingsWindow.redrawIfShowing() }
    )

    /// The fetch of the second part of the Engine, while one is under way.
    ///
    /// Held so that the two buttons that start it — the one in the History
    /// window and the one on the Settings row — are two ways to press the same
    /// thing rather than two downloads of the same 103 MB.
    private var fetchingTheSpellingsPart: Task<Void, Never>?

    /// How much of it has arrived, while it is arriving. Nothing at every other
    /// moment, including after an attempt that stopped: a fetch that ended is
    /// picked up by the next press of either button and never at launch
    /// (ADR-0014).
    private var theSpellingsPartSoFar: EngineDownloadProgress?

    /// The permission standing between Cheppu and the Hotkey, or nothing where
    /// it is being watched. Everything the menu says about a Hotkey that does
    /// not work hangs off this, and which permission it is depends on the key
    /// the user chose.
    private var missingForTheHotkey: Permission?

    /// What Cheppu did, written down so that a problem can be sent to somebody
    /// who can fix it without sending what was said. One log for the whole app,
    /// held here for the same reason the History store is: everything writing
    /// to it has to be writing to the same file.
    private let diagnostics = DiagnosticsLog()

    /// The Engine: the one object that both transcribes and puts itself on the
    /// machine.
    ///
    /// Held rather than made where each of them is needed, so that the first
    /// launch's download and the Dictations that follow it are the same Engine
    /// reading the same directory. Nothing where this account has no
    /// Application Support to keep it in, which is a Dictation that fails where
    /// the Engine would have been rather than an app that does not start.
    private lazy var parakeet = try? ParakeetEngine(
        // Read at each Dictation rather than handed over once, exactly as the
        // Cleanup switches are: a Spelling left behind a moment ago is read by
        // the very next thing the user says (ADR-0010).
        readingSpellings: spellings,
        when: preferences,
        writingDownTo: diagnostics
    )

    /// Putting the Engine on the machine, whether or not there is anywhere to
    /// put it. A first launch with an Engine Download step that did nothing and
    /// said nothing would be worse than one that says it cannot.
    private lazy var engineDownload: any EngineDownloadPort =
        parakeet ?? EngineWithNowhereToLive()

    /// Everything the user has set, and the window they set it in.
    ///
    /// One `Preferences` for the whole app rather than one per reader: the menu
    /// shows the Cue switch, the Settings window moves it, and a Dictation
    /// reads it and the three Cleanup switches on its way past. All of them are
    /// reading the same preferences domain, so none of them can come to
    /// disagree with what a Dictation actually does (ADR-0010).
    private let preferences = Preferences()

    /// What macOS says about each permission, asked afresh every time. One
    /// answer for the whole app, so the menu, the Settings window and the
    /// Dictation that met a refusal cannot come to disagree about what Cheppu
    /// has.
    private let permissions = SystemPermissions()

    /// Saying which permission is missing, and offering the way to the pane it
    /// is granted on. The Dictation that meets the refusal asks for it, and so
    /// does the watch when it finds it may no longer read the keyboard.
    private lazy var sayingWhatIsMissing = SayingWhatIsMissing(
        setting: preferences, asking: permissions)

    /// The first launch: permissions, the Engine, and one Dictation into a field
    /// Cheppu owns. Shown once, on the launch that is owed it, and never again.
    private lazy var onboarding = OnboardingWindow(
        setting: preferences, asking: permissions, fetching: engineDownload)

    private lazy var settingsWindow = SettingsWindow(
        setting: preferences,
        asking: permissions,
        clearingHistory: { [weak self] in self?.emptyHistory() },
        readingSpellings: theSpellingsRow,
        forgettingSpellings: { [weak self] in self?.forgetEverySpelling() },
        fetchingTheSpellingsPart: { [weak self] in self?.fetchTheSpellingsPart() },
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

    /// How long to leave between asking macOS whether Cheppu may *still* watch
    /// the keyboard.
    ///
    /// The same question, asked from the other side of it. Nothing tells an app
    /// when a grant is taken away either, and a tap macOS has stopped handing
    /// keys to is indistinguishable from a user who has not pressed anything —
    /// which is exactly the silence #17 rules out.
    ///
    /// Longer than the wait above, because it is the one Cheppu spends its whole
    /// life in: waiting for a permission is a minute of somebody's day, and
    /// watching is the rest of it. Five seconds is still inside the moment the
    /// user is in — they press the key, nothing happens, and Cheppu says why
    /// before they have finished wondering — and it is a decision already on
    /// record being read rather than a prompt being shown.
    private static let whileWatchingTheKeyboard: Duration = .seconds(5)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image()
        // Filled as it opens rather than now and again afterwards: what it says
        // depends on permissions that can be taken away while Cheppu is running
        // and while nobody is looking at the menu.
        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem

        runDictations()
    }

    /// Wires a Dictation to the machine it runs on, and sets it going.
    ///
    /// This is the whole of Cheppu in one place: the keyboard the Hotkey is
    /// watched on, the microphone it listens through, the Engine that hears it,
    /// the pasteboard the words are put where the cursor is with, and the Pill
    /// and Cues that say which of those is happening.
    private func runDictations() {
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
            permissions: sayingWhatIsMissing,
            clock: SystemClock(),
            diagnostics: diagnostics
        )
        self.dictations = dictations

        theFirstLaunchOrWhatItLeftBehind()
        watchForTheHotkey(with: dictations)
    }

    /// Shows the first launch on the one launch it is owed, and otherwise makes
    /// sure the Engine is still where the last one left it.
    ///
    /// The two are the same errand seen from either end. A user who has never
    /// been through Onboarding is walked through the download with a size and a
    /// bar in front of them; a user who has is not made to watch it again
    /// because they moved the folder or Cheppu shipped a new Engine — that one
    /// is fetched quietly, in the background, while their Hotkey goes on
    /// working.
    private func theFirstLaunchOrWhatItLeftBehind() {
        guard !onboarding.isOwed else {
            onboarding.show()
            return
        }
        putTheEngineOnTheMachine()
    }

    /// Fetches the Engine if it is not here yet, so that the next Dictation has
    /// something to be transcribed by.
    ///
    /// Silent, because by here the user has already been shown the download
    /// once and agreed to it: what is left is the copy of an Engine they
    /// already have going missing. What an interrupted attempt leaves behind is
    /// picked up by the next one rather than started over, so a failure here
    /// costs the next launch nothing.
    private func putTheEngineOnTheMachine() {
        let engine = engineDownload
        Task {
            guard await !engine.isEngineDownloaded() else { return }
            try? await engine.downloadEngine { _ in }
        }
    }

    /// Starts watching for the Hotkey, says why it cannot if it cannot, and
    /// keeps watching that it still may.
    ///
    /// The reason is given when Cheppu first finds it cannot watch; the menu
    /// goes on saying it for as long as it is true, because a user whose Hotkey
    /// does nothing has nowhere else to look. Which reason it is depends on the
    /// key they chose: every Hotkey needs Accessibility, and the Globe key needs
    /// Input Monitoring on top of it.
    ///
    /// It does not stop once it is watching. A grant can be taken away while
    /// Cheppu is running, and macOS tells nobody when that happens — the tap
    /// simply stops being handed keys, which from inside the app is
    /// indistinguishable from a user who has not pressed anything. So the loop
    /// keeps asking, and the moment the answer changes it goes round again and
    /// meets the same refusal the first launch would have (#17).
    private func watchForTheHotkey(with dictations: DictationCore, sayingWhy: Bool = true) {
        watching?.cancel()
        watching = Task { [weak self] in
            // Said the first time round unless the user is being shown a Hotkey
            // they have just chosen, and said again after any watch that
            // worked: a permission granted and then taken away a month later is
            // worth exactly the same sentence it was worth the first time.
            var sayWhy = sayingWhy
            while let self, !Task.isCancelled {
                do {
                    try await dictations.watchForActivations()
                    missingForTheHotkey = nil
                    sayWhy = true
                    await untilTheKeyboardIsTakenAway()
                } catch {
                    // A failure Cheppu has no name for is answered as the one
                    // it does: without Accessibility no Hotkey works at all, so
                    // it is the thing to say to somebody whose key is doing
                    // nothing.
                    let missing = (error as? HotkeyFailure)?.permission ?? .accessibility
                    missingForTheHotkey = missing
                    // Not while the first launch is on the screen. It is asking
                    // for these permissions one at a time, with the reason and
                    // the pane beside each, and an alert over the top of it
                    // would be Cheppu asking twice — and asking out of the
                    // order the sequence exists to keep. The moment that window
                    // is gone, the loop comes round again and says it.
                    if sayWhy, !onboarding.isShowing { await sayingWhatIsMissing.askFor(missing) }
                    try? await Task.sleep(for: Self.whileWaitingForAccessibility)
                }
            }
        }
    }

    /// Returns once macOS stops saying Cheppu may watch the keyboard.
    ///
    /// The Microphone is deliberately not asked about: it is what a Dictation
    /// needs once the key has arrived, and a microphone switched off must not be
    /// what tears down a tap that is working. The Dictation that meets that
    /// refusal is what says so, which is where the user is when it matters.
    private func untilTheKeyboardIsTakenAway() async {
        while !Task.isCancelled, mayStillWatchTheKeyboard() {
            try? await Task.sleep(for: Self.whileWatchingTheKeyboard)
        }
    }

    private func mayStillWatchTheKeyboard() -> Bool {
        Permission.neededToWatch(preferences.hotkey())
            .allSatisfy { permissions.status(of: $0) == .granted }
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

    /// Fills the menu as it opens, from what is true this instant.
    ///
    /// Everything on it can move while nobody is looking at it — the Cue switch
    /// from the Settings window, and a permission from System Settings — and
    /// this is what makes the menu the one place that cannot be out of date
    /// about them.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let showing = MenuBarMenu(
            missing: missingPermissions(), areCuesOn: preferences.areCuesOn())
        for item in showing.items {
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
    }

    /// Every permission Cheppu is missing this instant, in the order Settings
    /// reads them.
    ///
    /// What macOS says, asked afresh, so that the menu and the Settings window
    /// cannot disagree about what Cheppu has — and, where the watch found
    /// something in its way that macOS says is granted, that too. That is not a
    /// copy of a decision kept in step with macOS (ADR-0010): it is the record
    /// of what actually happened when Cheppu last tried to watch the keyboard,
    /// which is a thing macOS has no answer for and which outranks the one on
    /// record when the two differ.
    ///
    /// A permission nobody has answered for yet counts as missing, exactly as it
    /// does in Settings, so a fresh install says it needs the Microphone before
    /// any Dictation has asked for it. Offering the pane is not asking for the
    /// permission (`docs/product-experience.md` §9); Onboarding is what asks,
    /// on the one launch that walks the user through them.
    private func missingPermissions() -> [Permission] {
        Permission.neededBy(preferences.hotkey()).filter {
            permissions.status(of: $0) == .notGranted || $0 == missingForTheHotkey
        }
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

    /// What both windows say about the user's Spellings, answered in one place
    /// so that the two cannot come to disagree.
    ///
    /// A fetch under way outranks everything: while the bytes are arriving the
    /// row says so, whichever window is showing it.
    private func whatTheSpellingsRowSays() async -> SpellingsRow {
        if let theSpellingsPartSoFar { return .thePartIsArriving(theSpellingsPartSoFar) }
        guard await engineDownload.isTheSpellingsPartDownloaded() else { return .thePartIsMissing }
        return .theEngineCanReadThem(
            areOn: preferences.areSpellingsRead(), howMany: await spellings.spellings().count)
    }

    /// Fetches the part of the Engine that reads Spellings, because somebody
    /// pressed a button.
    ///
    /// Never at launch and never on the way past. A fetch already under way is
    /// left alone rather than restarted: the second button is the same button,
    /// and what an interrupted attempt left behind is picked up by the next
    /// press rather than fetched again (ADR-0014).
    private func fetchTheSpellingsPart() {
        guard fetchingTheSpellingsPart == nil else { return }

        let engine = engineDownload
        // Opened at the committed figure — the one the button the user just
        // pressed had on it — and replaced by the repository's own total the
        // moment the first bytes land. A bar that started blank would be a
        // download that looks like nothing happening (`docs/product-experience.md` §12).
        theSpellingsPartSoFar = EngineDownloadProgress(
            downloadedBytes: 0, totalBytes: SpellingsPartOfTheEngine.bytes)
        redrawWhereSpellingsAreShown()

        fetchingTheSpellingsPart = Task { [weak self] in
            // The reports arrive on whichever thread the bytes landed on, so
            // each is handed back to the main actor before it touches a window.
            try? await engine.downloadTheSpellingsPart { arrived in
                Task { @MainActor in self?.theSpellingsPartArrived(arrived) }
            }
            // Whether it finished or stopped, the row goes back to asking the
            // disk: a fetch that failed halfway leaves the part missing and the
            // offer standing, which is the truth about what the machine has.
            self?.fetchingTheSpellingsPart = nil
            self?.theSpellingsPartSoFar = nil
            self?.redrawWhereSpellingsAreShown()
        }
    }

    private func theSpellingsPartArrived(_ progress: EngineDownloadProgress) {
        // Only while the fetch is still the one this belongs to. A report can
        // arrive after the transfer that made it has ended, and a bar that came
        // back after the row had gone would be a window saying a download was
        // under way when none is.
        guard fetchingTheSpellingsPart != nil else { return }
        theSpellingsPartSoFar = progress
        redrawWhereSpellingsAreShown()
    }

    /// Forgets every Spelling, from the button on the Settings row.
    ///
    /// It empties Spellings and only Spellings: History is a different store
    /// with a different button, and one action doing both would be one of them
    /// forgotten by accident (ADR-0014).
    private func forgetEverySpelling() {
        Task {
            try? await spellings.forgetEverything()
            redrawWhereSpellingsAreShown()
        }
    }

    /// Draws both windows that show Spellings, wherever either is open.
    private func redrawWhereSpellingsAreShown() {
        settingsWindow.redrawIfShowing()
        historyWindow.redrawIfShowing()
    }

    @objc private func menuBarItemPicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? MenuBarItem else { return }
        switch item {
        case .allowPermission(let permission):
            // Asked for directly rather than through `SayingWhatIsMissing`,
            // which is what keeps Cheppu from saying the same thing twice
            // unasked. This one was asked for: the user picked the item.
            PermissionRequest.ask(for: permission, toWatch: preferences.hotkey())
        case .history:
            historyWindow.show()
        case .settings:
            settingsWindow.show()
        case .cues(let areOn):
            preferences.turnCues(on: !areOn)
            // The same switch is a line in the Settings window, which may be
            // open behind the menu. The menu itself needs nothing: it is filled
            // again the next time it is opened.
            settingsWindow.redrawIfShowing()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
