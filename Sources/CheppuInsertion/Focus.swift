import AppKit
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
/// Asked on the main actor, because that is where AppKit keeps the answer up to
/// date — the workspace notices an app coming to the front on the main run loop
/// — and reading it from anywhere else is reading something while it is being
/// written.
struct SystemFocus: Focus {
    func focusedApp() async -> TargetApp? {
        await MainActor.run {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            return TargetApp(
                bundleIdentifier: app.bundleIdentifier,
                processIdentifier: app.processIdentifier
            )
        }
    }
}
