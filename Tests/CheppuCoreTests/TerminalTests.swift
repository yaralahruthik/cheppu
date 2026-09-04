import Testing

@testable import CheppuCore

// What Cheppu is willing to call a Terminal, and why. The whole of the question
// is what kind of app has focus and what kind of thing inside it the keyboard is
// pointing at — nothing here reads a screen, and nothing here needs one.
@Suite("Terminal awareness")
struct TerminalTests {
    /// A reading of focus, said in one line.
    private func focused(on bundleIdentifier: String?, pointingAt role: String?) -> TargetApp {
        TargetApp(
            bundleIdentifier: bundleIdentifier, processIdentifier: 501, focusedElementRole: role)
    }

    @Test("A Terminal on the list is a Terminal, whatever it says it is showing")
    func aTerminalOnTheListIsATerminal() {
        // Terminal.app and iTerm2 both expose the same ordinary text area a mail
        // window does, so the role alone would clear them. Being named is what
        // tells them apart, and it is the half of the answer that is exact.
        #expect(focused(on: "com.apple.Terminal", pointingAt: "AXTextArea").isATerminal)
        #expect(focused(on: "com.googlecode.iterm2", pointingAt: "AXTextArea").isATerminal)
    }

    @Test("A Terminal nobody named is a Terminal when it points at nothing Cheppu knows")
    func aTerminalNobodyNamedIsStillATerminal() {
        // The emulators that draw their own screen expose no focused element at
        // all, and there will always be one more of them than the list has.
        #expect(focused(on: "com.example.NewTerminal", pointingAt: nil).isATerminal)

        // And one that exposes something Cheppu does not recognise as a place
        // text is written is read the same way.
        #expect(focused(on: "com.example.NewTerminal", pointingAt: "AXUnknown").isATerminal)
    }

    @Test("Somewhere text is written is not a Terminal")
    func somewhereTextIsWrittenIsNotATerminal() {
        // The other side of the same rule: the app is unknown, and what the
        // keyboard is pointing at is a place text goes, so the Paragraph Breaks
        // survive.
        #expect(!focused(on: "com.apple.mail", pointingAt: "AXTextArea").isATerminal)
        #expect(!focused(on: "com.example.SomeEditor", pointingAt: "AXTextArea").isATerminal)
        #expect(!focused(on: "com.apple.Safari", pointingAt: "AXTextField").isATerminal)
        #expect(!focused(on: nil, pointingAt: "AXWebArea").isATerminal)
    }

    @Test("A Paragraph Break becomes one space in a Terminal and stays a break everywhere else")
    func aParagraphBreakBecomesOneSpaceInATerminal() {
        let saidInTwoParagraphs = FinalText("That is one thought.\nThe next one")

        #expect(
            saidInTwoParagraphs.normalisedForInsertion(into: ATargetApp.terminal).text
                == "That is one thought. The next one")
        #expect(
            saidInTwoParagraphs.normalisedForInsertion(into: ATargetApp.mail).text
                == "That is one thought.\nThe next one")
    }

    @Test("A run of newlines becomes one space, not one space each")
    func aRunOfNewlinesBecomesOneSpace() {
        // Cleanup only ever writes a single newline, but with its rules off the
        // Final Text is whatever the Engine produced, and that is where a
        // blank line between two paragraphs comes from.
        #expect(
            FinalText("first\r\n\nsecond").normalisedForInsertion(into: ATargetApp.terminal).text
                == "first second")
    }

    @Test("What goes into a Terminal is still trimmed at both ends")
    func whatGoesIntoATerminalIsStillTrimmed() {
        // Terminal awareness is the second thing that happens at the Insertion
        // boundary and not a replacement for the first: the Engine's leading
        // space and trailing newline go, rather than the newline becoming a
        // space the user did not ask for at the end of their command.
        #expect(
            FinalText(" ls -la\n").normalisedForInsertion(into: ATargetApp.terminal).text == "ls -la"
        )
    }

    @Test("Two readings of focus inside one app are the same app")
    func twoReadingsOfFocusInsideOneAppAreTheSameApp() {
        // Which is what Insertion asks before it types. The user clicking from
        // the field they dictated into to the button beside it changes the
        // focused element's role and not the app, and the words still belong
        // where they were going.
        let field = focused(on: "com.apple.mail", pointingAt: "AXTextArea")
        let button = focused(on: "com.apple.mail", pointingAt: "AXButton")

        #expect(field.isTheSameAppAs(button))
        #expect(!field.isTheSameAppAs(ATargetApp.browser))
    }
}
