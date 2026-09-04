import AppKit
import CheppuCore

/// The window History is read in.
///
/// It exists for one moment: the user dictated something and it went into the
/// wrong window, or nowhere at all, and they want it back. So it opens on the
/// newest Dictation, every row can be copied in one click, and the whole store
/// can be emptied in one more (`docs/product-experience.md` §4 and §10).
///
/// It reads the store each time it is opened rather than following it, because
/// a Dictation is something the user does somewhere else: a window that updated
/// while they were typing into their email would be a window they were not
/// looking at.
///
/// This is glue: what it does is lay out and render what the store hands back.
/// Which Dictations there are, what order they come in and what clearing means
/// are decided in `History` and `HistoryStore`, and tested there.
@MainActor
public final class HistoryWindow: NSObject {
    private let store: HistoryStore

    private var window: NSWindow?
    private let rows = NSStackView()
    private let nothingYet = NSTextField(labelWithString: "Nothing dictated yet.")

    private static let size = NSSize(width: 460, height: 540)
    private static let margin: CGFloat = 16

    public init(reading store: HistoryStore) {
        self.store = store
        super.init()
    }

    /// Opens History, showing what the store holds this instant.
    ///
    /// Cheppu is an accessory app with no Dock icon, so it activates itself
    /// first: a window ordered front by an app that is not active would open
    /// behind whatever the user is working in.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window

        Task {
            fill(with: await store.read())
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Draws History again where the window is open, because the store was
    /// emptied somewhere else — the button in the Settings window.
    ///
    /// A window still listing what the user has just asked Cheppu to forget
    /// would be the one lie History cannot afford to tell, even for as long as
    /// it takes them to click on it again.
    public func redrawIfShowing() {
        guard window?.isVisible == true else { return }
        Task { fill(with: await store.read()) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = contents()
        return window
    }

    /// The window's one view: the Dictations, and the two things that can be
    /// done with the store as a whole under them.
    private func contents() -> NSView {
        let contents = NSView()

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows

        nothingYet.textColor = .secondaryLabelColor
        nothingYet.translatesAutoresizingMaskIntoConstraints = false

        // What the store is, said where the user is looking at it. History is
        // the one part of Cheppu that keeps anything, so what it keeps and
        // where should not have to be taken on trust.
        let whatIsKept = NSTextField(
            labelWithString:
                "The last \(History.capacity) dictations, kept on this Mac and nowhere else."
        )
        whatIsKept.textColor = .secondaryLabelColor
        whatIsKept.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        whatIsKept.translatesAutoresizingMaskIntoConstraints = false

        let clear = NSButton(
            title: "Clear History", target: self, action: #selector(clearEverything))
        clear.bezelStyle = .rounded
        clear.translatesAutoresizingMaskIntoConstraints = false

        for view in [scroll, nothingYet, whatIsKept, clear] {
            contents.addSubview(view)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contents.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: contents.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contents.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: clear.topAnchor, constant: -Self.margin),

            // The rows are as wide as the window: a Dictation is a paragraph,
            // and a column that sized itself to its longest one would be a
            // window scrolling sideways.
            rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            nothingYet.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            nothingYet.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),

            whatIsKept.leadingAnchor.constraint(
                equalTo: contents.leadingAnchor, constant: Self.margin),
            whatIsKept.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            whatIsKept.trailingAnchor.constraint(
                lessThanOrEqualTo: clear.leadingAnchor, constant: -Self.margin),

            clear.trailingAnchor.constraint(
                equalTo: contents.trailingAnchor, constant: -Self.margin),
            clear.bottomAnchor.constraint(equalTo: contents.bottomAnchor, constant: -Self.margin),
        ])

        return contents
    }

    private func fill(with history: History) {
        for row in rows.arrangedSubviews {
            rows.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for entry in history.entries {
            let row = HistoryRow(entry) { [weak self] in self?.copy(entry) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        nothingYet.isHidden = !history.entries.isEmpty
    }

    private func copy(_ entry: HistoryEntry) {
        // The whole of what was said, not the part of it the row had room for:
        // the user is copying this to put it back where it was meant to go.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.finalText.text, forType: .string)
    }

    /// Empties the store, in the one action the button is.
    ///
    /// Nothing is asked first. Somebody reaching for this has had someone walk
    /// up behind them, and a dialog between them and an empty History is the
    /// difference between a promise kept and a promise explained
    /// (`docs/product-experience.md` §10).
    @objc private func clearEverything() {
        Task {
            try? await store.clear()
            fill(with: await store.read())
        }
    }
}

/// One Dictation, as a row: when it was said, what was said, and a way of
/// taking it back.
@MainActor
private final class HistoryRow: NSView {
    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 6

    /// How much of a Dictation a row shows before it is cut off. Enough to know
    /// which one it is at a glance; Copy takes the whole of it however long it
    /// ran.
    private static let linesShown = 4

    private let copied: () -> Void

    init(_ entry: HistoryEntry, copied: @escaping () -> Void) {
        self.copied = copied
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let when = NSTextField(labelWithString: Self.when(entry.recordedAt))
        when.textColor = .secondaryLabelColor
        when.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        when.translatesAutoresizingMaskIntoConstraints = false

        let said = NSTextField(wrappingLabelWithString: entry.finalText.text)
        said.maximumNumberOfLines = Self.linesShown
        said.lineBreakMode = .byTruncatingTail
        said.isSelectable = true
        said.translatesAutoresizingMaskIntoConstraints = false

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyThisOne))
        copy.bezelStyle = .rounded
        copy.controlSize = .small
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.setContentHuggingPriority(.required, for: .horizontal)

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false

        for view in [when, said, copy, line] { addSubview(view) }

        NSLayoutConstraint.activate([
            when.topAnchor.constraint(equalTo: topAnchor, constant: Self.margin),
            when.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.margin),

            copy.centerYAnchor.constraint(equalTo: when.centerYAnchor),
            copy.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.margin),
            copy.leadingAnchor.constraint(
                greaterThanOrEqualTo: when.trailingAnchor, constant: Self.gap),

            said.topAnchor.constraint(equalTo: when.bottomAnchor, constant: Self.gap),
            said.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.margin),
            said.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.margin),
            said.bottomAnchor.constraint(equalTo: line.topAnchor, constant: -Self.margin),

            line.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HistoryRow is built in code, not in a nib.")
    }

    @objc private func copyThisOne() {
        copied()
    }

    /// When a Dictation was made, in the user's own format: the time on its own
    /// for one made today, and the date with it for anything older.
    private static func when(_ moment: Date) -> String {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = Calendar.current.isDateInToday(moment) ? .none : .medium
        return format.string(from: moment)
    }
}
