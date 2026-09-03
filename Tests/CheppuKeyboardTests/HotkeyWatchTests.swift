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
        accessibility: FakeAccessibilityAccess = FakeAccessibilityAccess(answering: [true])
    ) -> HotkeyWatch {
        HotkeyWatch(accessibility: accessibility, keyboard: keyboard)
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
        let reported = ReportedActivations()

        await #expect(throws: HotkeyFailure.accessibilityDenied) {
            try await watch.observe { _ in }
        }

        // Accessibility is granted by hand in System Settings, and nothing
        // tells an app when that happens. Asking again is what makes the Hotkey
        // start working the moment the switch is turned on.
        try await watch.observe(reported.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        #expect(await reported.nextActivation() == .tapped)
    }

    @Test("A keyboard that cannot be watched takes the failure with it")
    func aKeyboardThatCannotBeWatchedTakesTheFailureWithIt() async throws {
        let watch = Self.watch(FakeKeyboard(refuses: true))

        await #expect(throws: FakeKeyboard.WillNotWatch.self) {
            try await watch.observe { _ in }
        }
    }

    // MARK: - What is reported

    @Test("A tap of the Hotkey reaches whoever is listening for it")
    func aTapOfTheHotkeyReachesWhoeverIsListeningForIt() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedActivations()

        try await watch.observe(reported.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        // Awaited rather than read back at the end: a tap that arrives once the
        // user has moved on is not an Activation, it is a surprise.
        #expect(await reported.nextActivation() == .tapped)
    }

    @Test("What the user types passes by, and only the Hotkey is reported")
    func whatTheUserTypesPassesBy() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedActivations()

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
        #expect(await reported.nextActivation() == .tapped)
        #expect(await reported.activations == [.tapped])
    }

    @Test("Watching again replaces the handler already installed")
    func watchingAgainReplacesTheHandlerAlreadyInstalled() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let first = ReportedActivations()
        let second = ReportedActivations()

        try await watch.observe(first.report)
        try await watch.observe(second.report)
        keyboard.strikes(Self.hotkeyDown, Self.everythingUp)

        #expect(await second.nextActivation() == .tapped)
        // One tap is one Activation, however many times watching was started.
        #expect(await first.activations.isEmpty)
        #expect(keyboard.timesWatched == 2)
    }

    @Test("A press that began before Cheppu was watching is not a tap")
    func aPressThatBeganBeforeCheppuWasWatchingIsNotATap() async throws {
        let keyboard = FakeKeyboard()
        let watch = Self.watch(keyboard)
        let reported = ReportedActivations()

        try await watch.observe { _ in }
        keyboard.strikes(Self.hotkeyDown)

        // Watching starts again with the key already down. The half of the
        // press this watch never saw is not one it can vouch for.
        try await watch.observe(reported.report)
        keyboard.strikes(Self.everythingUp, Self.hotkeyDown, Self.everythingUp)

        #expect(await reported.nextActivation() == .tapped)
        #expect(await reported.activations == [.tapped])
    }
}
