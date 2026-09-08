import AppKit
import CheppuAudio
import CheppuCore
import CheppuSettings

/// The first launch, on screen: one window, one thing asked for at a time, and
/// a Dictation at the end of it (`docs/product-experience.md` §12).
///
/// It is the only window Cheppu opens without being asked. Everything else —
/// Settings, History — is something the user went to the menu bar for; this is
/// what a fresh install does on its own, once, and then never again.
///
/// The screens it draws are `Onboarding`'s, and so is every sentence on them.
/// What is here is the four things a screen cannot do for itself: put the macOS
/// Microphone prompt up, open a System Settings pane, fetch the Engine and
/// report what has arrived, and hold the field the practice Dictation lands in.
/// Which step follows which, what each says and what its button reads are
/// decided in the core and tested there.
///
/// The practice Dictation is not run from here. It is the Hotkey, the
/// microphone, the Engine and the Insertion that every other Dictation is —
/// this window's whole part in it is owning a text field and being the app in
/// front, so that the one thing that can go wrong is Cheppu rather than
/// somebody else's text box.
///
/// This is glue: it lays out and performs. That is why it is not tested.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let permissions: any Permissions
    private let engine: any EngineDownloadPort

    /// What only this window knows about the sequence: what macOS has already
    /// been asked, how the download is going, and whether the words have
    /// landed. Everything else it draws is read afresh from macOS and from the
    /// user's preferences each time, exactly as the Settings window reads them
    /// (ADR-0010).
    private var hasAskedForTheMicrophone = false
    private var download: EngineDownloadState = .notStarted
    private var hasDictated = false

    /// The screen on the glass, so that a redraw that would change nothing
    /// changes nothing. The window is redrawn every two seconds while it is
    /// open and on every megabyte that arrives; without this, the practice
    /// field would have the cursor put back into it twice a second while
    /// somebody was reading the sentence above it.
    private var showing: Onboarding?

    private var window: NSWindow?
    private var fetching: Task<Void, Never>?
    private var watching: Task<Void, Never>?

    /// How long to leave between asking macOS again whether it has been granted
    /// something.
    ///
    /// A permission is granted in another app and macOS tells nobody, so the
    /// alternative to asking again is a screen that sits there after the user
    /// has done exactly what it asked. Two seconds is the same wait the Hotkey
    /// watch spends on the same question.
    private static let whileWaitingForAGrant: Duration = .seconds(2)

    private static let width: CGFloat = 460
    private static let height: CGFloat = 300
    private static let margin: CGFloat = 20

    private let heading = NSTextField(labelWithString: "")
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let bar = NSProgressIndicator()
    private let field = PracticeField()
    private let box = NSScrollView()
    private let caption = NSTextField(labelWithString: "")
    private lazy var button = NSButton(title: "", target: self, action: #selector(pressed))

    init(
        setting preferences: Preferences,
        asking permissions: any Permissions,
        fetching engine: any EngineDownloadPort
    ) {
        self.preferences = preferences
        self.permissions = permissions
        self.engine = engine
        super.init()
    }

    /// Whether the user still has a first launch owed to them.
    var isOwed: Bool {
        !preferences.hasFinishedOnboarding()
    }

    /// Whether the sequence is in front of the user this instant.
    ///
    /// Asked by whatever else would say something about a permission. This
    /// window is asking for them one at a time, with a reason and a pane, and
    /// an alert saying the same thing over the top of it would be Cheppu asking
    /// twice for what it is already asking for once.
    var isShowing: Bool {
        window?.isVisible == true
    }

    /// Opens the sequence where the user left off.
    ///
    /// Cheppu is an accessory app with no Dock icon, so it activates itself
    /// first — a window ordered front by an app that is not active opens behind
    /// whatever is in front of it, which for the one window that has to be read
    /// is fatal.
    func show() {
        let window = window ?? makeWindow()
        self.window = window

        // Whatever is already true is already done: a permission granted last
        // week and an Engine that is already here are steps the user never
        // sees.
        Task { await lookForTheEngine() }
        redraw()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        watchForAGrant()
    }

    // MARK: - The window

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(
                origin: .zero, size: NSSize(width: Self.width, height: Self.height)),
            // One size for every step. A window that resized itself between
            // "allow the microphone" and "say something" would be four windows
            // that happened to follow one another.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Cheppu"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.contentView = contents()

        // A permission is granted in System Settings, and coming back to Cheppu
        // is what that looks like from in here.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cameBackToTheFront),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        return window
    }

    /// Lays the window out once. What each part says is filled in on every
    /// redraw; where they sit never moves.
    private func contents() -> NSView {
        let contents = NSView()

        heading.font = .systemFont(ofSize: NSFont.systemFontSize + 4, weight: .semibold)
        explanation.textColor = .secondaryLabelColor

        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small

        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .tertiaryLabelColor
        button.bezelStyle = .rounded

        let said = NSStackView(views: [heading, explanation, bar, practiceField()])
        said.orientation = .vertical
        said.alignment = .leading
        said.spacing = 12
        said.translatesAutoresizingMaskIntoConstraints = false

        for view in [said, caption, button] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contents.addSubview(view)
        }

        NSLayoutConstraint.activate([
            said.topAnchor.constraint(equalTo: contents.topAnchor, constant: Self.margin),
            said.leadingAnchor.constraint(equalTo: contents.leadingAnchor, constant: Self.margin),
            said.trailingAnchor.constraint(equalTo: contents.trailingAnchor, constant: -Self.margin),

            explanation.widthAnchor.constraint(equalTo: said.widthAnchor),
            bar.widthAnchor.constraint(equalTo: said.widthAnchor),
            box.widthAnchor.constraint(equalTo: said.widthAnchor),
            box.heightAnchor.constraint(equalToConstant: 96),

            // The button and how far along the user is sit on the bottom edge,
            // where they are in the same place on every screen: one thing to
            // press, in one place, four times running.
            button.trailingAnchor.constraint(
                equalTo: contents.trailingAnchor, constant: -Self.margin),
            button.bottomAnchor.constraint(equalTo: contents.bottomAnchor, constant: -Self.margin),
            caption.leadingAnchor.constraint(
                equalTo: contents.leadingAnchor, constant: Self.margin),
            caption.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            said.bottomAnchor.constraint(lessThanOrEqualTo: button.topAnchor, constant: -Self.margin),
        ])

        return contents
    }

    /// The field the practice Dictation goes into: a text view Cheppu owns, in
    /// a window Cheppu owns.
    ///
    /// The point of it is what it is not. A first Dictation aimed at whatever
    /// app the user happened to have open can fail for reasons that are nothing
    /// to do with Cheppu — a web page that swallows a paste, an editor with
    /// modes — and a first attempt that failed for somebody else's reason is
    /// indistinguishable from an app that does not work.
    private func practiceField() -> NSView {
        // The words arriving by paste is what the practice step waits for, and
        // the field is what can tell that from somebody typing.
        field.wordsWerePasted = { [weak self] in self?.wordsLanded() }
        field.isEditable = true
        field.isRichText = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textContainerInset = NSSize(width: 6, height: 8)
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.autoresizingMask = [.width]
        field.minSize = NSSize(width: 0, height: 0)
        field.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        field.textContainer?.widthTracksTextView = true
        field.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)

        box.documentView = field
        box.hasVerticalScroller = true
        box.borderType = .bezelBorder
        box.drawsBackground = true
        return box
    }

    // MARK: - Drawing what is true

    /// Draws the step the user is on, and nothing if that has not moved.
    ///
    /// Everything it is built from is asked for again here — what macOS says
    /// about each permission, and which key the user dictates with — rather
    /// than remembered from when the window opened, because all of it can
    /// change while this window is sitting on the screen.
    private func redraw() {
        let hotkey = preferences.hotkey()
        let screen = Onboarding(
            hotkey: hotkey,
            permissions: Permission.neededBy(hotkey).reduce(into: [:]) { statuses, permission in
                statuses[permission] = permissions.status(of: permission)
            },
            hasAskedForTheMicrophone: hasAskedForTheMicrophone,
            engine: download,
            hasDictated: hasDictated
        )
        guard screen != showing else { return }
        // The practice Dictation goes to whichever app is in front when the
        // Hotkey is pressed, exactly as every other Dictation does. So the step
        // that asks for one puts this window in front as it opens, rather than
        // asking somebody to speak into a window that is behind their browser.
        let openingThePracticeStep = screen.step == .practice && showing?.step != .practice
        showing = screen

        heading.stringValue = screen.title
        explanation.stringValue = screen.explanation
        caption.stringValue = screen.whereTheUserIs ?? ""

        button.title = screen.action ?? ""
        button.isHidden = screen.action == nil
        // Return presses the button, except on the two screens that carry the
        // practice field: a key equivalent is answered before the responder
        // chain, so on those it would be a new line in what the user just
        // dictated closing the window instead.
        button.keyEquivalent = screen.showsThePracticeField ? "" : "\r"

        draw(screen)

        box.isHidden = !screen.showsThePracticeField
        // The window is where the user's next keystroke goes, and on this step
        // so is the Hotkey's Insertion: a field that is not the first responder
        // is a Dictation that lands somewhere else in Cheppu's own window.
        if screen.showsThePracticeField, window?.firstResponder !== field {
            window?.makeFirstResponder(field)
        }
        if openingThePracticeStep {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Draws how far the download has got — or, where it has started and has
    /// nothing to report yet, a bar that moves rather than a bar at zero.
    ///
    /// Both of those are the screen's answers rather than this window's: what
    /// there is to watch is `isFetchingTheEngine`, and what there is to measure
    /// is `progress`.
    private func draw(_ screen: Onboarding) {
        bar.isHidden = !screen.isFetchingTheEngine

        guard let progress = screen.progress else {
            bar.isIndeterminate = true
            if screen.isFetchingTheEngine { bar.startAnimation(nil) } else { bar.stopAnimation(nil) }
            return
        }

        bar.stopAnimation(nil)
        bar.isIndeterminate = false
        bar.doubleValue = progress.fractionCompleted
    }

    @objc private func cameBackToTheFront() {
        guard window?.isVisible == true else { return }
        redraw()
    }

    /// Keeps asking macOS whether it has been granted what the screen is asking
    /// for.
    ///
    /// The same question the Hotkey watch asks, for the same reason: nothing
    /// tells an app when a permission is granted or taken away, and a first
    /// launch that only noticed when the user came back to Cheppu would leave
    /// them looking at a screen they have already satisfied.
    private func watchForAGrant() {
        watching?.cancel()
        watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.whileWaitingForAGrant)
                guard let self, !Task.isCancelled, window?.isVisible == true else { return }
                redraw()
            }
        }
    }

    /// Asks the disk whether the Engine is already here.
    ///
    /// Without the network: a user who has downloaded it once — or who is
    /// running a second copy of Cheppu — walks past this step rather than
    /// through it.
    private func lookForTheEngine() async {
        guard download == .notStarted, await engine.isEngineDownloaded() else { return }
        download = .finished
        redraw()
    }

    // MARK: - Doing what the button says

    @objc private func pressed() {
        switch showing?.step {
        // The macOS prompt, while there is still one to show. What the user
        // answers is read off macOS afterwards rather than taken from the
        // prompt, so a "no" and a grant taken away in System Settings a moment
        // later are the same screen.
        case .permission(.microphone) where !hasAskedForTheMicrophone:
            Task {
                hasAskedForTheMicrophone = true
                await MicrophonePermission.request()
                redraw()
            }
        // The same pane the Settings window's button opens, from the same
        // place: an app that knew two ways to the one switch would eventually
        // know one of them wrongly.
        case .permission(let permission):
            SystemSettingsPane.open(permission)
        case .engine:
            fetchTheEngine()
        case .done:
            finish()
        // Nothing to press: the user is being asked to speak.
        case .practice, nil:
            break
        }
    }

    /// Fetches the Engine, and says how far it has got as it arrives.
    ///
    /// An attempt that ends before the Engine is here leaves what arrived on
    /// the machine, and the next one carries on from there — so a dropped
    /// connection costs the user the button and not the bytes behind it.
    private func fetchTheEngine() {
        guard fetching == nil else { return }

        download = .starting
        redraw()

        fetching = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.downloadEngine { arrived in
                    // The report is handed over on whichever queue the transfer
                    // is running on, and everything here is the main actor's.
                    Task { @MainActor [weak self] in self?.arrived(arrived) }
                }
                download = .finished
            } catch {
                download = .interrupted
            }
            fetching = nil
            redraw()
        }
    }

    private func arrived(_ progress: EngineDownloadProgress) {
        // Ignored once the download is over: a report still in flight when the
        // last file landed would take the screen back to a bar that is nearly
        // full.
        guard fetching != nil else { return }
        download = .underWay(progress)
        redraw()
    }

    /// Ends the sequence, and remembers that it is over.
    ///
    /// Written here rather than as the user goes: somebody who closed the
    /// window at the Engine Download has not dictated yet, and the next launch
    /// owes them the rest of it.
    private func finish() {
        preferences.finishOnboarding()
        window?.close()
    }

    // MARK: - The practice Dictation landing

    /// Words pasted into the field is the whole of what the practice step is
    /// waiting for.
    ///
    /// A paste rather than anything the field comes to hold, because an
    /// Insertion *is* a paste: the Final Text goes on the pasteboard and
    /// Command-V is typed as the user would have typed it. Somebody typing
    /// their sentence into the box has not dictated, and neither has somebody
    /// whose Hotkey is a chord whose key lands in the field on the way past —
    /// counting either would end the one step that exists to prove a Dictation
    /// works without one having happened.
    ///
    /// A Command-V the user pressed themselves counts, and should: the words
    /// they are pasting are the ones a Clipboard Fallback just left there for
    /// them, which is a Dictation that ran and said where its words went.
    private func wordsLanded() {
        hasDictated = true
        // On the next turn of the run loop rather than here: this arrives from
        // inside the paste that is still being delivered to the field.
        Task { redraw() }
    }

    func windowWillClose(_ notification: Notification) {
        // The download is deliberately not called off. The Engine is what
        // Cheppu needs whether or not this window is open, and a user who
        // closed the window mid-download and came back to a first launch that
        // had made no progress would rightly conclude nothing was happening.
        watching?.cancel()
        watching = nil
    }
}

/// The field the practice Dictation lands in.
///
/// Two things it does that an `NSTextView` does not. It tells whoever is
/// watching that words arrived by paste, which is how an Insertion arrives and
/// is not how typing arrives. And it answers Command-V itself: pasting is
/// ordinarily the Edit menu's key equivalent, and Cheppu is a menu bar app with
/// no menu bar of its own — so without this, the one keystroke Cheppu types
/// would reach this window and do nothing, which is the one place a first
/// launch cannot afford a Dictation that quietly does not land.
@MainActor
private final class PracticeField: NSTextView {
    /// Told when words arrived by paste. Set once, by the window that owns the
    /// field.
    var wordsWerePasted: (() -> Void)?

    override func paste(_ sender: Any?) {
        super.paste(sender)
        wordsWerePasted?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard held == .command, event.charactersIgnoringModifiers?.lowercased() == "v" else {
            return super.performKeyEquivalent(with: event)
        }
        paste(nil)
        return true
    }
}
