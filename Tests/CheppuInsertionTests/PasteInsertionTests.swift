import CheppuCore
import Foundation
import Testing

@testable import CheppuInsertion

// What Insertion does around the pasteboard and the keyboard: what the Target
// App is handed, what the user's clipboard looks like afterwards, and what
// happens when the user has moved on. Nothing here touches the pasteboard of
// the machine running the suite, and nothing here types anywhere.
@Suite("Paste Insertion")
struct PasteInsertionTests {
    private static let mail = TargetApp(bundleIdentifier: "com.apple.mail", processIdentifier: 501)
    private static let browser = TargetApp(
        bundleIdentifier: "com.apple.Safari", processIdentifier: 502)

    /// What the user had copied before they dictated: a screenshot, which no
    /// amount of putting a string back would restore.
    private static let aScreenshot = PasteboardContents(items: [
        ["public.png": Data([0x89, 0x50, 0x4E, 0x47])]
    ])

    private static let hello = FinalText("hello there")

    /// An Insertion wired to a pasteboard that is nobody's and a keyboard that
    /// is unplugged.
    private struct Scenario {
        let pasteboard: FakePasteboard
        let keystrokes: FakeKeystrokes
        let focus: FakeFocus
        let insertion: PasteInsertion

        init(
            clipboardHolding contents: PasteboardContents = PasteboardContents(items: []),
            typingIn app: TargetApp? = PasteInsertionTests.mail,
            keystrokeRefused: Bool = false
        ) {
            let pasteboard = FakePasteboard(holding: contents)
            let keystrokes = FakeKeystrokes(reading: pasteboard, refuses: keystrokeRefused)
            let focus = FakeFocus(on: app)
            self.pasteboard = pasteboard
            self.keystrokes = keystrokes
            self.focus = focus
            self.insertion = PasteInsertion(
                focus: focus,
                pasteboard: pasteboard,
                keystrokes: keystrokes,
                // The suite does not wait for a Target App that is not there.
                whileTheTargetAppPastes: .zero
            )
        }
    }

    @Test("The Final Text is what the Target App is handed to paste")
    func theFinalTextIsWhatTheTargetAppIsHandedToPaste() async throws {
        let scenario = Scenario()

        try await scenario.insertion.insert(Self.hello, into: Self.mail)

        #expect(scenario.keystrokes.pastedText == ["hello there"])
    }

    @Test("The clipboard afterwards holds exactly what it held before")
    func theClipboardAfterwardsHoldsExactlyWhatItHeldBefore() async throws {
        let scenario = Scenario(clipboardHolding: Self.aScreenshot)

        try await scenario.insertion.insert(Self.hello, into: Self.mail)

        // Given back whole, and as what it was: a Dictation must not turn the
        // screenshot someone copied five minutes ago into a line of text.
        #expect(scenario.pasteboard.contents() == Self.aScreenshot)
    }

    @Test("A clipboard that was empty before the Dictation is empty after it")
    func aClipboardThatWasEmptyBeforeTheDictationIsEmptyAfterIt() async throws {
        let scenario = Scenario()

        try await scenario.insertion.insert(Self.hello, into: Self.mail)

        // Leaving the Final Text behind would be the one case where "put it
        // back as you found it" quietly means "and keep what you borrowed".
        #expect(scenario.pasteboard.contents().items.isEmpty)
    }

    @Test("An Insertion whose Target App no longer has focus is abandoned rather than misdirected")
    func anInsertionWhoseTargetAppNoLongerHasFocusIsAbandoned() async throws {
        let scenario = Scenario(clipboardHolding: Self.aScreenshot, typingIn: Self.mail)

        // The Engine took a moment, and the user clicked into their browser
        // while it worked.
        scenario.focus.moveTo(Self.browser)

        await #expect(throws: InsertionFailure.focusMoved) {
            try await scenario.insertion.insert(Self.hello, into: Self.mail)
        }

        #expect(scenario.keystrokes.pastedText.isEmpty)
        // And the clipboard was never even borrowed: an Insertion that cannot
        // happen costs the user nothing at all.
        #expect(scenario.pasteboard.wasBorrowedFor.isEmpty)
        #expect(scenario.pasteboard.contents() == Self.aScreenshot)
    }

    @Test("An Insertion with nothing focused at all is abandoned")
    func anInsertionWithNothingFocusedAtAllIsAbandoned() async throws {
        let scenario = Scenario(typingIn: nil)

        await #expect(throws: InsertionFailure.focusMoved) {
            try await scenario.insertion.insert(Self.hello, into: Self.mail)
        }

        #expect(scenario.pasteboard.wasBorrowedFor.isEmpty)
    }

    @Test("A paste macOS would not let Cheppu type still gives the clipboard back")
    func aPasteMacOSWouldNotLetCheppuTypeStillGivesTheClipboardBack() async throws {
        let scenario = Scenario(clipboardHolding: Self.aScreenshot, keystrokeRefused: true)

        await #expect(throws: InsertionFailure.keystrokeRefused) {
            try await scenario.insertion.insert(Self.hello, into: Self.mail)
        }

        // The Insertion failed; the clipboard is not collateral.
        #expect(scenario.pasteboard.contents() == Self.aScreenshot)
    }

    @Test("One Dictation's Insertion borrows the clipboard once and gives it straight back")
    func oneDictationsInsertionBorrowsTheClipboardOnceAndGivesItStraightBack() async throws {
        let scenario = Scenario(clipboardHolding: Self.aScreenshot)

        try await scenario.insertion.insert(Self.hello, into: Self.mail)
        try await scenario.insertion.insert(FinalText("and again"), into: Self.mail)

        #expect(scenario.pasteboard.wasBorrowedFor == ["hello there", "and again"])
        #expect(scenario.pasteboard.contents() == Self.aScreenshot)
    }
}
