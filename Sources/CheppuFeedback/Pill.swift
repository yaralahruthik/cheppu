import AppKit
import CheppuCore

/// The Pill: a panel that appears for the length of a Dictation and gets out of
/// the way afterwards.
///
/// It is placed once, as it appears, and never moved while it is up. Where it
/// goes is `PillPlacement`'s; this is what asks the questions that placement
/// needs answering — which screen, and where the user is typing — and what
/// keeps the panel and the level in step with the states the core sends.
@MainActor
final class Pill {
    private let view = PillView()
    private let panel: PillPanel
    private let field = FocusedField()

    /// Whether this Pill is up for a Dictation. What it is for is the moment
    /// between: the level arrives many times a second, and every one of those
    /// after the first must redraw the Pill rather than place it again.
    private var isShowing = false

    /// Which Dictation the Pill that is up belongs to.
    ///
    /// Counted rather than left to the flag above, because placing the Pill
    /// means asking another app a question and waiting for its answer. An
    /// answer that arrives after the Dictation it was asked for has ended would
    /// otherwise place the next Dictation's Pill where the last one was typing.
    private var dictations = 0

    init() {
        self.panel = PillPanel(showing: view)
    }

    /// Shows a state of a Dictation, putting the Pill on screen if this is the
    /// first of them.
    ///
    /// It returns before the Pill is on screen, which is the whole reason the
    /// putting-there is a `Task`. Showing it means asking the app the user is
    /// typing in where its text is, and that app is free to take a tenth of a
    /// second to answer; a Dictation that waited for it would be one whose
    /// first levels arrived in a burst after the answer rather than as they
    /// were heard.
    func show(_ state: PillState) {
        view.show(state)
        guard !isShowing else { return }
        isShowing = true
        dictations += 1

        let thisDictation = dictations
        Task { [weak self] in
            guard let self else { return }
            let keepClearOf = await field.whatToKeepClearOf()

            // The Dictation ended while its app was being asked — a tap so
            // short it was over inside a tenth of a second, or one the user
            // cancelled at once. Showing the Pill now would leave one on screen
            // that nothing is left to take down.
            guard isShowing, dictations == thisDictation else { return }

            panel.setFrame(placement(keepingClearOf: keepClearOf), display: false)
            panel.show()
        }
    }

    /// Takes the Pill down. The Final Text appearing is what says the Dictation
    /// worked (`docs/product-experience.md` §3), so the Pill's last job is to
    /// be gone by the time it does.
    func hide() {
        isShowing = false
        panel.hide()
        view.rest()
    }

    /// Where this Pill goes, on the screen it belongs on.
    ///
    /// The screen with the field on it, because that is the screen the user is
    /// looking at. Failing that the one macOS calls main — for an app with no
    /// window of its own that is the screen the keyboard is working on, which
    /// is the same answer by a longer route.
    private func placement(keepingClearOf keepClearOf: [NSRect]) -> NSRect {
        let screen =
            keepClearOf.first.flatMap { field in
                NSScreen.screens.first { $0.frame.intersects(field) }
            }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        return PillPlacement.place(
            on: screen?.visibleFrame ?? .zero,
            keepingClearOf: keepClearOf
        )
    }
}
