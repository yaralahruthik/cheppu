import CheppuCore
import Testing

@testable import CheppuKeyboard

// What the Hotkey port does around the keyboard: when it asks whether it may
// watch, what it reports, what it lets pass, and what it says when it cannot
// watch at all. No event tap is created here, which is also what stops running
// the suite from asking the terminal for Accessibility.
@Suite("Hotkey watch")
struct HotkeyWatchTests {
    private static func watch(
        _ keyboard: FakeKeyboard,
        accessibility: FakeAccessibilityAccess = FakeAccessibilityAccess(answering: [true]),
        inputMonitoring: FakeInputMonitoringAccess = FakeInputMonitoringAccess(granted: false),
        watchingFor hotkey: Hotkey = .byDefault
    ) -> HotkeyWatch {
        HotkeyWatch(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            keyboard: keyboard,
            choice: ChosenHotkey(hotkey)
        )
    }

    private static let hotkeyDown = KeyStroke.modifiersHeld([.rightOption])
    private static let everythingUp = KeyStroke.modifiersHeld([])

    // MARK: - Asking to watch

    @Test("Accessibility is read when the keyboard is first watched, and not before")
    func accessibilityIsReadWhenTheKeyboardIsFirstWatchedAndNotBefore() async throws {
        let accessibility = FakeAccessibilityAccess(answering: [true])
        let watch = Self.watch(FakeKeyboard(), accessibility: accessibility)

        #expect(accessibility.timesRead == 0)

        try await watch.observe { _ in }

        #expect(accessibility.timesRead == 1)
    }

    @Test("Without Accessibility, the Hotkey says so rather than silently doing nothing")
    func withoutAccessibilityTheHotkeySaysSo() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard, accessibility: FakeAccessibilityAccess(answering: [false]))

        await #expect(throws: HotkeyFailure.accessibilityDenied) {
            try await watch.observe { _ in }
        }

        // And nothing is watching the keyboard behind the refusal.
        #expect(!keyboard.isBeingWatched)
    }

    @Test("Accessibility granted after a refusal is watched at the next attempt, without a relaunch")
    func accessibilityGrantedAfterARefusalIsWatchedAtTheNextAttempt() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard, accessibility: FakeAccessibilityAccess(answering: [false, true]))
        let reported = ReportedGestures()

        await #expect(throws: HotkeyFailure.accessibilityDenied) {
            try await watch.observe { _ in }
        }

        // Accessibility is granted by hand in System Settings, and nothing
        // tells an app when that happens. Asking again is what makes the Hotkey
        // start working the moment the switch is turned on.
        try await watch.observe(reported.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
    }

    @Test("A keyboard that cannot be watched takes the failure with it")
    func aKeyboardThatCannotBeWatchedTakesTheFailureWithIt() async throws {
        let watch = Self.watch(FakeKeyboard(refuses: true))

        await #expect(throws: FakeKeyboard.WillNotWatch.self) {
            try await watch.observe { _ in }
        }
    }

    // MARK: - Which key is watched for

    @Test("The Hotkey watched for is the one the user chose, read as watching starts")
    func theHotkeyWatchedForIsTheOneTheUserChose() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard, watchingFor: .bareModifier(.leftControl))
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        keyboard.strikes(.modifiersHeld([.leftControl]), Self.everythingUp)

        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
    }

    @Test("Watching again is the whole of changing the Hotkey")
    func watchingAgainIsTheWholeOfChangingTheHotkey() async throws {
        // The user picks a new key in Settings, and the next press is theirs —
        // no relaunch, and nothing between the window and the keyboard that has
        // to be kept in step (ADR-0010).
        let keyboard = FakeKeyboard()
        let choice = ChosenHotkey()
        let watch = HotkeyWatch(
            accessibility: FakeAccessibilityAccess(answering: [true]),
            inputMonitoring: FakeInputMonitoringAccess(),
            keyboard: keyboard,
            choice: choice
        )
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        await choice.change(to: .chord(Key(named: "D")!, with: [.leftControl]))
        try await watch.observe(reported.report)

        keyboard.strikes(.modifiersHeld([.leftControl]), .hotkeyKeyPressed, .hotkeyKeyReleased)

        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
    }

    @Test("The keyboard is told which key to tell apart, and only where there is one")
    func theKeyboardIsToldWhichKeyToTellApart() async throws {
        // The one key the user chose is told apart from the ones they type, and
        // on a bare-modifier Hotkey no key is told apart at all (ADR-0011).
        let onAChord = FakeKeyboard()
        try await Self.watch(
            onAChord, watchingFor: .chord(Key(named: "D")!, with: [.leftControl])
        ).observe { _ in }

        let onTheDefault = FakeKeyboard()
        try await Self.watch(onTheDefault).observe { _ in }

        #expect(onAChord.keyToldApart == Key(named: "D"))
        #expect(onTheDefault.keyToldApart == nil)
    }

    // MARK: - Input Monitoring

    @Test("Input Monitoring is asked about only by a Hotkey that needs it")
    func inputMonitoringIsAskedAboutOnlyByAHotkeyThatNeedsIt() async throws {
        // Cheppu asks for no permission the chosen Hotkey does not actually
        // need: on every key but the Globe one, a refusal has no bearing on
        // whether the Hotkey works.
        let keyboard = FakeKeyboard()
        let refused = FakeInputMonitoringAccess(granted: false)

        try await Self.watch(keyboard, inputMonitoring: refused).observe { _ in }

        #expect(keyboard.isBeingWatched)
        #expect(refused.timesAsked == 0)
    }

    @Test("Without Input Monitoring, the Globe key says so rather than doing nothing")
    func withoutInputMonitoringTheGlobeKeySaysSo() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(
            keyboard,
            inputMonitoring: FakeInputMonitoringAccess(granted: false),
            watchingFor: .bareModifier(.function)
        )

        // A different failure from a missing Accessibility grant, because it is
        // a different pane and a different sentence.
        await #expect(throws: HotkeyFailure.inputMonitoringDenied) {
            try await watch.observe { _ in }
        }
        #expect(!keyboard.isBeingWatched)
    }

    @Test("With Input Monitoring, the Globe key is watched like any other")
    func withInputMonitoringTheGlobeKeyIsWatchedLikeAnyOther() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(
            keyboard,
            inputMonitoring: FakeInputMonitoringAccess(granted: true),
            watchingFor: .bareModifier(.function)
        )
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        keyboard.strikes(.modifiersHeld([.function]), Self.everythingUp)

        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
    }

    @Test("A Hotkey that is refused takes the one it replaced down with it")
    func aHotkeyThatIsRefusedTakesTheOneItReplacedDownWithIt() async throws {
        // Somebody moves their Hotkey to the Globe key and does not grant Input
        // Monitoring. What they must not be left with is the key they moved off
        // still starting Dictations while Settings says they dictate on the
        // Globe key.
        let keyboard = FakeKeyboard()
        let choice = ChosenHotkey()
        let watch = HotkeyWatch(
            accessibility: FakeAccessibilityAccess(answering: [true]),
            inputMonitoring: FakeInputMonitoringAccess(granted: false),
            keyboard: keyboard,
            choice: choice
        )
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        await choice.change(to: .bareModifier(.function))

        await #expect(throws: HotkeyFailure.inputMonitoringDenied) {
            try await watch.observe(reported.report)
        }

        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)
        #expect(!keyboard.isBeingWatched)
        #expect(await reported.gestures.isEmpty)
    }

    @Test("Accessibility is answered before Input Monitoring is ever considered")
    func accessibilityIsAnsweredBeforeInputMonitoringIsEverConsidered() async throws {
        // Without Accessibility no Hotkey works at all, so it is the thing to
        // say. Telling a user to grant two permissions when the first one is
        // the reason is two trips to System Settings instead of one.
        let watch = Self.watch(
            FakeKeyboard(),
            accessibility: FakeAccessibilityAccess(answering: [false]),
            inputMonitoring: FakeInputMonitoringAccess(granted: false),
            watchingFor: .bareModifier(.function)
        )

        await #expect(throws: HotkeyFailure.accessibilityDenied) {
            try await watch.observe { _ in }
        }
    }

    // MARK: - What is reported

    @Test("The Hotkey going down and coming back up reaches whoever is listening for it")
    func theHotkeyGoingDownAndComingBackUpReachesWhoeverIsListeningForIt() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        // Awaited rather than read back at the end: a press that arrives once
        // the user has moved on is not an Activation, it is a surprise. And the
        // press arrives before the release, because a Dictation starts on the
        // way down.
        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
    }

    @Test("What the user types passes by, and only the Hotkey is reported")
    func whatTheUserTypesPassesBy() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedGestures()

        try await watch.observe(reported.report)
        keyboard.strikes(
            .keyPressed,
            .modifiersHeld([.leftShift]),
            .keyPressed,
            Self.everythingUp,
            Self.hotkeyDown,
            Self.everythingUp
        )

        // A sentence typed in someone else's app, and then the Hotkey. Only the
        // last of those is Cheppu's business.
        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
        #expect(await reported.gestures == [.pressed, .released])
    }

    @Test("Watching again replaces the handler already installed")
    func watchingAgainReplacesTheHandlerAlreadyInstalled() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let first = ReportedGestures()
        let second = ReportedGestures()

        try await watch.observe(first.report)
        try await watch.observe(second.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        #expect(await second.nextGesture() == .pressed)
        #expect(await second.nextGesture() == .released)
        // One press is one press, however many times watching was started.
        #expect(await first.gestures.isEmpty)
        #expect(keyboard.timesWatched == 2)
    }

    @Test("A press that began before Cheppu was watching is not reported")
    func aPressThatBeganBeforeCheppuWasWatchingIsNotReported() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedGestures()

        try await watch.observe { _ in }
        keyboard.strikes(Self.hotkeyDown)

        // Watching starts again with the key already down. The half of the
        // press this watch never saw is not one it can vouch for.
        try await watch.observe(reported.report)
        keyboard.strikes(Self.everythingUp, Self.hotkeyDown, Self.everythingUp)

        // The key coming up is not a release of a press this watch reported,
        // and the press that follows it is reported whole.
        #expect(await reported.nextGesture() == .pressed)
        #expect(await reported.nextGesture() == .released)
        #expect(await reported.gestures == [.pressed, .released])
    }
}
