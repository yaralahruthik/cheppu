import Testing

@testable import CheppuCore

// The core suite runs with no permissions granted, no Engine downloaded, no
// network and no audio hardware. Any test that needs one of those belongs in the
// word error rate harness, or does not belong at all.
@Suite("Settings screen")
struct SettingsScreenTests {
    private static func screen(
        hotkey: Hotkey = .byDefault,
        isChoosingAHotkey: Bool = false,
        cleanup: CleanupRules = .all,
        areCuesOn: Bool = true,
        launchesAtLogin: Bool = false,
        permissions: [Permission: PermissionStatus] = [
            .microphone: .granted, .accessibility: .granted,
        ]
    ) -> SettingsScreen {
        SettingsScreen(
            hotkey: hotkey,
            isChoosingAHotkey: isChoosingAHotkey,
            cleanup: cleanup,
            areCuesOn: areCuesOn,
            launchesAtLogin: launchesAtLogin,
            permissions: permissions
        )
    }

    /// Which permissions the screen has a row for, in the order they are read.
    private static func permissionsOn(_ screen: SettingsScreen) -> [Permission] {
        screen.controls.compactMap { control in
            guard case .permission(let permission, _) = control else { return nil as Permission? }
            return permission
        }
    }

    @Test("Everything the user can set is on the one screen")
    func everythingTheUserCanSetIsOnTheOneScreen() {
        // The whole of `docs/product-experience.md` §11: the Hotkey, three
        // Cleanup switches, the Cues, launch at login, the permissions this
        // Hotkey needs, and History. Written out here rather than counted,
        // because a setting that quietly stopped being shown is a setting the
        // user has to go looking for in a menu that does not have it either.
        #expect(
            Self.screen(cleanup: .all, areCuesOn: true, launchesAtLogin: true).controls == [
                .hotkey(.byDefault, isBeingChosen: false),
                .cleanupRule(.removesFillerWords, isOn: true),
                .cleanupRule(.capitalisesSentences, isOn: true),
                .cleanupRule(.breaksParagraphs, isOn: true),
                .cues(areOn: true),
                .launchAtLogin(isOn: true),
                .permission(.microphone, .granted),
                .permission(.accessibility, .granted),
                .history,
            ]
        )
    }

    @Test("Every Cleanup rule has a switch of its own")
    func everyCleanupRuleHasASwitchOfItsOwn() {
        // Off has to be a real option for each rule separately: a user who
        // wants their filler words dropped does not necessarily want their
        // paragraphs broken (`docs/product-experience.md` §8). Taken from the
        // rules rather than written out, so a fourth rule cannot arrive with no
        // switch in front of it.
        let switched = Self.screen().controls.compactMap { control in
            guard case .cleanupRule(let rule, _) = control else { return nil as CleanupRule? }
            return rule
        }

        #expect(switched == CleanupRule.allCases)
    }

    // MARK: - The Hotkey

    @Test("The Hotkey is on the screen, and says which key it is")
    func theHotkeyIsOnTheScreenAndSaysWhichKeyItIs() {
        // The user opens Settings to find out what they set it to as often as
        // to change it, so the row reads back the key rather than only offering
        // to take a new one.
        let chord = Hotkey.chord(Key(named: "D")!, with: [.leftControl, .leftOption])
        let screen = Self.screen(hotkey: chord)

        #expect(screen.controls.contains(.hotkey(chord, isBeingChosen: false)))
        #expect(SettingsControl.hotkey(chord, isBeingChosen: false).reading == "⌃⌥D")
        #expect(SettingsControl.hotkey(chord, isBeingChosen: false).action != nil)
        #expect(SettingsControl.hotkey(chord, isBeingChosen: false).isOn == nil)
    }

    @Test("The row says when it is listening, rather than taking a keystroke without warning")
    func theRowSaysWhenItIsListening() {
        let listening = Self.screen(hotkey: .byDefault, isChoosingAHotkey: true)
        let waiting = SettingsControl.hotkey(.byDefault, isBeingChosen: true)

        #expect(listening.controls.contains(waiting))
        // And the same button is the way out of it, so a user who clicked
        // "Change…" by accident is not stuck holding a keyboard.
        #expect(waiting.action == "Cancel")
        #expect(waiting.reading != Hotkey.byDefault.name)
    }

    @Test("Input Monitoring is shown only when the chosen Hotkey needs it")
    func inputMonitoringIsShownOnlyWhenTheChosenHotkeyNeedsIt() {
        // Cheppu asks for no permission the Hotkey does not actually need, and
        // a row offering the way to a pane the user has no reason to visit is
        // the screen asking for one.
        let onTheDefault = Self.screen(hotkey: .byDefault)
        let onTheGlobeKey = Self.screen(
            hotkey: .bareModifier(.function),
            permissions: [
                .microphone: .granted, .accessibility: .granted, .inputMonitoring: .notGranted,
            ]
        )

        #expect(Self.permissionsOn(onTheDefault) == [.microphone, .accessibility])
        #expect(
            Self.permissionsOn(onTheGlobeKey) == [.microphone, .accessibility, .inputMonitoring]
        )
        #expect(onTheGlobeKey.controls.contains(.permission(.inputMonitoring, .notGranted)))
    }

    @Test("A permission nobody answered for is shown as not granted rather than left out")
    func aPermissionNobodyAnsweredForIsShownAsNotGranted() {
        // The row the user came to check is the one that must not quietly go
        // missing.
        #expect(
            Self.screen(permissions: [:]).controls.contains(.permission(.microphone, .notGranted))
        )
    }

    @Test("A switch says which way the user left it")
    func aSwitchSaysWhichWayTheUserLeftIt() {
        let screen = Self.screen(
            cleanup: CleanupRules(
                removesFillerWords: false, capitalisesSentences: true, breaksParagraphs: false),
            areCuesOn: false,
            launchesAtLogin: true
        )

        #expect(screen.controls.contains(.cleanupRule(.removesFillerWords, isOn: false)))
        #expect(screen.controls.contains(.cleanupRule(.capitalisesSentences, isOn: true)))
        #expect(screen.controls.contains(.cleanupRule(.breaksParagraphs, isOn: false)))
        #expect(screen.controls.contains(.cues(areOn: false)))
        #expect(screen.controls.contains(.launchAtLogin(isOn: true)))
    }

    @Test("Every permission's status is shown without a Dictation being started")
    func everyPermissionsStatusIsShown() {
        // The question Settings answers about a permission is "is it still
        // granted?", and the answer must not cost the user a Dictation to find
        // out (`docs/product-experience.md` §9).
        let screen = Self.screen(permissions: [.microphone: .granted, .accessibility: .notGranted])

        #expect(screen.controls.contains(.permission(.microphone, .granted)))
        #expect(screen.controls.contains(.permission(.accessibility, .notGranted)))
    }

    @Test("Every permission offers the way to the pane it is granted on")
    func everyPermissionOffersTheWayToThePaneItIsGrantedOn() {
        // Whichever way it is answered. The user came here to check a
        // permission, and both things they might do about one — grant it, or
        // take it back — are the same switch on the same pane.
        for status in [PermissionStatus.granted, .notGranted] {
            #expect(SettingsControl.permission(.microphone, status).action != nil)
            #expect(SettingsControl.permission(.accessibility, status).action != nil)
        }
    }

    @Test("A row under a heading that has already named it does not say it twice")
    func aRowUnderAHeadingThatHasAlreadyNamedItDoesNotSayItTwice() {
        // History is one section of one row about one thing, and the sentence
        // under the heading is what the user came to read. The Cleanup rows are
        // the other way round: the heading names the group and each row names
        // itself.
        let sections = Self.screen().sections
        let history = sections.first { $0.title == "History" }
        let cleanup = sections.first { $0.title == "Cleanup" }

        #expect(history?.saysItsOwnTitle(.history) == false)
        #expect(
            cleanup?.controls.allSatisfy { cleanup?.saysItsOwnTitle($0) == true } == true
        )
    }

    @Test("A permission is a reading rather than a switch")
    func aPermissionIsAReadingRatherThanASwitch() {
        // Cheppu cannot grant itself a permission, so the row must not look
        // like something that can be flicked. Same for History, which is an
        // action and not a setting.
        #expect(SettingsControl.permission(.microphone, .granted).isOn == nil)
        #expect(SettingsControl.history.isOn == nil)
        #expect(SettingsControl.cues(areOn: true).isOn == true)
    }

    @Test("History can be emptied from this window")
    func historyCanBeEmptiedFromThisWindow() {
        // The one action, and no ellipsis on it: nothing is asked first
        // (ADR-0009).
        #expect(Self.screen().controls.contains(.history))
        #expect(SettingsControl.history.action == "Clear History")
    }

    @Test("Sections group the rows and never hide them")
    func sectionsGroupTheRowsAndNeverHideThem() {
        // Headings on one screen, not tabs. Every row the screen has is a row
        // the user can see without clicking anything, which is what the section
        // titles cost: nothing.
        let screen = Self.screen()

        #expect(
            screen.sections.map(\.title) == [
                "Hotkey", "Cleanup", "Sounds", "Startup", "Permissions", "History",
            ]
        )
        #expect(screen.sections.allSatisfy { !$0.controls.isEmpty })
        #expect(screen.controls.count == screen.sections.reduce(0) { $0 + $1.controls.count })
    }

    @Test("No setting needs a paragraph to explain")
    func noSettingNeedsAParagraphToExplain() {
        // A setting that needs a paragraph is the wrong setting or the wrong
        // default (`docs/product-experience.md` §11). So the screen has room
        // for one sentence under a row and no room for a second: the bound is
        // here rather than in the window, where it would be a layout that
        // happened to fit rather than a promise.
        for control in Self.screen(permissions: [.microphone: .notGranted]).controls {
            #expect(control.title.count <= 48)
            guard let explanation = control.explanation else { continue }
            #expect(explanation.count <= 80)
            #expect(explanation.filter { $0 == "." }.count == 1)
            #expect(explanation.hasSuffix("."))
        }
    }


    @Test("A Microphone that is off is never a reason to stop watching for the Hotkey")
    func aMicrophoneThatIsOffIsNeverAReasonToStopWatching() {
        // Cheppu keeps an eye on the grants it needs to see the Hotkey at all,
        // because macOS tells nobody when one is taken away. The Microphone is
        // not one of them: it is what a Dictation needs once the key has
        // arrived, and a microphone switched off must not be what stops the key
        // arriving in the first place.
        #expect(Permission.neededToWatch(.byDefault) == [.accessibility])
        #expect(!Permission.neededToWatch(.byDefault).contains(.microphone))
        #expect(
            Permission.neededBy(.byDefault)
                == [.microphone] + Permission.neededToWatch(.byDefault))
    }
}
