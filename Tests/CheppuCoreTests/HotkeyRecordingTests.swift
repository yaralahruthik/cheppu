import Testing

@testable import CheppuCore

// Picking a Hotkey, one keystroke at a time. Every test here is somebody
// pressing the key they want to dictate with while Settings watches, and the
// question is only ever the same one: is that the key, or are they still on
// their way to it?
@Suite("Hotkey recording")
struct HotkeyRecordingTests {
    private static func recording() -> HotkeyRecording { HotkeyRecording() }

    @Test("A modifier pressed on its own and let go is a bare modifier")
    func aModifierPressedOnItsOwnAndLetGoIsABareModifier() {
        var recording = Self.recording()

        #expect(recording.sawModifiers([.rightOption]) == nil)
        // Taken on the way up rather than on the way down: a key that is still
        // held might yet be the first half of a chord, and picking it early
        // would make every chord impossible to type.
        #expect(recording.sawModifiers([]) == .bareModifier(.rightOption))
    }

    @Test("A key struck with something held is a chord")
    func aKeyStruckWithSomethingHeldIsAChord() {
        var recording = Self.recording()

        #expect(recording.sawModifiers([.leftControl]) == nil)
        #expect(recording.sawModifiers([.leftControl, .leftOption]) == nil)
        #expect(
            recording.sawKey(Key(named: "D")!)
                == .chord(Key(named: "D")!, with: [.leftControl, .leftOption])
        )
    }

    @Test("A key struck with nothing held is refused")
    func aKeyStruckWithNothingHeldIsRefused() {
        var recording = Self.recording()

        // A bare letter as the Hotkey would take every D the user types for the
        // rest of the day. There is no warning that makes that a choice worth
        // offering.
        #expect(recording.sawKey(Key(named: "D")!) == nil)
    }

    @Test("Two modifiers let go of together are not a Hotkey")
    func twoModifiersLetGoOfTogetherAreNotAHotkey() {
        var recording = Self.recording()

        // Cheppu watches one key held on its own, or a chord. Two modifiers and
        // nothing else is neither, and is far likelier to be a hand on its way
        // to a chord than a choice.
        #expect(recording.sawModifiers([.leftControl]) == nil)
        #expect(recording.sawModifiers([.leftControl, .leftOption]) == nil)
        #expect(recording.sawModifiers([.leftOption]) == nil)
        #expect(recording.sawModifiers([]) == nil)
    }

    @Test("The modifiers a chord is recorded with are the ones held at the moment it is struck")
    func theModifiersAChordIsRecordedWithAreTheOnesHeldWhenItIsStruck() {
        var recording = Self.recording()

        _ = recording.sawModifiers([.leftControl])
        _ = recording.sawModifiers([.leftControl, .leftOption])
        _ = recording.sawModifiers([.leftControl])

        // Option was pressed and let go of on the way — a hand settling, not a
        // choice. What is recorded is what was still down when the key landed.
        #expect(
            recording.sawKey(Key(named: "D")!) == .chord(Key(named: "D")!, with: [.leftControl])
        )
    }

    @Test("Letting go after a chord does not also record a bare modifier")
    func lettingGoAfterAChordDoesNotAlsoRecordABareModifier() {
        var recording = Self.recording()

        _ = recording.sawModifiers([.leftControl])
        #expect(recording.sawKey(Key(named: "D")!) != nil)

        // The hand leaves the keyboard after every chord. A recording that read
        // that as a second choice would overwrite the one just made.
        #expect(recording.sawModifiers([]) == nil)
    }

    @Test("The Globe key on its own can be chosen")
    func theGlobeKeyOnItsOwnCanBeChosen() {
        var recording = Self.recording()

        _ = recording.sawModifiers([.function])

        // It costs more than the others — a permission and a macOS setting —
        // and it is said at this moment rather than made impossible.
        #expect(recording.sawModifiers([]) == .bareModifier(.function))
    }
}
