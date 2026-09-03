import CheppuCore
import Testing

@testable import CheppuKeyboard

// What counts as a tap of the Hotkey. Every one of these is a claim about a user
// at a keyboard: this is someone reaching for Cheppu, and that is someone typing
// in another app who must not be interrupted by it.
@Suite("Hotkey gesture")
struct HotkeyGestureTests {
    private static let hotkeyDown = KeyStroke.modifiersHeld([.rightOption])
    private static let everythingUp = KeyStroke.modifiersHeld([])

    /// Every Activation a run of keystrokes completed.
    private static func activations(from strokes: [KeyStroke]) -> [HotkeyEvent] {
        var gesture = HotkeyGesture()
        return strokes.compactMap { gesture.seeing($0) }
    }

    @Test("The Hotkey is the right Option key on its own")
    func theHotkeyIsTheRightOptionKeyOnItsOwn() {
        // The default, because it does nothing on its own in any app: turning
        // Cheppu on takes no shortcut away from anyone.
        #expect(HotkeyGesture.hotkey == [.rightOption])
    }

    @Test("A tap of the Hotkey is an Activation")
    func aTapOfTheHotkeyIsAnActivation() {
        #expect(Self.activations(from: [Self.hotkeyDown, Self.everythingUp]) == [.tapped])
    }

    @Test("A second tap is a second Activation")
    func aSecondTapIsASecondActivation() {
        // Which of the two starts a Dictation and which stops it is the
        // machine's to answer. All the keyboard reports is that it happened
        // again.
        let taps = [Self.hotkeyDown, Self.everythingUp, Self.hotkeyDown, Self.everythingUp]

        #expect(Self.activations(from: taps) == [.tapped, .tapped])
    }

    @Test("Holding the Hotkey down is not yet an Activation")
    func holdingTheHotkeyDownIsNotYetAnActivation() {
        // Right Option is a live modifier — held with a letter it types an
        // accented character — so the question of whether this is a Dictation
        // or a keystroke is not settled until the key comes back up.
        #expect(Self.activations(from: [Self.hotkeyDown]).isEmpty)
    }

    @Test("The left Option key is not the Hotkey")
    func theLeftOptionKeyIsNotTheHotkey() {
        let strokes: [KeyStroke] = [.modifiersHeld([.leftOption]), Self.everythingUp]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("The Hotkey pressed as part of a chord is a chord")
    func theHotkeyPressedAsPartOfAChordIsAChord() {
        // Command was already down. This is someone reaching for a shortcut in
        // the app they are working in, and Cheppu is not in it.
        let strokes: [KeyStroke] = [
            .modifiersHeld([.leftCommand]),
            .modifiersHeld([.leftCommand, .rightOption]),
            .modifiersHeld([.leftCommand]),
            Self.everythingUp,
        ]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("Letting go of the other key first does not turn a chord into an Activation")
    func lettingGoOfTheOtherKeyFirstDoesNotTurnAChordIntoAnActivation() {
        // The Hotkey is left held for a moment after the chord is over, which
        // is how anyone's fingers actually leave a keyboard. The press was
        // spoiled when Command joined it and stays spoiled.
        let strokes: [KeyStroke] = [
            .modifiersHeld([.leftCommand]),
            .modifiersHeld([.leftCommand, .rightOption]),
            .modifiersHeld([.rightOption]),
            Self.everythingUp,
        ]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("A modifier joining the Hotkey while it is held spoils the press")
    func aModifierJoiningTheHotkeyWhileItIsHeldSpoilsThePress() {
        let strokes: [KeyStroke] = [
            Self.hotkeyDown,
            .modifiersHeld([.rightOption, .leftShift]),
            .modifiersHeld([.rightOption]),
            Self.everythingUp,
        ]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("Typing with the Hotkey held is typing, not an Activation")
    func typingWithTheHotkeyHeldIsTypingNotAnActivation() {
        // Right Option and a letter is a dead key on several layouts. Someone
        // typing an accented character has not asked to dictate.
        let strokes: [KeyStroke] = [Self.hotkeyDown, .keyPressed, Self.everythingUp]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("Ordinary typing is never an Activation")
    func ordinaryTypingIsNeverAnActivation() {
        let strokes: [KeyStroke] = [
            .keyPressed,
            .modifiersHeld([.leftShift]),
            .keyPressed,
            Self.everythingUp,
            .keyPressed,
        ]

        #expect(Self.activations(from: strokes).isEmpty)
    }

    @Test("A spoiled press does not spoil the tap that follows it")
    func aSpoiledPressDoesNotSpoilTheTapThatFollowsIt() {
        let strokes: [KeyStroke] = [
            Self.hotkeyDown,
            .keyPressed,
            Self.everythingUp,
            Self.hotkeyDown,
            Self.everythingUp,
        ]

        #expect(Self.activations(from: strokes) == [.tapped])
    }
}
