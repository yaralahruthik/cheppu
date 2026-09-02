import AppKit
import CheppuCore

/// Cheppu's entry point.
///
/// Cheppu is an accessory app: it lives in the menu bar, with no Dock icon and
/// no main window. `NSApplication.ActivationPolicy.accessory` is what makes that
/// true when the executable is run directly; the `LSUIElement` key in the app
/// bundle's `Info.plist` makes it true before the process starts.
@main
enum CheppuApp {
    /// `NSApplication.delegate` does not retain its delegate, so the app owns it
    /// here. Without this the status item goes away as soon as launch finishes.
    @MainActor private static let menuBarController = MenuBarController()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.delegate = menuBarController
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
