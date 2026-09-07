import CheppuCore
import CoreGraphics
import Testing

@testable import CheppuKeyboard

// Which keys an event says are held. The Hotkey may be one particular key, and
// this is where a Mac's answer to "which Option key was that?" is read —
// including the answers that would quietly stop the Hotkey working if they were
// read wrong.
@Suite("Modifier keys")
struct ModifierKeysTests {
    /// The device-dependent bits macOS sets alongside the flag for a modifier,
    /// saying which side of the keyboard it was pressed on.
    private enum Side {
        static let leftShift: UInt64 = 0x0000_0002
        static let leftCommand: UInt64 = 0x0000_0008
        static let leftOption: UInt64 = 0x0000_0020
        static let rightOption: UInt64 = 0x0000_0040
    }

    private static func held(_ flags: CGEventFlags, andSides sides: UInt64 = 0) -> Set<Modifier> {
        Modifier.held(inFlags: flags.rawValue | sides)
    }

    @Test("The right Option key is told apart from the left one")
    func theRightOptionKeyIsToldApartFromTheLeftOne() {
        #expect(Self.held(.maskAlternate, andSides: Side.rightOption) == [.rightOption])
        #expect(Self.held(.maskAlternate, andSides: Side.leftOption) == [.leftOption])
    }

    @Test("A keyboard with nothing held holds nothing")
    func aKeyboardWithNothingHeldHoldsNothing() {
        #expect(Self.held([]) == [])
    }

    @Test("Caps Lock left on does not stop the Hotkey being on its own")
    func capsLockLeftOnDoesNotStopTheHotkeyBeingOnItsOwn() {
        // Caps Lock is a lock rather than a key being held. Counting it would
        // leave the Hotkey never on its own for as long as it was on, and
        // Cheppu apparently broken for a reason no one would guess.
        let withCapsLockOn = Self.held([.maskAlternate, .maskAlphaShift], andSides: Side.rightOption)

        #expect(withCapsLockOn == [.rightOption])
    }

    @Test("Every key held is reported, so a chord can be told from the Hotkey")
    func everyKeyHeldIsReported() {
        let chord = Self.held(
            [.maskAlternate, .maskCommand, .maskShift],
            andSides: Side.rightOption | Side.leftCommand | Side.leftShift
        )

        #expect(chord == [.rightOption, .leftCommand, .leftShift])
    }

    @Test("The Fn key counts, so Fn and the Hotkey together is a chord")
    func theFnKeyCounts() {
        #expect(Self.held([.maskSecondaryFn]) == [.function])
    }

    @Test("A modifier with no side is never taken for the Hotkey")
    func aModifierWithNoSideIsNeverTakenForTheHotkey() {
        // A synthesised event usually says only "Option", without saying which
        // one. Cheppu takes it as the left key: an event it cannot attribute
        // can stop the Hotkey being on its own, but must never be the Hotkey.
        #expect(Self.held(.maskAlternate) == [.leftOption])
    }
}
