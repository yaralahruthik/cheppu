import AppKit

/// The window the Pill is drawn in.
///
/// Everything about it is arranged around one rule: it appears over the app the
/// user is working in without ever becoming part of it. A Dictation is
/// something that happens while someone types somewhere else, so a Pill that
/// took the keyboard — even for the instant it took to show itself — would put
/// the next word into Cheppu instead of into their email.
///
/// That is four separate things, and each of them is load-bearing:
/// `nonactivatingPanel` and a panel that refuses to become key mean showing it
/// activates neither Cheppu nor the window; `orderFrontRegardless` puts it on
/// screen without asking to be activated; and ignoring the mouse means a click
/// meant for what is underneath goes there rather than to a Pill that happened
/// to be over it.
final class PillPanel: NSPanel {
    /// Never, whatever it is asked. A borderless panel would otherwise become
    /// key the moment anything ordered it front.
    override var canBecomeKey: Bool { false }

    override var canBecomeMain: Bool { false }

    init(showing view: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: view.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        contentView = view

        // The capsule is drawn by the view, so the window behind it is nothing
        // but a shape to draw in.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Above the windows of every other app, including a full-screen one:
        // the whole point is to be readable without leaving what you are doing.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // A click belongs to whatever is underneath. The Pill is something to
        // glance at, never something to press.
        ignoresMouseEvents = true

        // Cheppu is never the active app, so a panel that hid itself when its
        // app was deactivated would be a Pill nobody ever saw.
        hidesOnDeactivate = false
        isMovableByWindowBackground = false

        // No fade in and none out. A Dictation's edges are the moments the user
        // is reading, and half a Pill fading through them says neither thing.
        animationBehavior = .none
    }

    /// Puts the Pill on screen without activating Cheppu or taking the
    /// keyboard from the app the user is typing in.
    func show() {
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
