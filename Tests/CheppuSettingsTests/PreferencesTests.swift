import CheppuCore
import Foundation
import Testing

@testable import CheppuSettings

// What Cheppu remembers of what the user set, and what it does before they have
// set anything. Every test here writes to a preferences domain of its own and
// takes it away again, so running the suite can neither read nor change what the
// person running it chose.
@Suite("Preferences")
struct PreferencesTests {
    private static func inADomainOfItsOwn(_ test: (Preferences, UserDefaults) -> Void) {
        let name = "com.iamyhr.cheppu.suite.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        test(Preferences(in: defaults), defaults)
    }

    @Test("A fresh install cleans up what was said, and can be heard")
    func aFreshInstallCleansUpAndCanBeHeard() {
        Self.inADomainOfItsOwn { preferences, _ in
            // Somebody who has never opened Settings has not asked for a
            // Dictation full of "um", and has not asked for one they cannot
            // hear either. On is what they would have chosen, so it is what
            // they get without choosing.
            #expect(preferences.rules() == .all)
            #expect(preferences.areCuesOn())
        }
    }

    @Test("A switch the user moves is still where they left it next time")
    func aSwitchTheUserMovesIsStillWhereTheyLeftIt() {
        Self.inADomainOfItsOwn { preferences, defaults in
            preferences.turn(.removesFillerWords, on: false)
            preferences.turnCues(on: false)

            // A second `Preferences` over the same domain is what the next
            // launch is: nothing is carried over in memory, and the answers
            // come back off the disk.
            let afterARelaunch = Preferences(in: defaults)

            #expect(afterARelaunch.rules()[.removesFillerWords] == false)
            #expect(afterARelaunch.areCuesOn() == false)
        }
    }

    @Test("Moving one Cleanup rule leaves the other two alone")
    func movingOneCleanupRuleLeavesTheOtherTwoAlone() {
        Self.inADomainOfItsOwn { preferences, _ in
            // One key per rule, so that a user who wants their paragraphs left
            // alone keeps their filler words dropped
            // (`docs/product-experience.md` §8).
            preferences.turn(.breaksParagraphs, on: false)

            #expect(
                preferences.rules()
                    == CleanupRules(
                        removesFillerWords: true, capitalisesSentences: true,
                        breaksParagraphs: false)
            )
        }
    }

    @Test("Every rule can be turned off and back on by name")
    func everyRuleCanBeTurnedOffAndBackOnByName() {
        Self.inADomainOfItsOwn { preferences, _ in
            for rule in CleanupRule.allCases {
                preferences.turn(rule, on: false)
                #expect(preferences.rules()[rule] == false)
                preferences.turn(rule, on: true)
                #expect(preferences.rules()[rule] == true)
            }

            // A key that pointed at the wrong rule would show up as one switch
            // moving another, which no window could make sense of.
            #expect(preferences.rules() == .all)
        }
    }

    @Test("Reading a switch nobody has moved writes nothing")
    func readingASwitchNobodyHasMovedWritesNothing() {
        Self.inADomainOfItsOwn { preferences, defaults in
            _ = preferences.rules()
            _ = preferences.areCuesOn()

            // The defaults are what Cheppu does, not something it saves on the
            // user's behalf. A launch that wrote them down would be one that
            // froze today's answers into a machine that never asked for them.
            #expect(defaults.object(forKey: Preferences.Key.cuesAreOn) == nil)
            for rule in CleanupRule.allCases {
                #expect(defaults.object(forKey: Preferences.Key.cleanup(rule)) == nil)
            }
        }
    }

    @Test("The Cue switch the menu bar has been writing is the one Settings shows")
    func theCueSwitchTheMenuBarHasBeenWritingIsTheOneSettingsShows() {
        Self.inADomainOfItsOwn { preferences, defaults in
            // Somebody turned the sounds off from the menu bar before there was
            // a Settings window. The window has to open on the switch they
            // moved, not on a second switch that happens to look like it.
            defaults.set(false, forKey: "CuesAreOn")

            #expect(preferences.areCuesOn() == false)
        }
    }
}
