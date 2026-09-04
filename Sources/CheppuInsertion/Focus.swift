import AppKit
import ApplicationServices
import CheppuCore

/// Where the keyboard is pointing.
protocol Focus: Sendable {
    /// The app a keystroke typed this instant would go to, or nothing if none
    /// would take it.
    func focusedApp() async -> TargetApp?
}

/// Keyboard focus as macOS answers it.
///
/// The frontmost app is the one a synthesised keystroke reaches, which is what
/// makes it the right question: this is the app that would receive the paste,
/// asked in the same terms as the paste is sent.
///
/// Two things are read, in this order, and the order is the whole of what
/// happens when the user moves between them. The app is read first, on the main
/// actor, because that is where AppKit keeps the answer up to date — the
/// workspace notices an app coming to the front on the main run loop — and
/// reading it from anywhere else is reading something while it is being written.
/// The focused element is read second, and off the main actor, because that
/// question is answered by the app that has focus and an app that is busy can
/// take its time over it.
///
/// A user who switches apps between the two readings therefore gets the old
/// app's identity with the new app's focused element, and that is the way round
/// it has to be: the mismatch lands on the side of calling something a Terminal,
/// and the Insertion that follows compares the process again before it types, so
/// a reading that straddles a switch is abandoned rather than pasted.
struct SystemFocus: Focus {
    /// How long an app has to answer what the keyboard is pointing at inside it.
    ///
    /// The accessibility API waits six seconds by default for an app that does
    /// not reply, which on the path between the user finishing speaking and
    /// their words appearing is not a delay but a hang
    /// (`docs/product-experience.md` §7). A fifth of a second is far longer than
    /// a healthy app takes and short enough to be a breath.
    ///
    /// Giving up is safe rather than merely fast: an app that did not answer is
    /// an app Cheppu does not know the focused element of, which
    /// `TargetApp.isATerminal` reads as a Terminal.
    private static let whileTheAppAnswers: Float = 0.2

    func focusedApp() async -> TargetApp? {
        guard let app = await frontmostApp() else { return nil }
        return TargetApp(
            bundleIdentifier: app.bundleIdentifier,
            processIdentifier: app.processIdentifier,
            focusedElementRole: focusedElementRole()
        )
    }

    /// The app in front, reduced on the main actor to the two facts about it
    /// that leave it.
    ///
    /// `NSRunningApplication` does not cross actors, and nothing outside this
    /// wants it to: what a reading of focus is made of is an identity, not a
    /// live handle onto somebody else's process.
    private func frontmostApp() async -> (bundleIdentifier: String?, processIdentifier: Int32)? {
        await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return (app.bundleIdentifier, app.processIdentifier)
        }
    }

    /// The accessibility role of whatever has keyboard focus, machine-wide.
    ///
    /// Read from the system-wide element rather than from the frontmost app's,
    /// so that the answer is about the thing that would receive a keystroke
    /// rather than about a window that happens to be in front.
    ///
    /// It only ever asks for the element's role. Cheppu does not read its value,
    /// which is the text the user has already typed: the question is what kind
    /// of place this is, and reading the user's document in order to insert into
    /// it is exactly what `docs/product-experience.md` §1 rules out. Nothing
    /// here can change anything either — the accessibility API is asked and
    /// never told.
    ///
    /// Every way of not getting an answer is the same answer: nothing.
    /// Accessibility not granted, an app that exposes no focused element, and an
    /// app too busy to reply before `whileTheAppAnswers` is up are
    /// indistinguishable from out here, and all three mean Cheppu does not know
    /// what the keyboard is pointing at.
    private func focusedElementRole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.whileTheAppAnswers)

        var focused: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focused
            ) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        // Checked by its type identifier just above rather than by the cast: a
        // conditional cast to a Core Foundation type always succeeds, so it
        // would say nothing about what came back.
        let element = unsafeDowncast(focused, to: AXUIElement.self)

        var role: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
        else { return nil }
        return role as? String
    }
}
