import Testing

@testable import CheppuCore

// What the Pill writes rather than draws. The two states the user reads are
// decided here rather than in front of a screen, so that the words Cheppu says
// about a moment and the pane it opens about the same moment are the same
// answer.
@Suite("What the Pill says")
struct PillTests {
    @Test("The states a Dictation runs through are drawn rather than written")
    func theStatesADictationRunsThroughAreDrawn() {
        // "Can it hear me?" and "is it working?" are answered faster by a shape
        // than by a word (`docs/product-experience.md` §3), so neither state has
        // anything to say.
        #expect(PillState.listening(.silent).words == nil)
        #expect(PillState.transcribing.words == nil)
    }

    @Test("The Clipboard Fallback says where the words are")
    func theClipboardFallbackSaysWhereTheWordsAre() {
        // And never why they are there: what the user does next is paste,
        // whichever way the Insertion failed.
        #expect(PillState.onTheClipboard.words == "On the clipboard")
    }

    @Test("A permission that is missing is named, rather than left to be guessed")
    func aPermissionThatIsMissingIsNamed() {
        // A Dictation that did nothing is indistinguishable from an app that is
        // broken. The Pill is the only thing on screen at that moment, so it
        // says which permission is in the way — by the name macOS calls it, so
        // that it is the name on the pane the user is sent to.
        for permission in Permission.allCases {
            let said = PillState.permissionMissing(permission).words
            #expect(said?.contains(permission.name) == true)
        }
    }
}
