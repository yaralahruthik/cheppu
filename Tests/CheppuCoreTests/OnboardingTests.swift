import Testing

@testable import CheppuCore

// The first launch, which is the whole first impression
// (`docs/product-experience.md` §12). What is asked for, in what order, what
// each screen says, and what is left to do — all of it read off what is true
// this instant, with nothing granted, nothing downloaded and nobody speaking.
@Suite("Onboarding")
struct OnboardingTests {
    private static func firstLaunch(
        hotkey: Hotkey = .byDefault,
        granted: Set<Permission> = [],
        hasAskedForTheMicrophone: Bool = false,
        engine: EngineDownloadState = .notStarted,
        hasDictated: Bool = false
    ) -> Onboarding {
        Onboarding(
            hotkey: hotkey,
            permissions: Permission.allCases.reduce(into: [:]) { statuses, permission in
                statuses[permission] = granted.contains(permission) ? .granted : .notGranted
            },
            hasAskedForTheMicrophone: hasAskedForTheMicrophone,
            engine: engine,
            hasDictated: hasDictated
        )
    }

    // MARK: - The order

    @Test("A first launch begins by asking to be heard")
    func aFirstLaunchBeginsByAskingToBeHeard() {
        #expect(Self.firstLaunch().step == .permission(.microphone))
    }

    @Test("Permissions come before the Engine, and the Engine before the first Dictation")
    func permissionsComeBeforeTheEngineAndTheEngineBeforeTheFirstDictation() {
        // The order is the whole of the sequence: a download the user watches
        // before they have granted anything is a download they wait through
        // twice, and a first Dictation before either is a Hotkey that does
        // nothing.
        #expect(
            Self.firstLaunch().steps == [
                .permission(.microphone), .permission(.accessibility), .engine, .practice,
            ]
        )
    }

    @Test("A permission already granted is not asked for again")
    func aPermissionAlreadyGrantedIsNotAskedForAgain() {
        // Somebody who granted the Microphone to a build they ran last week is
        // not walked through it a second time — the step is a thing that has to
        // be true, not a page to be turned.
        #expect(Self.firstLaunch(granted: [.microphone]).step == .permission(.accessibility))
    }

    @Test("A permission the chosen Hotkey does not need is never a step")
    func aPermissionTheChosenHotkeyDoesNotNeedIsNeverAStep() {
        // The same promise Settings makes: Cheppu asks for no permission the
        // key the user dictates with does not actually need.
        #expect(!Self.firstLaunch().steps.contains(.permission(.inputMonitoring)))

        let onTheGlobeKey = Self.firstLaunch(hotkey: .bareModifier(.function))
        #expect(onTheGlobeKey.steps.contains(.permission(.inputMonitoring)))
    }

    @Test("A launch halfway through opens where the user left off")
    func aLaunchHalfwayThroughOpensWhereTheUserLeftOff() {
        // Nothing is counted or remembered: the step is the first thing that is
        // not true yet, so a sequence interrupted by a restart carries on
        // rather than starting over.
        let afterTheGrants = Self.firstLaunch(granted: [.microphone, .accessibility])
        #expect(afterTheGrants.step == .engine)
    }

    @Test("An Engine already on the machine is not downloaded again")
    func anEngineAlreadyOnTheMachineIsNotDownloadedAgain() {
        let ready = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .finished)

        #expect(ready.step == .practice)
    }

    @Test("The sequence ends once the user has dictated once")
    func theSequenceEndsOnceTheUserHasDictatedOnce() {
        let done = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .finished, hasDictated: true)

        #expect(done.step == .done)
    }

    @Test("A permission taken away mid-sequence is asked for again")
    func aPermissionTakenAwayMidSequenceIsAskedForAgain() {
        // macOS tells nobody when a grant goes, and a first launch that carried
        // on to a practice Dictation it could not run would be the silence
        // `docs/product-experience.md` §9 rules out.
        let taken = Self.firstLaunch(granted: [.accessibility], engine: .finished)

        #expect(taken.step == .permission(.microphone))
    }

    // MARK: - What each screen says

    @Test("Every screen says what it is for and why, in words of its own")
    func everyScreenSaysWhatItIsForAndWhy() {
        let screens = [
            Self.firstLaunch(),
            Self.firstLaunch(granted: [.microphone]),
            Self.firstLaunch(granted: [.microphone, .accessibility]),
            Self.firstLaunch(granted: [.microphone, .accessibility], engine: .finished),
            Self.firstLaunch(
                granted: [.microphone, .accessibility], engine: .finished, hasDictated: true),
        ]

        for screen in screens {
            #expect(!screen.title.isEmpty)
            #expect(!screen.explanation.isEmpty)
        }
        // Five screens, five different things being asked of the user.
        #expect(Set(screens.map(\.title)).count == screens.count)
    }

    @Test("A permission screen offers the pane it is granted on")
    func aPermissionScreenOffersThePaneItIsGrantedOn() {
        // Accessibility has no prompt of its own — it is a switch in System
        // Settings — so a screen that only said why would be a dead end
        // (`docs/product-experience.md` §9).
        let accessibility = Self.firstLaunch(granted: [.microphone])

        #expect(accessibility.action == "Open System Settings…")
    }

    @Test("The Microphone is asked for with a prompt before it is asked for with a pane")
    func theMicrophoneIsAskedForWithAPromptBeforeAPane() {
        // macOS shows the prompt once. Until it has been shown, the button is
        // the prompt; afterwards it is the only place left where the answer can
        // be changed, and a screen still offering a prompt that will never
        // appear again is a first launch nobody can get past.
        #expect(Self.firstLaunch().action == "Allow Microphone")
        #expect(Self.firstLaunch(hasAskedForTheMicrophone: true).action == "Open System Settings…")
    }

    @Test("A refusal macOS will not ask about again says where the answer lives")
    func aRefusalMacOSWillNotAskAboutAgainSaysWhereTheAnswerLives() {
        let refused = Self.firstLaunch(hasAskedForTheMicrophone: true)

        #expect(refused.explanation.contains("System Settings"))
    }

    @Test("The screen that asks for a permission names the key the user chose")
    func theScreenThatAsksForAPermissionNamesTheKeyTheUserChose() {
        let onAChord = Self.firstLaunch(
            hotkey: .chord(Key(named: "D")!, with: [.leftControl, .leftOption]),
            granted: [.microphone]
        )

        #expect(onAChord.explanation.contains("⌃⌥D"))
    }

    // MARK: - The Engine Download

    @Test("Nothing is fetched until the user asks for it")
    func nothingIsFetchedUntilTheUserAsksForIt() {
        let engine = Self.firstLaunch(granted: [.microphone, .accessibility])

        // 600 MB over somebody else's connection is not something Cheppu starts
        // on their behalf, so the screen says what it weighs and waits.
        #expect(engine.action == "Download")
        #expect(engine.explanation.contains("600 MB"))
        #expect(engine.progress == nil)
    }

    @Test("A download under way says how much has arrived and how much there is")
    func aDownloadUnderWaySaysHowMuchHasArrivedAndHowMuchThereIs() {
        // A bare percentage reads the same whether the remainder is ten seconds
        // or ten minutes, which is how 600 MB comes to look like a stall.
        let arriving = EngineDownloadProgress(
            downloadedBytes: 212_000_000, totalBytes: 604_000_000)
        let engine = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .underWay(arriving))

        #expect(engine.progress == arriving)
        #expect(engine.isFetchingTheEngine)
        #expect(engine.explanation.contains("212 MB of 604 MB"))
        // Nothing to press: it is arriving, and a button would be a second way
        // to start what has already started.
        #expect(engine.action == nil)
    }

    @Test("A download with nothing counted yet is not a download that has finished")
    func aDownloadWithNothingCountedYetIsNotADownloadThatHasFinished() {
        // Nobody has asked the repository what the Engine weighs yet, so there
        // is no total to draw a bar from — and no button either, because the
        // download the button would start is already running.
        let starting = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .starting)

        #expect(starting.step == .engine)
        #expect(starting.progress == nil)
        #expect(starting.action == nil)
        // Something moving on the screen all the same, because something is
        // happening: a bar that claims no position is not a bar that has
        // stopped.
        #expect(starting.isFetchingTheEngine)
        // The resume is said here rather than only after a failure: the second
        // attempt at a 600 MB download opens on this screen.
        #expect(starting.explanation.contains("picked up rather than fetched twice"))
    }

    @Test("A download that stopped offers to carry on rather than to start again")
    func aDownloadThatStoppedOffersToCarryOn() {
        let interrupted = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .interrupted)

        #expect(interrupted.action == "Resume")
        // What arrived is still on the machine, and the sentence has to say so:
        // a user who thinks a dropped connection cost them what they had
        // already waited for closes the window. It says it without claiming
        // anything arrived, because on the attempt that never got a byte —
        // a repository that would not answer, an account with nowhere to keep
        // the Engine — nothing did.
        #expect(interrupted.explanation.contains("Nothing that did arrive was lost"))
        // Nothing to watch: an attempt that has stopped is not one that is
        // still arriving.
        #expect(!interrupted.isFetchingTheEngine)
    }

    @Test("There is nothing to watch on a screen that is not the download")
    func thereIsNothingToWatchOnAScreenThatIsNotTheDownload() {
        // The bar belongs to the one step that has something to measure.
        #expect(!Self.firstLaunch().isFetchingTheEngine)
        #expect(
            !Self.firstLaunch(granted: [.microphone, .accessibility], engine: .finished)
                .isFetchingTheEngine
        )
        // Nor before the user has asked for it.
        #expect(!Self.firstLaunch(granted: [.microphone, .accessibility]).isFetchingTheEngine)
    }

    // MARK: - The first Dictation, and the screen after it

    @Test("The screen asking for a Dictation names the key to press and waits")
    func theScreenAskingForADictationNamesTheKeyToPressAndWaits() {
        let practice = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .finished)

        #expect(practice.explanation.contains(Hotkey.byDefault.name))
        // The user's voice is the button. Anything to press here would be a way
        // past the one thing the sequence exists to prove.
        #expect(practice.action == nil)
        #expect(practice.showsThePracticeField)
    }

    @Test("The last screen names the Hotkey")
    func theLastScreenNamesTheHotkey() {
        // So that the user can dictate the moment they close the window, which
        // is the whole of what the last screen is for.
        let done = Self.firstLaunch(
            hotkey: .bareModifier(.rightCommand),
            granted: [.microphone, .accessibility],
            engine: .finished,
            hasDictated: true
        )

        #expect(done.explanation.contains("Right Command"))
        #expect(done.action == "Done")
    }

    @Test("The words the user just said are still on the last screen")
    func theWordsTheUserJustSaidAreStillOnTheLastScreen() {
        // Taking the field away the moment the words landed would be Cheppu
        // showing somebody the one thing they came for and then clearing it.
        let done = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .finished, hasDictated: true)

        #expect(done.showsThePracticeField)
    }

    // MARK: - How far there is to go

    @Test("Every screen but the last says how far along the user is")
    func everyScreenButTheLastSaysHowFarAlongTheUserIs() {
        #expect(Self.firstLaunch().whereTheUserIs == "Step 1 of 4")
        #expect(Self.firstLaunch(granted: [.microphone]).whereTheUserIs == "Step 2 of 4")
        #expect(
            Self.firstLaunch(granted: [.microphone, .accessibility], engine: .finished)
                .whereTheUserIs == "Step 4 of 4"
        )

        // Nothing on the last screen: there is nothing left to be part-way
        // through.
        let done = Self.firstLaunch(
            granted: [.microphone, .accessibility], engine: .finished, hasDictated: true)
        #expect(done.whereTheUserIs == nil)
    }

    @Test("A Hotkey that costs a third permission says so in the count")
    func aHotkeyThatCostsAThirdPermissionSaysSoInTheCount() {
        let onTheGlobeKey = Self.firstLaunch(hotkey: .bareModifier(.function))

        #expect(onTheGlobeKey.whereTheUserIs == "Step 1 of 5")
    }
}
