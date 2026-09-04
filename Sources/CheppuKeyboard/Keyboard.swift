import ApplicationServices
import CheppuCore
import CoreGraphics
import Foundation

/// The modifier keys, told left from right.
///
/// The two sides are separate keys here because the default Hotkey is one of
/// them and not the other. A Mac calls both of them Option, and Cheppu must not
/// start a Dictation on the one people type accented characters with.
///
/// Caps Lock is deliberately absent. It is a lock rather than a key being held,
/// so counting it would leave the Hotkey never on its own for as long as it was
/// on — an app that stopped working and never said why.
struct ModifierKeys: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let leftControl = ModifierKeys(rawValue: 1 << 0)
    static let rightControl = ModifierKeys(rawValue: 1 << 1)
    static let leftShift = ModifierKeys(rawValue: 1 << 2)
    static let rightShift = ModifierKeys(rawValue: 1 << 3)
    static let leftCommand = ModifierKeys(rawValue: 1 << 4)
    static let rightCommand = ModifierKeys(rawValue: 1 << 5)
    static let leftOption = ModifierKeys(rawValue: 1 << 6)
    static let rightOption = ModifierKeys(rawValue: 1 << 7)
    static let function = ModifierKeys(rawValue: 1 << 8)
}

/// One thing the keyboard did, as little of it as the Hotkey needs to know.
enum KeyStroke: Equatable, Sendable {
    /// A modifier key went down or came up, leaving these held.
    case modifiersHeld(ModifierKeys)

    /// A key that is not a modifier, and not Escape, went down.
    ///
    /// Which key it was is deliberately not carried. All the Hotkey has to know
    /// is that the user was typing, and what they typed is none of Cheppu's
    /// business — the words it keeps are the ones it was asked to hear.
    case keyPressed

    /// Escape went down.
    ///
    /// The one key Cheppu tells apart from the rest, because it is the one key
    /// that means something to a Dictation that is running. It is told apart
    /// and then let go of: the key code is read to answer "was that Escape?"
    /// and is never carried any further.
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
    func watch(_ struck: @escaping @Sendable (KeyStroke) -> Void) throws

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

    /// Modifiers and ordinary keys going down. Key-up is not asked for: the
    /// Hotkey is a modifier, so its own release arrives as a change of flags,
    /// and the only thing another key has to tell Cheppu is that it was pressed.
    private static let interesting: CGEventMask =
        (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

    /// Escape. Virtual key codes are positions on the keyboard rather than
    /// letters, and this is the position macOS calls `kVK_Escape`.
    private static let escape: Int64 = 53

    func watch(_ struck: @escaping @Sendable (KeyStroke) -> Void) throws {
        // Nothing asks for this, but a tap left behind would be a second
        // watcher of every keystroke on the machine.
        stop()
        lock.withLock { self.struck = struck }

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
            // A session tap for two event types is refused for one reason: the
            // process is not trusted. It is also the only reason the user can
            // do anything about, and they are told which one it is.
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
            report(.modifiersHeld(ModifierKeys(event.flags)))

        case .keyDown:
            // The only question asked of a key Cheppu was not sent: was that
            // Escape? The answer decides whether a Dictation is Cancelled, and
            // the key code goes no further than this line.
            let isEscape = event.getIntegerValueField(.keyboardEventKeycode) == Self.escape
            report(isEscape ? .escapePressed : .keyPressed)

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

    private func report(_ stroke: KeyStroke) {
        lock.withLock { struck }?(stroke)
    }
}

extension ModifierKeys {
    /// The modifier keys an event says are held.
    ///
    /// Which side a modifier is on lives in the device-dependent bits, and
    /// nowhere else: `CGEventFlags` has one flag for Option and does not say
    /// which of the two keys it came from. A modifier that arrives with no side
    /// at all — which is what a synthesised event usually looks like — is taken
    /// as the left one, so an event Cheppu cannot attribute can stop the Hotkey
    /// being on its own but can never be the Hotkey.
    init(_ flags: CGEventFlags) {
        var held: ModifierKeys = []

        for (modifier, left, right) in Self.sides where flags.contains(modifier) {
            if flags.rawValue & right.bit != 0 {
                held.insert(right.key)
            }
            if flags.rawValue & left.bit != 0 || flags.rawValue & right.bit == 0 {
                held.insert(left.key)
            }
        }
        if flags.contains(.maskSecondaryFn) {
            held.insert(.function)
        }

        self = held
    }

    /// Each modifier, and the bit that says which side of the keyboard it was
    /// pressed on. The values are the `NX_DEVICE…KEYMASK` constants; Caps Lock
    /// has no entry because it is not a key anyone holds.
    private static let sides:
        [(
            modifier: CGEventFlags,
            left: (bit: UInt64, key: ModifierKeys),
            right: (bit: UInt64, key: ModifierKeys)
        )] = [
            (.maskControl, (0x0000_0001, .leftControl), (0x0000_2000, .rightControl)),
            (.maskShift, (0x0000_0002, .leftShift), (0x0000_0004, .rightShift)),
            (.maskCommand, (0x0000_0008, .leftCommand), (0x0000_0010, .rightCommand)),
            (.maskAlternate, (0x0000_0020, .leftOption), (0x0000_0040, .rightOption)),
        ]
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
