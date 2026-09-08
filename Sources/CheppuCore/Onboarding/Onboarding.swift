/// How the Engine Download is going, as a first launch has to draw it.
///
/// Four answers, because the user is owed a different sentence for each: what
/// it will cost them before it starts, how far it has got while it runs, that
/// nothing was lost when it stops, and nothing at all once the Engine is here.
public enum EngineDownloadState: Equatable, Sendable {
    /// Nothing fetched, and nothing being fetched.
    ///
    /// Where a first launch opens: 600 MB over somebody else's connection is
    /// not something Cheppu starts on their behalf, and the one network path
    /// Cheppu has is one the user presses a button to open (ADR-0005).
    case notStarted

    /// Asked for, with nothing reported yet.
    ///
    /// Its own answer rather than a report of nothing, because a bar drawn from
    /// "0 of 0" is a bar that reads as finished, and one drawn from a total
    /// nobody has been told yet is a lie about a number the user is owed.
    case starting

    /// Arriving, with the bytes on both sides of it.
    case underWay(EngineDownloadProgress)

    /// The attempt ended before the Engine was here — the connection dropped,
    /// or the repository would not answer.
    ///
    /// What arrived stays on the machine, so this is a state to carry on from
    /// rather than a state to start over from. That is a property of the
    /// download itself rather than a promise made here.
    case interrupted

    /// Every file the Engine needs is on the machine.
    case finished
}

/// The first launch, which is the whole first impression
/// (`docs/product-experience.md` §12).
///
/// Three things have to be true before a Dictation can work — Cheppu may hear
/// the user, Cheppu may watch the keyboard and type where they are working, and
/// the Engine is on the machine — and none of them is worth anything until the
/// user has said one sentence and watched it appear. So the sequence is those
/// three and then that one, in that order, each on a screen of its own that
/// asks for one thing and says why in a sentence.
///
/// Which step the user is on is read off what is true this instant rather than
/// counted. A permission granted last week, an Engine that is already here, a
/// grant taken away halfway through and a relaunch in the middle of the
/// sequence all arrive at the same answer: the first thing that is not done
/// yet. There is nothing to keep in step, and nothing a user can be stranded
/// between.
///
/// Nothing here draws, prompts, opens a pane, fetches a byte or listens to
/// anybody — this describes the screen and the app performs it, exactly as
/// `SettingsScreen` and `MenuBarMenu` are performed.
public struct Onboarding: Equatable, Sendable {
    /// One thing a first launch has to get done, or the screen it ends on.
    public enum Step: Equatable, Sendable {
        /// A permission Cheppu cannot take for itself, named so that the
        /// sentence the user reads and the pane a button opens are about the
        /// same one.
        case permission(Permission)

        /// The Engine Download: the one time Cheppu uses the network.
        case engine

        /// One Dictation, into a field Cheppu owns.
        ///
        /// Last, and never skipped. Everything before it is a thing that might
        /// be true; this is the only one that proves the rest of them are.
        case practice

        /// The screen the sequence ends on. Not a step: there is nothing left
        /// for the user to do on it but read the key they dictate with and
        /// close the window.
        case done
    }

    /// The key the user dictates with. Named on the screens that ask for what
    /// it needs, and on the one that ends the sequence.
    public let hotkey: Hotkey

    /// Every step this user's first launch is made of, in the order they are
    /// walked.
    ///
    /// The permissions are the ones the chosen Hotkey actually needs and no
    /// others, exactly as they are in Settings: somebody dictating on the right
    /// Option key never sees Input Monitoring mentioned.
    public let steps: [Step]

    /// The step the user is on: the first one that is not done yet.
    public let step: Step

    private let engine: EngineDownloadState
    private let hasAskedForTheMicrophone: Bool

    /// Roughly what the Engine weighs, said before a byte of it is fetched.
    ///
    /// Approximate on purpose, and the only size the user is ever shown that
    /// Cheppu did not measure: the real total comes from the repository's own
    /// listing, and nobody has asked it yet at the moment this sentence is read.
    /// A user about to spend their bandwidth is owed a number before they press
    /// the button rather than after it, and every report from then on carries
    /// the measured one.
    static let engineWeighsAbout = "about 600 MB"

    /// - Parameters:
    ///   - hotkey: the key the user dictates with. It decides which permissions
    ///     the sequence asks for, and it is what the last screen names.
    ///   - permissions: what macOS says about each permission this instant. One
    ///     nobody has answered for counts as missing, exactly as it does in
    ///     Settings.
    ///   - hasAskedForTheMicrophone: whether Cheppu has already put the macOS
    ///     prompt in front of the user during this run. macOS shows it once and
    ///     answers from the decision on record ever afterwards, so a screen that
    ///     went on offering a prompt that will never appear again would be a
    ///     first launch nobody could get past.
    ///   - engine: how the Engine Download is going.
    ///   - hasDictated: whether the practice Dictation has landed — words
    ///     pasted into the field Cheppu owns, which is how an Insertion arrives
    ///     and is not how typing arrives.
    public init(
        hotkey: Hotkey,
        permissions: [Permission: PermissionStatus],
        hasAskedForTheMicrophone: Bool = false,
        engine: EngineDownloadState,
        hasDictated: Bool
    ) {
        self.hotkey = hotkey
        self.engine = engine
        self.hasAskedForTheMicrophone = hasAskedForTheMicrophone

        let needed = Permission.neededBy(hotkey)
        self.steps = needed.map(Step.permission) + [.engine, .practice]

        let missing = needed.first { (permissions[$0] ?? .notGranted) == .notGranted }
        self.step =
            if let missing {
                .permission(missing)
            } else if engine != .finished {
                .engine
            } else if !hasDictated {
                .practice
            } else {
                .done
            }
    }

    /// What the screen is headed with: what is being asked for, in the user's
    /// words rather than in macOS's.
    public var title: String {
        switch step {
        case .permission(.microphone): "Let Cheppu hear you"
        // Named for what the user gets rather than for what macOS calls it. The
        // permission's own name is in the sentence underneath and on the button.
        case .permission(.accessibility): "Let your hotkey work everywhere"
        case .permission(.inputMonitoring): "Let Cheppu see the Globe key"
        case .engine: "Put the engine on this Mac"
        case .practice: "Say something"
        case .done: "Cheppu is ready"
        }
    }

    /// Why, in the sentence the user reads before they act.
    ///
    /// The permissions say what `Settings` and the menu bar say, decided once
    /// where it was decided for them: a first launch that explained
    /// Accessibility differently from the alert a lost grant puts up would be
    /// two explanations to keep true.
    public var explanation: String {
        switch step {
        // The prompt has been shown and answered, and macOS will not show it
        // again. What is left is the pane, and saying so is the difference
        // between a screen that can be got past and one that cannot.
        case .permission(.microphone) where hasAskedForTheMicrophone:
            Permission.microphone.reason
                + " macOS keeps the answer you gave it, so this one is turned back on in "
                + "System Settings."
        case .permission(let permission):
            permission.whyItIsNeeded(toWatch: hotkey)
        case .engine:
            switch engine {
            case .notStarted:
                "Cheppu transcribes on this Mac, so the engine has to live here rather than on "
                    + "somebody's server. It is \(Self.engineWeighsAbout), fetched once, and it "
                    + "is the only thing Cheppu ever downloads."
            // Said before the first byte is counted, because this is also the
            // moment a second attempt starts from: what an interrupted one left
            // behind is picked up rather than fetched again.
            case .starting:
                "Starting the download. Anything an earlier attempt already left on this Mac is "
                    + "picked up rather than fetched twice."
            case .underWay(let progress):
                progress.howFarAlong
            case .interrupted:
                "The download stopped before the engine was here. Nothing that did arrive was "
                    + "lost, and carrying on picks it up from where it stopped."
            // Never read: the sequence has moved on to the practice Dictation by
            // the time this is true.
            case .finished:
                "The engine is on this Mac."
            }
        case .practice:
            "Press \(hotkey.name) and say a sentence — tap it to start and stop, or hold it "
                + "down and speak while you hold it. What you say goes into the box below and "
                + "nowhere else."
        case .done:
            "You dictate with \(hotkey.name). Press it in any app and what you say goes where "
                + "your cursor is."
        }
    }

    /// What the one button on the screen says, where the screen has one.
    ///
    /// Nothing, on the two screens where Cheppu is the one waiting: a download
    /// that is arriving, and a Dictation that has not been spoken yet. A button
    /// on either would be a second way to start something already started, or a
    /// way past the one thing the sequence exists to prove.
    public var action: String? {
        switch step {
        // The prompt, while there is still a prompt to show.
        case .permission(.microphone) where !hasAskedForTheMicrophone: "Allow Microphone"
        // Every other way a permission is granted is a switch in System
        // Settings, and Cheppu never leaves the user at its front door
        // (`docs/product-experience.md` §9).
        case .permission: "Open System Settings…"
        case .engine:
            switch engine {
            case .notStarted: "Download"
            case .starting, .underWay: nil
            // Not "Try Again": nothing is tried again. The bytes that arrived
            // are still on the machine and this asks for the rest of them.
            case .interrupted: "Resume"
            case .finished: nil
            }
        case .practice: nil
        case .done: "Done"
        }
    }

    /// Whether the Engine is arriving this instant.
    ///
    /// The screen has something moving on it for exactly as long as this is
    /// true, and nothing moving on it the rest of the time. Answered here
    /// rather than by whatever draws the bar, because "is there something to
    /// watch" is the same question as "is there anything to press", and the two
    /// answers have to agree.
    public var isFetchingTheEngine: Bool {
        guard case .engine = step else { return false }
        switch engine {
        case .starting, .underWay: return true
        case .notStarted, .interrupted, .finished: return false
        }
    }

    /// How far the download has got, where that is what the screen is about,
    /// and nothing while it is arriving and has not been counted yet.
    ///
    /// Bytes on both sides rather than a fraction alone, so that whatever draws
    /// a bar can also say the two numbers underneath it. Nothing beside
    /// `isFetchingTheEngine` is what a bar with nothing to measure looks like:
    /// it moves, because something is happening, and it does not claim a
    /// position it has not been told.
    public var progress: EngineDownloadProgress? {
        guard case .engine = step, case .underWay(let progress) = engine else { return nil }
        return progress
    }

    /// Whether the screen carries the field the practice Dictation goes into.
    ///
    /// It is on the last screen too, still holding what the user said: taking
    /// the words away the moment they arrived would be Cheppu showing somebody
    /// the one thing they came for and then clearing it.
    public var showsThePracticeField: Bool {
        switch step {
        case .practice, .done: true
        case .permission, .engine: false
        }
    }

    /// How far through the sequence the user is — "Step 2 of 4" — or nothing on
    /// the screen it ends on.
    ///
    /// A first launch with an end in sight is one somebody finishes. The count
    /// is of this user's steps rather than of a fixed four, because a Hotkey
    /// that needs a third permission is a sequence with one more thing in it.
    public var whereTheUserIs: String? {
        guard let index = steps.firstIndex(of: step) else { return nil }
        return "Step \(index + 1) of \(steps.count)"
    }
}
