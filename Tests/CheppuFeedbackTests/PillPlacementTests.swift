import CoreGraphics
import Testing

@testable import CheppuFeedback

// Where the Pill goes is the only thing about it a test can read back — a panel
// needs a screen, and the suite has none — so it is the part that decides and
// the part that is tested. Every one of these is a claim about what the user
// sees out of the corner of an eye that is on their work.
@Suite("Pill placement")
struct PillPlacementTests {
    /// A laptop screen, with the menu bar and the Dock already taken off it:
    /// `NSScreen.visibleFrame` is what the Pill is placed within, so that
    /// resting near the bottom is never resting behind the Dock.
    private static let screen = CGRect(x: 0, y: 44, width: 1_512, height: 866)

    /// The Pill, placed with nothing in the way.
    private static var home: CGRect {
        PillPlacement.place(on: screen, keepingClearOf: [])
    }

    /// The Pill, keeping clear of one thing.
    private static func placed(clearOf field: CGRect) -> CGRect {
        PillPlacement.place(on: screen, keepingClearOf: [field])
    }

    @Test("With nothing in the way the Pill rests at the bottom of the screen, in the middle")
    func withNothingInTheWayThePillRestsAtTheBottomInTheMiddle() {
        #expect(Self.home.midX == Self.screen.midX)
        #expect(Self.home.minY == Self.screen.minY + PillPlacement.restingAboveTheBottom)
        #expect(Self.home.size == PillPlacement.size)
    }

    @Test("A field nowhere near the Pill leaves it exactly where it always is")
    func aFieldNowhereNearThePillLeavesItWhereItAlwaysIs() {
        // The ordinary case: someone writing an email, with the cursor
        // somewhere up in the body of it. A Pill that moved for that would be a
        // Pill the user has to find each time.
        let bodyOfAnEmail = CGRect(x: 400, y: 500, width: 700, height: 300)

        #expect(Self.placed(clearOf: bodyOfAnEmail) == Self.home)
    }

    @Test("A field where the Pill rests moves the Pill above it")
    func aFieldWhereThePillRestsMovesThePillAboveIt() {
        // A chat box, a terminal prompt and a search field all sit exactly
        // where the Pill rests.
        let chatBox = CGRect(x: 300, y: 60, width: 900, height: 44)

        let placed = Self.placed(clearOf: chatBox)

        #expect(placed != Self.home)
        #expect(placed.minY >= chatBox.maxY + PillPlacement.clearOfTheField)
        #expect(!placed.intersects(chatBox))
        #expect(Self.screen.contains(placed))
    }

    @Test("Stepping clear of a field moves the Pill up and nowhere else")
    func steppingClearOfAFieldMovesThePillUpAndNowhereElse() {
        // Horizontally the Pill has one place, whatever is in the way. A
        // window off to one side of the screen has room next to it, and taking
        // it would be a Pill that appears somewhere different for every app the
        // user dictates into.
        let chatBox = CGRect(x: 40, y: 60, width: 800, height: 44)

        let placed = Self.placed(clearOf: chatBox)

        #expect(placed.midX == Self.home.midX)
        #expect(placed.minY > Self.home.minY)
    }

    @Test("A text cursor with no width of its own still moves the Pill")
    func aTextCursorWithNoWidthOfItsOwnStillMovesThePill() {
        // What a text field answers with is often the caret rather than the
        // field: a line one point wide. It is still the thing the user is
        // watching their words arrive at.
        let caret = CGRect(x: Self.screen.midX, y: 70, width: 1, height: 18)

        let placed = Self.placed(clearOf: caret)

        #expect(placed != Self.home)
        #expect(!placed.intersects(caret))
    }

    @Test("A field with no room above it moves the Pill below it instead")
    func aFieldWithNoRoomAboveItMovesThePillBelowIt() {
        // A window standing on the bottom edge of the screen and filling the
        // rest of it: it covers where the Pill rests, there is nothing above it
        // to move to, and the only room left is the strip underneath.
        let almostTheWholeScreen = CGRect(x: 0, y: 100, width: 1_512, height: 800)

        let placed = Self.placed(clearOf: almostTheWholeScreen)

        #expect(placed != Self.home)
        #expect(placed.maxY <= almostTheWholeScreen.minY - PillPlacement.clearOfTheField)
        #expect(Self.screen.contains(placed))
    }

    @Test("A field with the whole screen in it leaves the Pill where it can be seen")
    func aFieldWithTheWholeScreenInItLeavesThePillWhereItCanBeSeen() {
        // An editor filling the screen: there is nowhere the Pill would not be
        // over it, and a Pill off the edge of the screen is worse than one in
        // the way — the user would have no way of knowing Cheppu was listening
        // at all.
        let fullScreenEditor = Self.screen

        let placed = Self.placed(clearOf: fullScreenEditor)

        #expect(placed == Self.home)
        #expect(Self.screen.contains(placed))
    }

    @Test("A field too big to step clear of still leaves the line being typed on uncovered")
    func aFieldTooBigToStepClearOfStillLeavesTheLineBeingTypedOnUncovered() {
        // An editor filling the screen, with the cursor down at the bottom of
        // it — the last line of a long file, which is where someone dictating
        // into a document usually is. There is no clearing the editor, so the
        // Pill clears the line instead.
        let fullScreenEditor = Self.screen
        let lastLine = CGRect(x: Self.screen.midX, y: 70, width: 1, height: 18)

        let placed = PillPlacement.place(
            on: Self.screen,
            keepingClearOf: [fullScreenEditor, lastLine]
        )

        #expect(placed != Self.home)
        #expect(!placed.intersects(lastLine))
        #expect(Self.screen.contains(placed))
    }

    @Test("The Pill rests on the screen it was given, not on the one at the origin")
    func thePillRestsOnTheScreenItWasGiven() {
        // A second display, to the left of and below the built-in one. Screen
        // coordinates there are negative, and a Pill placed by arithmetic that
        // assumed otherwise would be on the wrong display or off every display.
        let secondDisplay = CGRect(x: -2_560, y: -400, width: 2_560, height: 1_440)

        let placed = PillPlacement.place(on: secondDisplay, keepingClearOf: [])

        #expect(secondDisplay.contains(placed))
        #expect(placed.midX == secondDisplay.midX)
    }
}
