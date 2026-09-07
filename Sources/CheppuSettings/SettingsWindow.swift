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
public final class SettingsWindow: NSObject {
    private let preferences: Preferences
    private let launchAtLogin: LaunchAtLogin
    private let permissions: any Permissions

    /// Empties History, which is the store's to do and not this window's
    /// (ADR-0009).
    private let clearHistory: () -> Void

    /// Says the Cue switch has moved. It is a menu bar item as well as a line
    /// here, and a tick that disagreed with the sound would be worse than
    /// either.
    private let cuesMoved: () -> Void

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
        whenTheCuesMove cuesMoved: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.permissions = permissions
        self.clearHistory = clearHistory
        self.cuesMoved = cuesMoved
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
    }

    @objc private func cameBackToTheFront() {
        redrawIfShowing()
    }

    /// Draws the screen the core describes.
    private func fill() {
        for view in everything.arrangedSubviews {
            everything.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let screen = SettingsScreen(
            cleanup: preferences.rules(),
            areCuesOn: preferences.areCuesOn(),
            launchesAtLogin: launchAtLogin.isOn,
            permissions: Permission.allCases.reduce(into: [:]) { statuses, permission in
                statuses[permission] = permissions.status(of: permission)
            }
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
            }
        }

        return ReadingRow(control, saying: itsTitle, status: status(of: control)) { [weak self] in
            self?.act(on: control)
        }
    }

    /// What the row says about itself where it is a reading rather than a
    /// switch. A permission says whether Cheppu has it; History says nothing
    /// beyond what it already keeps.
    private func status(of control: SettingsControl) -> String? {
        guard case .permission(_, let status) = control else { return nil }
        return status.name
    }

    /// Carries out what flicking a switch means, at the moment it is flicked.
    private func move(_ control: SettingsControl, on: Bool) {
        switch control {
        case .cleanupRule(let rule, _):
            preferences.turn(rule, on: on)
        case .cues:
            preferences.turnCues(on: on)
            cuesMoved()
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
        case .permission, .history:
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
        case .permission(let permission, _):
            SystemSettingsPane.open(permission)
        case .history:
            // Nothing is asked first. Somebody reaching for this has had
            // someone walk up behind them, and a dialog between them and an
            // empty History is the difference between a promise kept and a
            // promise explained (`docs/product-experience.md` §10).
            clearHistory()
        case .cleanupRule, .cues, .launchAtLogin:
            break
        }
    }
}

/// A row the user can flick: a checkbox, and one line under it where the label
/// alone does not say what it does.
@MainActor
private final class SwitchRow: NSView {
    private let moved: (Bool) -> Void

    init(_ control: SettingsControl, isOn: Bool, moved: @escaping (Bool) -> Void) {
        self.moved = moved
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let box = NSButton(
            checkboxWithTitle: control.title, target: self, action: #selector(flicked(_:)))
        box.state = isOn ? .on : .off
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)

        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])

        guard let said = control.explanation else {
            box.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
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
