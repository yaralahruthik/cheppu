import ApplicationServices
import CheppuCore
import CoreGraphics
import Foundation
import IOKit.hid

/// One thing the keyboard did, as little of it as the Hotkey needs to know.
enum KeyStroke: Equatable, Sendable {
    /// A modifier key went down or came up, leaving these held.
    case modifiersHeld(Set<Modifier>)

    /// A key that is not a modifier, not Escape, and not the one the Hotkey is
    /// built on, went down.
    ///
    /// Which key it was is deliberately not carried. All the Hotkey has to know
    /// is that the user was typing, and what they typed is none of Cheppu's
    /// business — the words it keeps are the ones it was asked to hear.
    case keyPressed

    /// The key the Hotkey's chord is built on went down.
    ///
    /// Told apart from the rest by the same reading that tells Escape apart,
    /// and told apart only while the user's own Hotkey has a key in it: on the
    /// default Hotkey there is no such key and this never happens (ADR-0011).
    case hotkeyKeyPressed

    /// That same key came back up, which is what ends a Hold on a chord.
    case hotkeyKeyReleased

    /// Escape went down.
    ///
    /// The one key Cheppu tells apart whatever the Hotkey is, because it is the
    /// one key that means something to a Dictation that is running.
    case escapePressed
}

/// The keyboard itself.
///
/// Narrow on purpose: start watching, stop watching. What counts as the Hotkey,
/// and whether what just happened was a tap of it, sits above this line and is
/// tested there.
protocol Keyboard: Sendable {
    /// Starts watching, reporting every stroke it is given — including the ones
    /// the user meant for another app, which is the whole point.
    ///
    /// Strokes arrive on the thread the system delivers events on, which cannot
    /// afford to wait, so the hand-over does not suspend.
    ///
    /// - Parameter key: the key the user's Hotkey is built on, where their
    ///   Hotkey is a chord. It is the whole of what the keyboard is told about
    ///   the Hotkey, and it is what lets the one key they chose be told apart
    ///   from the ones they type (ADR-0011). Nothing, where the Hotkey is a
    ///   bare modifier — and then no key is told apart at all.
    func watch(tellingApart key: Key?, _ struck: @escaping @Sendable (KeyStroke) -> Void) throws

    /// Stops watching.
    func stop()
}

/// Whether Cheppu may watch the keyboard while another app has focus.
protocol AccessibilityAccess: Sendable {
    /// Whether Accessibility access has been granted. Read afresh every time
    /// rather than remembered, so a grant taken away in System Settings is
    /// noticed rather than assumed.
    var isGranted: Bool { get }
}

/// Whether Cheppu may see the Globe key.
///
/// A second grant, asked about only by a Hotkey that uses that key. macOS does
/// not hand the Globe key to apps the way it hands over every other key, and
/// this is what it wants in exchange.
protocol InputMonitoringAccess: Sendable {
    var isGranted: Bool { get }

    /// Asks macOS for it, which prompts the first time and answers from the
    /// decision on record every time after.
    @discardableResult func request() -> Bool
}

/// The Mac's keyboard, by way of a `CGEvent` tap.
///
/// A session tap is handed the keys the user presses in whatever app has focus,
/// which is what lets the Hotkey work without clicking on Cheppu first, and is
/// the reason Accessibility is needed at all.
///
/// The tap is listen-only: it can read events and can neither change nor drop
/// one, so a keystroke meant for the app the user is typing in cannot be
/// swallowed by the app watching for the Hotkey. That is a property of how the
/// tap is made rather than a promise about what the callback does, and
/// `Scripts/check-the-hotkey-never-swallows-a-keystroke.sh` keeps it so.
///
/// The tap is only ever touched from `HotkeyWatch`, an actor, which is what
/// serializes it; the callback the system runs touches only the lock below.
final class SystemKeyboard: Keyboard, @unchecked Sendable {
    private let lock = NSLock()
    private var struck: (@Sendable (KeyStroke) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Where the one key the user chose sits on the keyboard, if their Hotkey
    /// has a key in it at all.
    private var hotkeyKey: Int64?

    /// Modifiers, and ordinary keys going down and coming back up.
    ///
    /// Key-up is asked for because a Hold on a chord ends when the key is let
    /// go of, and a Dictation that only stopped when the modifiers came up
    /// would run on past the words. A bare-modifier Hotkey needs none of it —
    /// its own release arrives as a change of flags — and pays nothing for it:
    /// a key-up that is not the Hotkey's is dropped where it arrives.
    private static let interesting: CGEventMask =
        (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        | (1 << CGEventType.keyUp.rawValue)

    /// Escape. Virtual key codes are positions on the keyboard rather than
    /// letters, and this is the position macOS calls `kVK_Escape`.
    private static let escape: Int64 = 53

    func watch(tellingApart key: Key?, _ struck: @escaping @Sendable (KeyStroke) -> Void) throws {
        // Nothing asks for this, but a tap left behind would be a second
        // watcher of every keystroke on the machine.
        stop()
        lock.withLock {
            self.struck = struck
            self.hotkeyKey = key.map { Int64($0.code) }
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: Self.interesting,
                callback: { _, type, event, watcher in
                    if let watcher {
                        Unmanaged<SystemKeyboard>.fromOpaque(watcher)
                            .takeUnretainedValue()
                            .saw(type, event)
                    }
                    // Handed straight back, untouched. A listen-only tap could
                    // not alter or drop it in any case; this is the same
                    // promise, made where someone reading the callback is.
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            lock.withLock { self.struck = nil }
            // A session tap for these event types is refused for one reason:
            // the process is not trusted. It is also the only reason the user
            // can do anything about, and they are told which one it is.
            throw HotkeyFailure.accessibilityDenied
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            // The port was made a moment ago, so there is no way for this to
            // fail that is not the tap itself being invalid — which is the same
            // thing to the user as never having been allowed to make one.
            CFMachPortInvalidate(tap)
            lock.withLock { self.struck = nil }
            throw HotkeyFailure.accessibilityDenied
        }

        // The main run loop, in the common modes, so the Hotkey keeps arriving
        // while a menu is open or a window is being dragged.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        lock.withLock {
            self.tap = tap
            self.source = source
        }
    }

    /// The tap is handed a pointer to this object that it does not retain, so
    /// the tap must not outlive it.
    deinit {
        stop()
    }

    func stop() {
        let (tap, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            defer {
                self.struck = nil
                self.hotkeyKey = nil
                self.tap = nil
                self.source = nil
            }
            return (self.tap, self.source)
        }
        guard let tap, let source else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFMachPortInvalidate(tap)
    }

    /// One event, as the system hands it over.
    private func saw(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .flagsChanged:
            report(.modifiersHeld(Modifier.held(inFlags: event.flags.rawValue)))

        case .keyDown, .keyUp:
            // The whole of what Cheppu asks of a key it was not sent, asked
            // once and in one place: which position on the keyboard was that?
            // The answer is compared against two keys and goes no further —
            // Escape, which Cancels a Dictation, and the one key the user chose
            // to dictate with. Every other key remains "the user typed
            // something" (ADR-0011).
            report(
                at: event.getIntegerValueField(.keyboardEventKeycode),
                wentDown: type == .keyDown
            )

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off if it ever takes too long, and leaves it
            // off. Switching it back on is the difference between a Hotkey that
            // had one slow moment and one that quietly stopped working for the
            // rest of the session.
            if let tap = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        default:
            break
        }
    }

    /// What a key at this position means to Cheppu, which is one of three
    /// things and usually the last of them.
    private func report(at position: Int64, wentDown: Bool) {
        if position == Self.escape {
            // Only on the way down. Escape coming back up says nothing a
            // Dictation could act on.
            if wentDown { report(.escapePressed) }
            return
        }

        if position == lock.withLock({ hotkeyKey }) {
            report(wentDown ? .hotkeyKeyPressed : .hotkeyKeyReleased)
            return
        }

        // A key the user typed. That it was pressed at all is the only thing
        // that leaves this line.
        if wentDown { report(.keyPressed) }
    }

    private func report(_ stroke: KeyStroke) {
        lock.withLock { struck }?(stroke)
    }
}

extension Modifier {
    /// The modifier keys an event says are held.
    ///
    /// The reading itself is the core's, because the window the user picks a
    /// Hotkey in asks macOS the same question of a different event type, and an
    /// app that decoded "which Option key was that?" twice would eventually
    /// decode it differently.
    static func held(in flags: CGEventFlags) -> Set<Modifier> {
        held(inFlags: flags.rawValue)
    }
}

/// Whether Cheppu may watch the keyboard, as macOS has already answered it.
///
/// Public for the same reason `MicrophonePermission` is: Settings says whether
/// the permission is there, and saying so must cost the user neither a prompt
/// nor a Dictation. Nothing is asked and nothing is prompted — there is no
/// prompt for this one in the first place.
public enum AccessibilityPermission {
    public static var isGranted: Bool {
        SystemAccessibilityAccess().isGranted
    }
}

/// Accessibility as macOS answers it.
struct SystemAccessibilityAccess: AccessibilityAccess {
    /// Reports the existing decision and never prompts.
    ///
    /// There is no prompt to show: unlike the Microphone, Accessibility cannot
    /// be granted from inside the app. It is a switch in System Settings, which
    /// is why asking for it is a sentence and a button rather than a call.
    var isGranted: Bool { AXIsProcessTrusted() }
}

/// Whether Cheppu may see the Globe key, as macOS has already answered it.
///
/// Only ever reached by a Hotkey that uses that key. Somebody dictating on the
/// right Option key is never asked about this and never sees it mentioned:
/// Cheppu asks for no permission the chosen Hotkey does not actually need.
public enum InputMonitoringPermission {
    public static var isGranted: Bool {
        SystemInputMonitoringAccess().isGranted
    }

    /// Asks for it, which is what puts the macOS prompt on screen the first
    /// time. Called at the moment the user picks the Globe key and at no other.
    @discardableResult
    public static func request() -> Bool {
        SystemInputMonitoringAccess().request()
    }
}

/// Input Monitoring as macOS answers it.
///
/// Unlike Accessibility, this one has a prompt of its own, and asking is how it
/// is shown. Answered afresh every time rather than remembered, so a grant
/// taken away in System Settings is noticed rather than assumed.
struct SystemInputMonitoringAccess: InputMonitoringAccess {
    var isGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
