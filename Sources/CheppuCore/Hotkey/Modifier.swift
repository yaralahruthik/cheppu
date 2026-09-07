/// One modifier key on the keyboard, told left from right.
///
/// The two sides are separate keys because the Hotkey may be one of them and
/// not the other: a Mac calls both of them Option, and Cheppu must not start a
/// Dictation on the one people type accented characters with.
///
/// Caps Lock is deliberately absent. It is a lock rather than a key being held,
/// so counting it would leave a bare-modifier Hotkey never on its own for as
/// long as it was on — an app that stopped working and never said why.
public enum Modifier: String, CaseIterable, Equatable, Hashable, Sendable {
    case function
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftShift
    case rightShift
    case leftCommand
    case rightCommand

    /// The key's name in words, for the one place a Hotkey is a bare modifier
    /// and there is no chord to read.
    ///
    /// "Globe" rather than "Function": it is the name printed on the key on
    /// every Mac that has one, and "Function" is the name on none of them.
    public var name: String {
        switch self {
        case .function: "Globe"
        case .leftControl: "Left Control"
        case .rightControl: "Right Control"
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        }
    }

    /// The symbol macOS prints for the key in every menu on the machine.
    ///
    /// It says nothing about which side the key is on, because macOS itself
    /// does not: ⌘ is ⌘ whichever hand pressed it. That is what makes the
    /// symbols the right thing to match a system shortcut on.
    public var symbol: String {
        switch self {
        case .function: "🌐"
        case .leftControl, .rightControl: "⌃"
        case .leftOption, .rightOption: "⌥"
        case .leftShift, .rightShift: "⇧"
        case .leftCommand, .rightCommand: "⌘"
        }
    }

    /// The modifiers a set of macOS event flags says are held.
    ///
    /// Which side a modifier is on lives in the device-dependent bits, and
    /// nowhere else: the flags have one bit for Option and do not say which of
    /// the two keys it came from. A modifier that arrives with no side at all —
    /// which is what a synthesised event usually looks like — is taken as the
    /// left one, so an event Cheppu cannot attribute can stop a bare-modifier
    /// Hotkey being on its own but can never be the Hotkey.
    ///
    /// It takes the raw bits rather than a framework's flag type because both
    /// keyboards Cheppu reads answer this question — the event tap that watches
    /// for the Hotkey, and the window the user picks one in — and an app that
    /// decoded them twice would eventually decode them differently. The core
    /// has no framework to name them with, so the constants are written out.
    public static func held(inFlags flags: UInt64) -> Set<Modifier> {
        var held: Set<Modifier> = []

        for (mask, left, right) in sides where flags & mask != 0 {
            if flags & right.bit != 0 { held.insert(right.key) }
            if flags & left.bit != 0 || flags & right.bit == 0 { held.insert(left.key) }
        }
        if flags & secondaryFn != 0 { held.insert(.function) }

        return held
    }

    /// Each modifier, and the bits that say it is held and which side of the
    /// keyboard it was pressed on.
    ///
    /// The first of each row is the `NSEvent.ModifierFlags` / `CGEventFlags`
    /// bit; the others are the `NX_DEVICE…KEYMASK` constants. Caps Lock has no
    /// row because it is not a key anyone holds.
    private static let sides:
        [(mask: UInt64, left: (bit: UInt64, key: Modifier), right: (bit: UInt64, key: Modifier))] =
            [
                (1 << 18, (0x0000_0001, .leftControl), (0x0000_2000, .rightControl)),
                (1 << 17, (0x0000_0002, .leftShift), (0x0000_0004, .rightShift)),
                (1 << 20, (0x0000_0008, .leftCommand), (0x0000_0010, .rightCommand)),
                (1 << 19, (0x0000_0020, .leftOption), (0x0000_0040, .rightOption)),
            ]

    /// The Globe key. It has no side to be on.
    private static let secondaryFn: UInt64 = 1 << 23
}
