import CheppuCore
import Testing

@testable import CheppuKeyboard

// What the Hotkey does at the keyboard. Every one of these is a claim about a
// user at a keyboard: this is someone reaching for Cheppu, and that is someone
// typing in another app who must not be interrupted by it.
@Suite("Hotkey gesture")
struct HotkeyGestureTests {
    private static let hotkeyDown = KeyStroke.modifiersHeld([.rightOption])
    private static let everythingUp = KeyStroke.modifiersHeld([])

    /// Everything a run of keystrokes reported.
    private static func reported(from strokes: [KeyStroke]) -> [HotkeyEvent] {
        var gesture = HotkeyGesture()
        return strokes.compactMap { gesture.seeing($0) }
    }

    @Test("The Hotkey is the right Option key on its own")
    func theHotkeyIsTheRightOptionKeyOnItsOwn() {
        // The default, because it does nothing on its own in any app: turning
        // Cheppu on takes no shortcut away from anyone.
        #expect(HotkeyGesture.hotkey == [.rightOption])
    }

    @Test("The Hotkey going down is reported as it goes down, not when it comes back up")
    func theHotkeyGoingDownIsReportedAsItGoesDown() {
        // Which is what lets a Dictation start on key-down, so that the quarter
        // of a second spent telling a tap from a Hold is not a quarter of a
        // second of the user's voice.
        #expect(Self.reported(from: [Self.hotkeyDown]) == [.pressed])
    }

    @Test("A tap of the Hotkey is a press and a release")
    func aTapOfTheHotkeyIsAPressAndARelease() {
        // How long it was held is not the keyboard's to interpret. It reports
        // both ends of the press and the core times it.
        #expect(Self.reported(from: [Self.hotkeyDown, Self.everythingUp]) == [.pressed, .released])
    }

    @Test("A second tap is reported the same way as the first")
    func aSecondTapIsReportedTheSameWayAsTheFirst() {
        let taps = [Self.hotkeyDown, Self.everythingUp, Self.hotkeyDown, Self.everythingUp]

        #expect(Self.reported(from: taps) == [.pressed, .released, .pressed, .released])
    }

    @Test("The left Option key is not the Hotkey")
    func theLeftOptionKeyIsNotTheHotkey() {
        let strokes: [KeyStroke] = [.modifiersHeld([.leftOption]), Self.everythingUp]

        #expect(Self.reported(from: strokes).isEmpty)
    }

    @Test("The Hotkey pressed as part of a chord is a chord")
    func theHotkeyPressedAsPartOfAChordIsAChord() {
        // Command was already down. This is someone reaching for a shortcut in
        // the app they are working in, and Cheppu is not in it — so nothing is
        // reported, and no Dictation is started for one to be taken back.
        let strokes: [KeyStroke] = [
            .modifiersHeld([.leftCommand]),
            .modifiersHeld([.leftCommand, .rightOption]),
            .modifiersHeld([.leftCommand]),
            Self.everythingUp,
        ]

        #expect(Self.reported(from: strokes).isEmpty)
    }

    @Test("Letting go of the other key first does not turn a chord into a press")
    func lettingGoOfTheOtherKeyFirstDoesNotTurnAChordIntoAPress() {
        // The Hotkey is left held for a moment after the chord is over, which
        // is how anyone's fingers actually leave a keyboard. The press was
        // never Cheppu's and does not become Cheppu's on the way up.
        let strokes: [KeyStroke] = [
            .modifiersHeld([.leftCommand]),
            .modifiersHeld([.leftCommand, .rightOption]),
            .modifiersHeld([.rightOption]),
            Self.everythingUp,
        ]

        #expect(Self.reported(from: strokes).isEmpty)
    }

    @Test("A modifier joining the Hotkey while it is held spoils the press")
    func aModifierJoiningTheHotkeyWhileItIsHeldSpoilsThePress() {
        let strokes: [KeyStroke] = [
            Self.hotkeyDown,
            .modifiersHeld([.rightOption, .leftShift]),
            .modifiersHeld([.rightOption]),
            Self.everythingUp,
        ]

        // The press is reported, because at the moment the key went down it was
        // on its own. What the user did next is what takes it back, and it is
        // taken back at that moment rather than when their hand finally leaves
        // the keyboard.
        #expect(Self.reported(from: strokes) == [.pressed, .pressSpoiled])
    }

    @Test("Typing with the Hotkey held is typing, and the press is taken back")
    func typingWithTheHotkeyHeldIsTypingAndThePressIsTakenBack() {
        // Right Option and a letter is a dead key on several layouts. Someone
        // typing an accented character has not asked to dictate, and the
        // Dictation their key-down started is handed back the moment they type.
        let strokes: [KeyStroke] = [Self.hotkeyDown, .keyPressed, Self.everythingUp]

        #expect(Self.reported(from: strokes) == [.pressed, .pressSpoiled])
    }

    @Test("A press is only spoiled once, however much is typed with it")
    func aPressIsOnlySpoiledOnceHoweverMuchIsTypedWithIt() {
        let strokes: [KeyStroke] = [
            Self.hotkeyDown,
            .keyPressed,
            .keyPressed,
            .modifiersHeld([.rightOption, .leftShift]),
            Self.everythingUp,
        ]

        #expect(Self.reported(from: strokes) == [.pressed, .pressSpoiled])
    }

    @Test("Ordinary typing is never reported")
    func ordinaryTypingIsNeverReported() {
        let strokes: [KeyStroke] = [
            .keyPressed,
            .modifiersHeld([.leftShift]),
            .keyPressed,
            Self.everythingUp,
            .keyPressed,
        ]

        #expect(Self.reported(from: strokes).isEmpty)
    }

    @Test("A spoiled press does not spoil the press that follows it")
    func aSpoiledPressDoesNotSpoilThePressThatFollowsIt() {
        let strokes: [KeyStroke] = [
            Self.hotkeyDown,
            .keyPressed,
            Self.everythingUp,
            Self.hotkeyDown,
            Self.everythingUp,
        ]

        #expect(Self.reported(from: strokes) == [.pressed, .pressSpoiled, .pressed, .released])
    }

    // MARK: - Escape

    @Test("Escape is reported wherever it is pressed")
    func escapeIsReportedWhereverItIsPressed() {
        // Whether it means anything is not the keyboard's to decide: Escape is
        // Cancel while a Dictation is Listening and the user's own business at
        // every other moment, and only the machine knows which of those this
        // is.
        #expect(Self.reported(from: [.escapePressed]) == [.escapePressed])
    }

    @Test("Escape during a Hold Cancels the Dictation rather than spoiling the press")
    func escapeDuringAHoldCancelsTheDictationRatherThanSpoilingThePress() {
        let strokes: [KeyStroke] = [Self.hotkeyDown, .escapePressed, Self.everythingUp]

        // Someone holding the Hotkey and reaching for Escape is throwing the
        // Dictation away, not typing. Reported as a spoiled press it would be a
        // key brushed during a Hold, and what they said would be transcribed
        // and inserted — the one thing they asked for it not to be.
        #expect(Self.reported(from: strokes) == [.pressed, .escapePressed, .released])
    }

    @Test("Escape is still Escape when it is pressed with something held")
    func escapeIsStillEscapeWhenItIsPressedWithSomethingHeld() {
        let strokes: [KeyStroke] = [.modifiersHeld([.leftShift]), .escapePressed]

        #expect(Self.reported(from: strokes) == [.escapePressed])
    }
}
