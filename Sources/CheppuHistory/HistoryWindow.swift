import AppKit
import CheppuCore

/// The window History is read in, and the one place a Correction is made.
///
/// It exists for one moment: the user dictated something and it went into the
/// wrong window, or nowhere at all, and they want it back. So it opens on the
/// newest Dictation, every row can be copied in one click, and the whole store
/// can be emptied in one more (`docs/product-experience.md` §4 and §10).
///
/// It is also where Cheppu finds out it was wrong. Nothing is read out of the
/// Target App after Insertion, so a word fixed there is a word Cheppu never
/// hears about; a word fixed here is a Correction, and what it leaves behind is
/// a Spelling (ADR-0014). The Spellings are listed above the Dictations,
/// removable one at a time, so that what the user has taught Cheppu is
/// something they can read and undo rather than something that accumulates
/// where they cannot see it.
///
/// It reads the store each time it is opened rather than following it, because
/// a Dictation is something the user does somewhere else: a window that updated
/// while they were typing into their email would be a window they were not
/// looking at.
///
/// This is glue: what it does is lay out and render what the stores hand back.
/// Which Dictations there are, what order they come in, what clearing means and
/// what an edit teaches are decided in `History`, `HistoryStore`, `Correction`
/// and `Spellings`, and tested there.
@MainActor
public final class HistoryWindow: NSObject {
    private let store: HistoryStore
    private let spellings: SpellingsStore

    /// What the Spellings section says about the part of the Engine that reads
    /// them: that it is here, that it is missing, or that it is on its way.
    ///
    /// Asked of whoever is holding the Engine rather than answered here, so
    /// that this window and the Settings row say the same thing about the same
    /// download — and so that pressing either button feeds the same fetch.
    private let readTheSpellingsRow: () async -> SpellingsRow

    /// Fetches that part. Nothing starts on its own: this is called by a button
    /// and by nothing else (ADR-0014).
    private let fetchTheSpellingsPart: () -> Void

    /// Says a Spelling was kept or forgotten, so that the Settings row — which
    /// counts them — is not left saying a number that has moved.
    private let spellingsMoved: () -> Void

    private var window: NSWindow?
    private let rows = NSStackView()
    private let taught = NSStackView()
    private let nothingYet = NSTextField(labelWithString: "Nothing dictated yet.")

    private static let size = NSSize(width: 460, height: 540)
    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 6

    /// How tall the Spellings are allowed to grow before they scroll inside
    /// themselves. A short section above the Dictations is what it is for; a
    /// user who has corrected forty words must not have to scroll past all
    /// forty to reach the thing they opened this window for.
    private static let tallestTheyGet: CGFloat = 110

    /// - Parameters:
    ///   - store: the Dictations, which this window reads and corrects.
    ///   - teaching: where a Correction's Spellings are kept.
    ///   - showingTheSpellingsRow: what to say about the part of the Engine
    ///     that reads them.
    ///   - fetchingTheSpellingsPart: what the button under that line does.
    ///   - whenSpellingsMove: what to tell the rest of the app when one is kept
    ///     or forgotten.
    public init(
        reading store: HistoryStore,
        teaching spellings: SpellingsStore,
        showingTheSpellingsRow readTheSpellingsRow: @escaping () async -> SpellingsRow,
        fetchingTheSpellingsPart fetchTheSpellingsPart: @escaping () -> Void,
        whenSpellingsMove spellingsMoved: @escaping () -> Void
    ) {
        self.store = store
        self.spellings = spellings
        self.readTheSpellingsRow = readTheSpellingsRow
        self.fetchTheSpellingsPart = fetchTheSpellingsPart
        self.spellingsMoved = spellingsMoved
        super.init()
    }

    /// Opens History, showing what the stores hold this instant.
    ///
    /// Cheppu is an accessory app with no Dock icon, so it activates itself
    /// first: a window ordered front by an app that is not active would open
    /// behind whatever the user is working in.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window

        Task {
            await fill()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Draws History again where the window is open, because a store was
    /// changed somewhere else — the buttons in the Settings window.
    ///
    /// A window still listing what the user has just asked Cheppu to forget
    /// would be the one lie History cannot afford to tell, even for as long as
    /// it takes them to click on it again.
    public func redrawIfShowing() {
        guard window?.isVisible == true else { return }
        Task { await fill() }
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

    /// The window's one view: what the user has taught Cheppu, the Dictations
    /// under it, and the two things that can be done with the store as a whole
    /// under those.
    private func contents() -> NSView {
        let contents = NSView()

        // Above the Dictations rather than inside the list, because it is a
        // short section about something else and a heading that scrolled away
        // would be one nobody found twice. Hidden entirely while there is
        // nothing taught and nothing to offer: a user who has never corrected a
        // word has no reason to read the word "Spellings" here.
        taught.orientation = .vertical
        taught.alignment = .leading
        taught.spacing = Self.gap
        taught.translatesAutoresizingMaskIntoConstraints = false

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

        for view in [taught, scroll, nothingYet, whatIsKept, clear] {
            contents.addSubview(view)
        }

        NSLayoutConstraint.activate([
            taught.topAnchor.constraint(equalTo: contents.topAnchor),
            taught.leadingAnchor.constraint(equalTo: contents.leadingAnchor),
            taught.trailingAnchor.constraint(equalTo: contents.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: taught.bottomAnchor),
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

    /// Reads both stores and draws the window from them.
    private func fill() async {
        fill(
            with: await store.read(),
            taught: await spellings.spellings(),
            says: await readTheSpellingsRow())
    }

    private func fill(with history: History, taught spellings: Spellings, says row: SpellingsRow) {
        empty(rows)

        for entry in history.entries {
            let row = HistoryRow(entry) { [weak self] what in
                switch what {
                case .copied(let entry): self?.copy(entry)
                case .corrected(let was, let now): self?.correct(was, to: now)
                }
            }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        nothingYet.isHidden = !history.entries.isEmpty
        fillTheSpellings(spellings, says: row)
    }

    /// Draws what the user has taught Cheppu, and the offer to fetch the part
    /// of the Engine that reads it where that part is missing.
    ///
    /// The section is there while there is a Spelling to show and gone
    /// otherwise, which is also the whole of when there is a download worth
    /// offering: nothing is fetched for a user who has never corrected a word,
    /// because there would be nothing for it to read.
    private func fillTheSpellings(_ spellings: Spellings, says row: SpellingsRow) {
        empty(taught)

        // There while there is a Spelling to show, or while the part they need
        // is on its way. Gone otherwise: a user who has never corrected a word
        // has no reason to read the word "Spellings" here, and no reason to be
        // offered a download for something they have nothing to read with.
        let worthShowing = !spellings.isEmpty || row.isWorthShowingOnItsOwn
        taught.isHidden = !worthShowing

        // The section's own margins go with it. A hidden stack view still holds
        // the space its insets ask for, which would leave a band of nothing
        // above the Dictations for every user who has never corrected a word.
        taught.edgeInsets = NSEdgeInsets(
            top: worthShowing ? Self.margin : 0,
            left: Self.margin,
            bottom: 0,
            right: Self.margin)

        guard worthShowing else { return }

        let heading = NSTextField(labelWithString: row.title)
        heading.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        taught.addArrangedSubview(heading)

        // A column rather than a row of chips: a Spelling is a word of any
        // length and a row of them would either squash or run off the side of
        // the window. It scrolls inside a height of its own once there are more
        // than a few, so that what the user came here for — the Dictations —
        // is never pushed off the bottom by what they have taught Cheppu.
        let words = NSStackView()
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        words.translatesAutoresizingMaskIntoConstraints = false
        for spelling in spellings.entries {
            words.addArrangedSubview(
                SpellingChip(spelling) { [weak self] in self?.forget(spelling) })
        }

        let scrolling = NSScrollView()
        scrolling.hasVerticalScroller = true
        scrolling.drawsBackground = false
        scrolling.documentView = words
        scrolling.translatesAutoresizingMaskIntoConstraints = false
        taught.addArrangedSubview(scrolling)

        NSLayoutConstraint.activate([
            words.leadingAnchor.constraint(equalTo: scrolling.contentView.leadingAnchor),
            words.topAnchor.constraint(equalTo: scrolling.contentView.topAnchor),
            words.widthAnchor.constraint(equalTo: scrolling.contentView.widthAnchor),
            scrolling.widthAnchor.constraint(
                equalTo: taught.widthAnchor, constant: -2 * Self.margin),
            scrolling.heightAnchor.constraint(
                equalTo: words.heightAnchor, multiplier: 1, constant: 0)
                .withPriority(.defaultHigh),
            scrolling.heightAnchor.constraint(lessThanOrEqualToConstant: Self.tallestTheyGet),
        ])

        // Said only while it is worth saying. With the part on the machine the
        // user is told nothing here: the Spellings above are already doing the
        // work, and a line explaining that they are is a window explaining
        // itself.
        guard row.isOn == nil else { return }

        let said = NSTextField(wrappingLabelWithString: row.explanation)
        said.textColor = .secondaryLabelColor
        said.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        said.translatesAutoresizingMaskIntoConstraints = false
        taught.addArrangedSubview(said)
        said.widthAnchor.constraint(equalTo: taught.widthAnchor, constant: -2 * Self.margin)
            .isActive = true

        guard let action = row.action else { return }
        let button = NSButton(title: action, target: self, action: #selector(fetchThePart))
        button.bezelStyle = .rounded
        button.controlSize = .small
        taught.addArrangedSubview(button)
    }

    private func empty(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func copy(_ entry: HistoryEntry) {
        // The whole of what was said, not the part of it the row had room for:
        // the user is copying this to put it back where it was meant to go.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.finalText.text, forType: .string)
    }

    /// Takes a Correction: the entry keeps what the user typed and the
    /// timestamp it already had, and what the change taught is kept beside it.
    ///
    /// Nothing is inserted and the clipboard is not touched — the words are
    /// already where they went — and a change that teaches nothing is silent,
    /// in the manner of a Discard (ADR-0014). The window is drawn again either
    /// way, because the Spellings section appears the moment the first one
    /// exists.
    private func correct(_ was: HistoryEntry, to now: FinalText) {
        let correction = Correction(of: was.finalText, to: now)
        guard correction.changes(was.finalText) else { return }

        Task {
            _ = try? await store.correct(was, to: correction.corrected)
            if !correction.spellings.isEmpty {
                _ = try? await spellings.keep(correction.spellings)
                spellingsMoved()
            }
            // Only the section above is drawn again. The row the user just left
            // already says what they typed, and rebuilding the list under them
            // would take the row they clicked into next out from under the
            // cursor — which is how somebody correcting two words in a row
            // would lose the second one.
            fillTheSpellings(await spellings.spellings(), says: await readTheSpellingsRow())
        }
    }

    /// Forgets one Spelling, which is what the user does about one they suspect
    /// of misfiring on a word they meant.
    private func forget(_ spelling: Spelling) {
        Task {
            _ = try? await spellings.forget(spelling)
            spellingsMoved()
            await fill()
        }
    }

    @objc private func fetchThePart() {
        fetchTheSpellingsPart()
        // Drawn again so the line under the button says the fetch has started.
        // Whoever is holding the Engine draws it again as the bytes arrive.
        Task { await fill() }
    }

    /// Empties the store, in the one action the button is.
    ///
    /// Nothing is asked first. Somebody reaching for this has had someone walk
    /// up behind them, and a dialog between them and an empty History is the
    /// difference between a promise kept and a promise explained
    /// (`docs/product-experience.md` §10).
    ///
    /// The Spellings are left where they are. They are what the user taught
    /// Cheppu rather than what they said, and they are useful after the
    /// Dictations they came from are gone; forgetting them is an action of its
    /// own, on the Settings row (ADR-0014).
    @objc private func clearEverything() {
        Task {
            try? await store.clear()
            await fill()
        }
    }
}

/// One Spelling, as the user sees it: the word, and a way of taking it back.
@MainActor
private final class SpellingChip: NSView {
    private let forgotten: () -> Void

    init(_ spelling: Spelling, forgotten: @escaping () -> Void) {
        self.forgotten = forgotten
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let word = NSTextField(labelWithString: spelling.text)
        word.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        word.translatesAutoresizingMaskIntoConstraints = false

        // One click, and nothing asked first, for the reason Clear History asks
        // nothing: the user is removing a word they can teach Cheppu again by
        // correcting one Dictation.
        let forget = NSButton(title: "✕", target: self, action: #selector(forgetThisOne))
        forget.bezelStyle = .inline
        forget.controlSize = .small
        forget.setAccessibilityLabel("Forget “\(spelling.text)”")
        forget.translatesAutoresizingMaskIntoConstraints = false

        addSubview(word)
        addSubview(forget)

        NSLayoutConstraint.activate([
            word.topAnchor.constraint(equalTo: topAnchor),
            word.bottomAnchor.constraint(equalTo: bottomAnchor),
            word.leadingAnchor.constraint(equalTo: leadingAnchor),

            forget.centerYAnchor.constraint(equalTo: word.centerYAnchor),
            forget.leadingAnchor.constraint(equalTo: word.trailingAnchor, constant: 2),
            forget.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpellingChip is built in code, not in a nib.")
    }

    @objc private func forgetThisOne() {
        forgotten()
    }
}

/// One Dictation, as a row: when it was said, what was said, a way of taking it
/// back, and a way of telling Cheppu it got a word wrong.
@MainActor
private final class HistoryRow: NSView, NSTextFieldDelegate {
    /// What the user did with the row.
    /// A Correction carries the entry as it was as well as what it says now,
    /// because the row goes on being editable afterwards: the second Correction
    /// of one row has to be read against the first rather than against what the
    /// Engine originally heard.
    enum WhatTheyDid {
        case copied(HistoryEntry)
        case corrected(was: HistoryEntry, to: FinalText)
    }

    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 6

    /// How much of a Dictation a row shows before it is cut off. Enough to know
    /// which one it is at a glance; Copy takes the whole of it however long it
    /// ran, and so does the field editor the moment the user clicks in.
    private static let linesShown = 4

    private let did: (WhatTheyDid) -> Void

    /// The Dictation this row is, as it stands. It moves when the user
    /// corrects it, so that clicking in and out again is not a Correction and a
    /// second Correction of the same row is read against the first.
    private var entry: HistoryEntry

    init(_ entry: HistoryEntry, did: @escaping (WhatTheyDid) -> Void) {
        self.did = did
        self.entry = entry
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
        // Edited in place, and committed by leaving the field. There is no Save
        // and no confirmation: the user is fixing a word, and a dialog between
        // them and the fix would be Cheppu asking whether they meant it
        // (ADR-0014).
        said.isEditable = true
        said.delegate = self
        said.focusRingType = .none
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
        did(.copied(entry))
    }

    /// Leaving the field commits the Correction.
    ///
    /// Leaving rather than typing: a Correction read off every keystroke would
    /// be a Spelling taught for every half-written word on the way to the one
    /// the user meant.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
            field.stringValue != entry.finalText.text
        else { return }

        let was = entry
        // The timestamp does not move: a Correction is the user telling Cheppu
        // it misheard them, not a new Dictation (ADR-0014).
        entry = HistoryEntry(
            finalText: FinalText(field.stringValue), recordedAt: was.recordedAt)
        did(.corrected(was: was, to: entry.finalText))
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

extension NSLayoutConstraint {
    /// The same constraint, willing to be broken.
    ///
    /// The Spellings scroll view asks to be exactly as tall as the words inside
    /// it and is capped above that, and a required constraint cannot be both.
    fileprivate func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
