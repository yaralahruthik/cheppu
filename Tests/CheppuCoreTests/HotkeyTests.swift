import Testing

@testable import CheppuCore

// What a Hotkey is, what it is called on the screen the user picks it on, and
// what picking it costs them. Every claim here is about someone at a keyboard
// choosing the key they will press a hundred times a day.
@Suite("Hotkey")
struct HotkeyTests {
    // MARK: - What it is

    @Test("A fresh install dictates on the right Option key, on its own")
    func aFreshInstallDictatesOnTheRightOptionKey() {
        // It does nothing on its own in any app, so turning Cheppu on takes no
        // shortcut away from anyone, and it needs no permission beyond the one
        // watching the keyboard already needs
        // (`docs/product-experience.md` §6).
        #expect(Hotkey.byDefault == .bareModifier(.rightOption))
        #expect(Hotkey.byDefault.needsInputMonitoring == false)
        #expect(Hotkey.byDefault.warnings.isEmpty)
    }

    @Test("A bare modifier is one key held on its own")
    func aBareModifierIsOneKeyHeldOnItsOwn() {
        let hotkey = Hotkey.bareModifier(.leftControl)

        #expect(hotkey.modifiers == [.leftControl])
        #expect(hotkey.key == nil)
    }

    @Test("A chord is a key and everything held with it")
    func aChordIsAKeyAndEverythingHeldWithIt() {
        let hotkey = Hotkey.chord(Key(named: "D")!, with: [.leftControl, .leftOption])

        #expect(hotkey.modifiers == [.leftControl, .leftOption])
        #expect(hotkey.key == Key(named: "D"))
    }

    // MARK: - What it is called

    @Test("A bare modifier is named in words, because there is no chord to read")
    func aBareModifierIsNamedInWords() {
        #expect(Hotkey.bareModifier(.rightOption).name == "Right Option")
        #expect(Hotkey.bareModifier(.leftCommand).name == "Left Command")
        // The Globe key is the name on the key itself on every Mac that has
        // one, and "Function" is the name on none of them.
        #expect(Hotkey.bareModifier(.function).name == "Globe")
    }

    @Test("A chord is named the way the rest of the machine names one")
    func aChordIsNamedTheWayTheRestOfTheMachineNamesOne() {
        // Symbols in the order every menu on macOS prints them, so that the
        // Hotkey reads like the shortcuts beside it rather than like a setting.
        #expect(
            Hotkey.chord(Key(named: "D")!, with: [.leftControl, .leftOption]).name == "⌃⌥D"
        )
        #expect(
            Hotkey.chord(Key(named: "Space")!, with: [.rightShift, .leftCommand]).name == "⇧⌘Space"
        )
        #expect(Hotkey.chord(Key(named: "F5")!, with: [.function]).name == "🌐F5")
    }

    // MARK: - What it costs

    @Test("Only the Globe key needs Input Monitoring")
    func onlyTheGlobeKeyNeedsInputMonitoring() {
        // Cheppu asks for no permission the chosen Hotkey does not need. Every
        // other key on the keyboard arrives on the grant watching the keyboard
        // already has.
        #expect(Hotkey.bareModifier(.function).needsInputMonitoring)
        #expect(Hotkey.chord(Key(named: "F5")!, with: [.function]).needsInputMonitoring)

        for modifier in Modifier.allCases where modifier != .function {
            #expect(Hotkey.bareModifier(modifier).needsInputMonitoring == false)
        }
    }

    @Test("Choosing the Globe key says what it needs, at the moment it is chosen")
    func choosingTheGlobeKeySaysWhatItNeeds() {
        // Two things, and both of them or the key does nothing at all: the
        // permission, and the macOS setting that would otherwise eat the press
        // before Cheppu ever sees it.
        #expect(Hotkey.bareModifier(.function).warnings == [.globeKey])

        let globe = HotkeyWarning.globeKey
        #expect(globe.explanation.contains("Input Monitoring"))
        #expect(globe.explanation.contains("Do Nothing"))
    }

    @Test("Choosing a common system shortcut says what it would take away")
    func choosingACommonSystemShortcutSaysWhatItWouldTakeAway() {
        // Naming the thing is the whole point. "This is a system shortcut" is a
        // warning the user cannot act on; "this is how you open Spotlight" is
        // one they can.
        let spotlight = Hotkey.chord(Key(named: "Space")!, with: [.leftCommand])

        #expect(spotlight.warnings == [.systemShortcut("open Spotlight")])
        #expect(HotkeyWarning.systemShortcut("open Spotlight").explanation.contains("Spotlight"))
    }

    @Test("Which side the modifier was pressed on does not change what a shortcut is")
    func whichSideTheModifierWasPressedOnDoesNotChangeWhatAShortcutIs() {
        // macOS does not care which Command key opened Spotlight, and neither
        // can the warning: one that only fired for the left one would be a
        // warning that misses half the people it is for.
        let onTheRight = Hotkey.chord(Key(named: "Space")!, with: [.rightCommand])

        #expect(onTheRight.warnings == [.systemShortcut("open Spotlight")])
    }

    @Test("A chord nothing on the machine uses is accepted without a word")
    func aChordNothingOnTheMachineUsesIsAcceptedWithoutAWord() {
        // The warning is worth having only for as long as it is rare. A screen
        // that objected to every choice would be one the user learns to click
        // through.
        #expect(Hotkey.chord(Key(named: "D")!, with: [.leftControl, .leftOption]).warnings.isEmpty)
    }

    @Test("A bare modifier takes no shortcut away, whichever one it is")
    func aBareModifierTakesNoShortcutAway() {
        for modifier in Modifier.allCases where modifier != .function {
            #expect(Hotkey.bareModifier(modifier).warnings.isEmpty)
        }
    }

    // MARK: - What is remembered

    @Test("The Hotkey the user chose is the Hotkey they get back")
    func theHotkeyTheUserChoseIsTheHotkeyTheyGetBack() {
        // Written down as text rather than as a number, so that a key code that
        // means something else on the next keyboard cannot silently become a
        // different Hotkey.
        let chosen: [Hotkey] = [
            .bareModifier(.rightOption),
            .bareModifier(.function),
            .chord(Key(named: "D")!, with: [.leftControl, .leftOption]),
            .chord(Key(named: "Space")!, with: [.leftCommand, .rightShift]),
            .chord(Key(named: "F5")!, with: [.function]),
        ]

        for hotkey in chosen {
            #expect(Hotkey(written: hotkey.written) == hotkey)
        }
    }

    @Test("A remembered Hotkey nothing can read is refused rather than guessed at")
    func aRememberedHotkeyNothingCanReadIsRefused() {
        // A preferences domain edited by hand, or written by a version that
        // spelled it differently. Refusing it here is what lets whoever asked
        // fall back to a Hotkey that works, rather than to a key that does
        // nothing.
        #expect(Hotkey(written: "") == nil)
        #expect(Hotkey(written: "rightOption+leftOption") == nil)
        #expect(Hotkey(written: "banana") == nil)
        #expect(Hotkey(written: "D") == nil)
    }
}
