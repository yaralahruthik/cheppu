import AppKit
import CheppuCore

/// The one window everything about Cheppu is set in.
///
/// One screen, no tabs, and nothing that has to be scrolled to be found: the
/// whole of what Cheppu can be set to is a handful of switches, and a user who
/// has to go looking for one is a user exploring an app they wanted to be
/// invisible (`docs/product-experience.md` §11).
///
/// Every switch takes effect where it is flicked. Nothing is applied on the way
/// out, because there is no way out — the window has no OK and no Cancel, and
/// closing it is closing a window rather than agreeing to anything.
///
/// It is rebuilt each time it is opened, and again whenever Cheppu is brought
/// back to the front, so that a permission granted in System Settings while
/// this window was sitting behind it is a permission this window says Cheppu
/// has.
///
/// This is glue: what it does is lay out and render `SettingsScreen`. Which
/// controls there are, what each says and which way each is set are decided in
/// the core and in `Preferences`, and tested there.
@MainActor
public final class SettingsWindow: NSObject, NSWindowDelegate {
    private let preferences: Preferences
    private let launchAtLogin: LaunchAtLogin
    private let permissions: any Permissions

    /// Empties History, which is the store's to do and not this window's
    /// (ADR-0009).
    private let clearHistory: () -> Void

    /// What the Spellings row reads this instant: how many there are, or that
    /// the part of the Engine that reads them is missing or on its way.
    ///
    /// Asked rather than held, like everything else on this screen — but asked
    /// with a suspension, because the answer is a file and a directory rather
    /// than a preference. So it is read on the way in and the screen is drawn
    /// again when it arrives, which is a fraction of a second the user spends
    /// looking at a row that says nothing rather than at no window at all.
    private let readSpellings: () async -> SpellingsRow

    /// Forgets every Spelling, which is the store's to do and not this
    /// window's — and which emptying History does not do (ADR-0014).
    private let forgetSpellings: () -> Void

    /// Fetches the part of the Engine that reads them. Nothing happens until
    /// this is called, and nothing calls it but a button.
    private let fetchTheSpellingsPart: () -> Void

    /// What the row said last time it was asked. Drawn from until the answer
    /// arrives, so that opening the window twice does not flicker through a
    /// row that has forgotten what it knew.
    ///
    /// Seeded from the switch, which is a preference and answers on the spot
    /// (ADR-0010), and from nothing taught — the reading in which the row says
    /// least. Not from the part being missing, which would be the pessimistic
    /// seed the permission rows take and is the wrong one here: "not granted"
    /// is a true thing to say about a permission nobody has answered for, while
    /// offering a 103 MB download for something already on the machine is a
    /// sentence the user would act on.
    private lazy var spellings: SpellingsRow = .theEngineCanReadThem(
        areOn: preferences.areSpellingsRead(), howMany: 0)

    /// Says the Hotkey has moved, so that whoever is watching the keyboard
    /// watches for the new one. Cheppu is not told which key it is: it reads
    /// that where it uses it, exactly as it reads every other switch
    /// (ADR-0010).
    private let hotkeyMoved: () -> Void

    /// Listening for the key the user wants, while they are choosing one.
    private var recorder: HotkeyRecorder?

    private var window: NSWindow?
    private let everything = NSStackView()

    /// Wide enough for the longest line on the screen and no wider. A settings
    /// window is read once and then never again, so it is sized to be taken in
    /// rather than to be lived in — which is also why it does not resize.
    private static let width: CGFloat = 460
    private static let margin: CGFloat = 20
    private static let betweenSections: CGFloat = 18
    private static let betweenRows: CGFloat = 8

    public init(
        setting preferences: Preferences,
        launchingAtLogin launchAtLogin: LaunchAtLogin = LaunchAtLogin(),
        asking permissions: any Permissions,
        clearingHistory clearHistory: @escaping () -> Void,
        readingSpellings readSpellings: @escaping () async -> SpellingsRow,
        forgettingSpellings forgetSpellings: @escaping () -> Void,
        fetchingTheSpellingsPart fetchTheSpellingsPart: @escaping () -> Void,
        whenTheHotkeyMoves hotkeyMoved: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.permissions = permissions
        self.clearHistory = clearHistory
        self.readSpellings = readSpellings
        self.forgetSpellings = forgetSpellings
        self.fetchTheSpellingsPart = fetchTheSpellingsPart
        self.hotkeyMoved = hotkeyMoved
        super.init()
    }

    /// Opens Settings, showing how everything is set this instant.
    ///
    /// Cheppu is an accessory app with no Dock icon, so it activates itself
    /// first: a window ordered front by an app that is not active would open
    /// behind whatever the user is working in.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window

        fill()
        askWhatTheSpellingsRowSays()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            // Sized to its contents as soon as it is filled; this is only what
            // it is born at.
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.width, height: 100)),
            // No resizing and no minimising: there is nothing here to make
            // bigger, and a settings window in the Dock is a window the user
            // has lost.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        // So that a window closed while it was listening for a Hotkey stops
        // listening. Otherwise the keys pressed at Cheppu the next time it came
        // to the front would still be going into a recording nobody can see.
        window.delegate = self
        window.center()

        everything.orientation = .vertical
        everything.alignment = .leading
        everything.spacing = Self.betweenSections
        everything.edgeInsets = NSEdgeInsets(
            top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        everything.translatesAutoresizingMaskIntoConstraints = false

        let contents = NSView()
        contents.addSubview(everything)
        NSLayoutConstraint.activate([
            everything.topAnchor.constraint(equalTo: contents.topAnchor),
            everything.leadingAnchor.constraint(equalTo: contents.leadingAnchor),
            everything.trailingAnchor.constraint(equalTo: contents.trailingAnchor),
            everything.bottomAnchor.constraint(equalTo: contents.bottomAnchor),
        ])
        window.contentView = contents

        // A permission is granted in another app, and macOS tells nobody. So
        // the statuses are read again every time Cheppu comes back to the
        // front, which is exactly what coming back from System Settings looks
        // like.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cameBackToTheFront),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        return window
    }

    /// Draws the screen again where the window is open, because something it
    /// shows moved somewhere else: the Cue switch is a menu bar item too, and a
    /// checkbox disagreeing with a tick is worse than either.
    public func redrawIfShowing() {
        guard window?.isVisible == true else { return }
        fill()
        askWhatTheSpellingsRowSays()
    }

    /// Reads the Spellings row and draws the screen again with it.
    ///
    /// Separate from `fill()` because it suspends and `fill()` does not: every
    /// other row on this screen is a preference or a question macOS answers on
    /// the spot, and a window that waited for a file before it appeared would
    /// be a window that appeared late for the sake of one line.
    private func askWhatTheSpellingsRowSays() {
        Task {
            let says = await readSpellings()
            guard says != spellings else { return }
            spellings = says
            guard window?.isVisible == true else { return }
            fill()
        }
    }

    @objc private func cameBackToTheFront() {
        redrawIfShowing()
    }

    public func windowWillClose(_ notification: Notification) {
        // Stopped, and not redrawn: the window this would draw into is on its
        // way out.
        recorder?.stopListening()
        recorder = nil
    }

    /// Draws the screen the core describes.
    private func fill() {
        for view in everything.arrangedSubviews {
            everything.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let hotkey = preferences.hotkey()
        let screen = SettingsScreen(
            hotkey: hotkey,
            isChoosingAHotkey: recorder?.isListening == true,
            cleanup: preferences.rules(),
            areCuesOn: preferences.areCuesOn(),
            launchesAtLogin: launchAtLogin.isOn,
            permissions: Permission.neededBy(hotkey).reduce(into: [:]) { statuses, permission in
                statuses[permission] = permissions.status(of: permission)
            },
            spellings: spellings
        )

        for section in screen.sections {
            let view = self.view(for: section)
            everything.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: everything.widthAnchor, constant: -2 * Self.margin)
                .isActive = true
        }

        // Laid out before it is measured. The rows that wrap — a permission's
        // reason, what History keeps — are a line taller than their first guess
        // once they know how wide they are, and a window sized to the guess
        // would cut off the bottom of a screen that has nothing to scroll.
        everything.layoutSubtreeIfNeeded()
        window?.setContentSize(
            NSSize(width: Self.width, height: everything.fittingSize.height)
        )
    }

    private func view(for section: SettingsScreen.Section) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = Self.betweenRows
        rows.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: section.title)
        heading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        rows.addArrangedSubview(heading)

        for control in section.controls {
            let row = view(for: control, saying: section.saysItsOwnTitle(control))
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        return rows
    }

    private func view(for control: SettingsControl, saying itsTitle: Bool) -> NSView {
        if let isOn = control.isOn {
            return SwitchRow(control, isOn: isOn) { [weak self] moved in
                self?.move(control, on: moved)
            } acted: { [weak self] in
                self?.act(on: control)
            }
        }

        return ReadingRow(control, saying: itsTitle, status: control.reading) { [weak self] in
            self?.act(on: control)
        }
    }

    /// Carries out what flicking a switch means, at the moment it is flicked.
    private func move(_ control: SettingsControl, on: Bool) {
        switch control {
        case .cleanupRule(let rule, _):
            preferences.turn(rule, on: on)
        case .cues:
            // Nobody is told. The Cue switch is a menu bar item as well as a
            // line here, and the menu is filled as it opens: it is already
            // saying what this window just did.
            preferences.turnCues(on: on)
        case .spellings:
            // Off keeps them and stops reading them, so a Spelling suspected of
            // misfiring can be ruled out in one flick and put back in another
            // (ADR-0014). Nothing is forgotten by this, and nothing is told:
            // the Engine reads the switch where it uses it (ADR-0010).
            preferences.turnSpellings(on: on)
        case .launchAtLogin:
            // Drawn again from what the system says afterwards rather than from
            // what was asked for: a registration that would not take must not
            // leave a switch saying Cheppu will launch when it will not. And
            // where it would not take, the switch snapping back on its own
            // would be the app failing silently, so it says why in one line.
            let took = launchAtLogin.turn(on: on)
            // On the next turn of the run loop rather than here: this is called
            // from the checkbox's own action, and redrawing takes that checkbox
            // out from under the click that is still being delivered.
            Task {
                if took != on { sayLoginItemsRefused(asking: on) }
                fill()
            }
        case .hotkey, .permission, .history:
            break
        }
    }

    /// Says that macOS would not move the login item, in the one line it is
    /// worth.
    ///
    /// Nearly always the same cause: this copy of Cheppu is not an installed
    /// app — it is a build being run out of a folder — and `SMAppService` will
    /// not register one. There is nothing in what it throws that the user could
    /// act on, so what they are told is the thing they can.
    private func sayLoginItemsRefused(asking on: Bool) {
        let alert = NSAlert()
        alert.messageText =
            on
            ? "macOS would not add Cheppu to your login items"
            : "macOS would not remove Cheppu from your login items"
        alert.informativeText =
            "This usually means Cheppu is being run from somewhere other than your Applications "
            + "folder. Move it there and try again, or use System Settings > General > Login "
            + "Items."
        alert.runModal()
    }

    /// Carries out the button on a row that is not a switch.
    private func act(on control: SettingsControl) {
        switch control {
        case .hotkey(_, let isBeingChosen):
            if isBeingChosen { stopChoosingAHotkey() } else { chooseAHotkey() }
        case .permission(let permission, _):
            SystemSettingsPane.open(permission)
        case .history:
            // Nothing is asked first. Somebody reaching for this has had
            // someone walk up behind them, and a dialog between them and an
            // empty History is the difference between a promise kept and a
            // promise explained (`docs/product-experience.md` §10).
            clearHistory()
        case .spellings(let row):
            act(on: row)
        case .cleanupRule, .cues, .launchAtLogin:
            break
        }
    }

    /// The one button the Spellings row has, whichever button that is.
    ///
    /// Which one it is is the row's, decided in the core beside the sentence
    /// above it, so that a screen offering to fetch something already here — or
    /// to forget nothing — is not a thing this window can draw.
    private func act(on row: SpellingsRow) {
        switch row {
        case .theEngineCanReadThem:
            forgetSpellings()
        case .thePartIsMissing:
            fetchTheSpellingsPart()
        case .thePartIsArriving:
            break
        }
    }

    // MARK: - Choosing a Hotkey

    /// Starts listening for the key the user wants to dictate with.
    ///
    /// The row says so while it listens. A window that took the next keystroke
    /// without saying it was about to would be one that stole a Command-Q.
    private func chooseAHotkey() {
        recorder = HotkeyRecorder { [weak self] chosen in
            guard let self else { return }
            recorder = nil
            // On the next turn of the run loop rather than here: this is called
            // from inside the handling of the keystroke that chose the Hotkey,
            // and what follows it puts an alert on the screen.
            Task {
                if let chosen { take(chosen) } else { fill() }
            }
        }
        recorder?.listen()
        redrawAfterTheClick()
    }

    private func stopChoosingAHotkey() {
        recorder?.stopListening()
        recorder = nil
        redrawAfterTheClick()
    }

    /// Draws the screen again on the next turn of the run loop.
    ///
    /// Not here: this is called from a row's own button, and redrawing takes
    /// that button out from under the click that is still being delivered — the
    /// same reason the login-item switch waits.
    private func redrawAfterTheClick() {
        Task { fill() }
    }

    /// Takes the Hotkey the user just pressed, once they have been told what it
    /// costs them.
    ///
    /// The warning comes between the press and the setting rather than after
    /// it: a user who is told what a key does once it is already theirs has
    /// been informed rather than asked.
    private func take(_ hotkey: Hotkey) {
        guard hotkey.warnings.isEmpty || saysYesTo(hotkey) else {
            fill()
            return
        }

        preferences.choose(hotkey)
        // Asked for here, at the moment the user's own choice makes it
        // necessary, and never for a Hotkey that does not need it.
        if hotkey.needsInputMonitoring { permissions.ask(for: .inputMonitoring) }
        hotkeyMoved()
        fill()
    }

    /// Says what the chosen key will cost, and asks whether they still want it.
    ///
    /// Everything they have to know in one alert rather than one after another,
    /// because it is one decision: this key, or another one.
    private func saysYesTo(_ hotkey: Hotkey) -> Bool {
        let warnings = hotkey.warnings
        let alert = NSAlert()
        // The first, which is the Globe key's wherever there are two: what a
        // key needs before it works at all outranks what it would double.
        alert.messageText = warnings[0].title
        alert.informativeText = warnings.map(\.explanation).joined(separator: "\n\n")
        alert.addButton(withTitle: "Use \(hotkey.name)")
        alert.addButton(withTitle: "Choose Another Key")

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// A row the user can flick: a checkbox, and one line under it where the label
/// alone does not say what it does.
@MainActor
private final class SwitchRow: NSView {
    private let moved: (Bool) -> Void
    private let acted: () -> Void

    /// - Parameter acted: what the row's button does, where it has one. Only
    ///   the Spellings row does: it is both a decision the user makes — whether
    ///   the Engine reads them — and a thing they hold, which they can ask
    ///   Cheppu to forget (ADR-0014).
    init(
        _ control: SettingsControl, isOn: Bool, moved: @escaping (Bool) -> Void,
        acted: @escaping () -> Void
    ) {
        self.moved = moved
        self.acted = acted
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let box = NSButton(
            checkboxWithTitle: control.title, target: self, action: #selector(flicked(_:)))
        box.state = isOn ? .on : .off
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)

        // Placed first where there is one, because it is what the rest of the
        // row has to fit beside — the same reason `ReadingRow` places its
        // button before its lines.
        let button = control.action.map { action -> NSButton in
            let button = NSButton(title: action, target: self, action: #selector(pressed))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(button)
            NSLayoutConstraint.activate([
                button.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.leadingAnchor.constraint(
                    greaterThanOrEqualTo: box.trailingAnchor, constant: 12),
            ])
            return button
        }

        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        guard let said = control.explanation else {
            box.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            if let button {
                bottomAnchor.constraint(greaterThanOrEqualTo: button.bottomAnchor).isActive = true
            }
            return
        }

        let explanation = NSTextField(wrappingLabelWithString: said)
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.translatesAutoresizingMaskIntoConstraints = false
        addSubview(explanation)

        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 2),
            // Lined up under the label rather than under the box, the way every
            // other checkbox on the machine explains itself.
            explanation.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            explanation.trailingAnchor.constraint(equalTo: trailingAnchor),
            explanation.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SwitchRow is built in code, not in a nib.")
    }

    @objc private func flicked(_ sender: NSButton) {
        moved(sender.state == .on)
    }

    @objc private func pressed() {
        acted()
    }
}

/// A row the user can read and, where there is something to be done about it,
/// one button doing it: a permission, or History.
@MainActor
private final class ReadingRow: NSView {
    private let acted: () -> Void

    init(
        _ control: SettingsControl, saying itsTitle: Bool, status: String?,
        acted: @escaping () -> Void
    ) {
        self.acted = acted
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // The button is placed first, because it is what the rest of the row
        // has to fit beside: a line that did not know where the button starts
        // is a line with no width, and a wrapping label with no width truncates
        // rather than wraps.
        let button = control.action.map { action -> NSButton in
            let button = NSButton(title: action, target: self, action: #selector(pressed))
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: topAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            return button
        }

        let rightEdge = button?.leadingAnchor ?? trailingAnchor
        let gap: CGFloat = button == nil ? 0 : 12

        var below = topAnchor
        var spacing: CGFloat = 0

        for line in Self.lines(control, saying: itsTitle, status: status) {
            addSubview(line)
            NSLayoutConstraint.activate([
                line.topAnchor.constraint(equalTo: below, constant: spacing),
                line.leadingAnchor.constraint(equalTo: leadingAnchor),
                line.trailingAnchor.constraint(equalTo: rightEdge, constant: -gap),
            ])
            below = line.bottomAnchor
            spacing = 2
        }

        below.constraint(equalTo: bottomAnchor).isActive = true

        // A row is never shorter than the button standing in it.
        if let button {
            bottomAnchor.constraint(greaterThanOrEqualTo: button.bottomAnchor).isActive = true
        }
    }

    /// What the row says, from the top: its name where the heading has not
    /// already said it, what it reads this instant, and the one sentence
    /// explaining it.
    private static func lines(
        _ control: SettingsControl, saying itsTitle: Bool, status: String?
    ) -> [NSTextField] {
        var lines: [NSTextField] = []

        if itsTitle {
            lines.append(NSTextField(labelWithString: control.title))
        }

        if let status {
            let reading = NSTextField(labelWithString: status)
            reading.textColor = .secondaryLabelColor
            lines.append(reading)
        }

        if let explanation = control.explanation {
            // Wrapping rather than truncating: the sentence under a row is the
            // whole of what the user is told about it, and half of one is worse
            // than none (`docs/product-experience.md` §11).
            let line = NSTextField(wrappingLabelWithString: explanation)
            line.textColor = .secondaryLabelColor
            line.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            lines.append(line)
        }

        for line in lines { line.translatesAutoresizingMaskIntoConstraints = false }
        return lines
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ReadingRow is built in code, not in a nib.")
    }

    @objc private func pressed() {
        acted()
    }
}
