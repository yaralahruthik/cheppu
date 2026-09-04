/// Where a Dictation has got to.
///
/// These are the four states the user cares about and nothing else. A state the
/// user cannot tell apart from another does not belong here.
public enum DictationState: Equatable, Sendable {
    /// Nothing is running. Where Cheppu waits, and where every Dictation ends.
    case idle

    /// The microphone is open and the user is speaking.
    case listening

    /// The user has finished and the Engine is working on what it heard.
    case transcribing

    /// The Final Text is on its way to the Target App.
    case inserting
}

/// Something that happened to a Dictation.
///
/// Some come from the user by way of the Hotkey port; the rest are a port
/// reporting back what it was asked to do.
public enum DictationEvent: Equatable, Sendable {
    /// The Hotkey went down on its own.
    ///
    /// A Dictation starts here rather than on the way back up, so that the
    /// quarter of a second spent deciding whether this is a Toggle or a Hold is
    /// spent with the microphone already open. Someone who holds the key starts
    /// speaking as they press it, and the threshold must not cost them the
    /// first word of it.
    ///
    /// A Dictation already running stops here too, and for the opposite reason:
    /// there is nothing left to find out. The user has finished speaking, so
    /// waiting for the key to come up would be latency spent on a question
    /// already answered.
    case hotkeyPressed

    /// The Hotkey came back up, having been held this long.
    ///
    /// How long is the whole of the difference between the two Activations, and
    /// it is measured rather than chosen: let go inside `holdThreshold` and the
    /// press was a tap, which leaves a Toggle Dictation running until the next
    /// tap; held past it and letting go is the end of a Hold. So there is no
    /// setting and no mode — the same key does the obvious thing both ways.
    ///
    /// The core reads the Clock at both ends and hands the span over, so that
    /// nothing in here has to know what time it is.
    case hotkeyReleased(heldFor: Duration)

    /// The press turned out to be typing: a key was struck, or another modifier
    /// joined it, while the Hotkey was down.
    ///
    /// The Hotkey is a bare modifier — right Option types an accented character
    /// on several layouts — so a Dictation begun on the way down has to be
    /// something Cheppu can hand back. Nothing the user typed is Cheppu's
    /// business, and neither is what the microphone happened to hear while they
    /// typed it.
    ///
    /// It carries how long the key had been down for the same reason a release
    /// does, and it is the same measurement: a press spoiled inside
    /// `holdThreshold` was someone typing an é, and one spoiled after it was
    /// someone three seconds into a Hold who brushed a key. Only the first is
    /// handed back.
    ///
    /// Nothing follows this. A spoiled press is never reported released, so a
    /// Dictation left running here would be one nothing could end.
    case hotkeyPressSpoiled(heldFor: Duration)

    /// Escape, wherever the user pressed it.
    ///
    /// It means Cancel while a Dictation is Listening and nothing at all at
    /// every other moment, which is why every Escape is reported and the
    /// machine decides what it meant. The key itself is never taken from the
    /// app the user is typing in: Cheppu can read a keystroke and cannot
    /// swallow one (ADR-0006), so an Escape that Cancels a Dictation also does
    /// whatever Escape does where they are.
    case escapePressed

    /// Five minutes of this Dictation have gone by.
    ///
    /// The Cap, and the only thing other than the user that ever ends a
    /// Dictation they meant. What was said is transcribed and kept: someone who
    /// walked away has not asked for their afternoon to be recorded, and
    /// someone mid-paragraph has not asked to lose it.
    case capReached

    /// Who had focus at the moment the Dictation stopped, which is who the
    /// Insertion is for. Nothing, where no app had focus at all.
    case targetAppNoted(TargetApp?)

    case audioCaptured(CapturedAudio)
    case inputLevelChanged(InputLevel)
    case rawTranscriptReceived(RawTranscript)
    case insertionSucceeded

    /// The Final Text did not land: the Target App would not take it, the user
    /// moved on while the Engine was working, or the Accessibility that types
    /// the paste was taken away mid-session.
    ///
    /// One event for all of them, because the answer to all of them is the
    /// same: the words go on the clipboard and the Pill says so. Why it did not
    /// land changes nothing the user can act on — what they do next is paste —
    /// and a Dictation that read differently depending on which refusal it met
    /// would be three failures to learn instead of one.
    ///
    /// It is not a `dictationFailed`. The Dictation ends with what was said
    /// somewhere the user can get it, which is the whole of what
    /// `docs/product-experience.md` §4 asks of it.
    case insertionFailed

    /// The notice has been up long enough to have been read.
    ///
    /// The Clock says so, on the way out of a Clipboard Fallback, because the
    /// Pill saying where the words went is the one thing on screen that is
    /// read rather than glanced at.
    case noticeRead

    /// A port could not do what it was asked.
    ///
    /// Which port is not in here, and neither is what the user is told: this is
    /// every failure that is not an Insertion, and there is nothing useful to
    /// say about a microphone that would not open or an Engine that would not
    /// answer beyond ending the Dictation. All this event settles is that a
    /// Dictation always has a way back to Idle, so a failure costs the user one
    /// Dictation and not the app.
    case dictationFailed
}

/// Something the machine has decided should happen.
///
/// An effect is a decision, not a doing: `DictationCore` is the only thing that
/// turns one into a call on a port.
public enum DictationEffect: Equatable, Sendable {
    case startCapturing
    case stopCapturing

    /// Start the five minutes at the end of which a Dictation stops itself.
    ///
    /// The waiting belongs to the Clock rather than to the machine or the core,
    /// so that nothing in Cheppu holds a timer of its own and the suite can
    /// reach the Cap without waiting five minutes for it.
    case startTheCap

    /// Call the Cap off, because the Dictation it was counting for has stopped
    /// Listening. Decided on every way out, so that one Dictation's five
    /// minutes can never end over the top of the next one.
    case stopTheCap

    /// Ask who has focus, so that the Insertion has somewhere to go once the
    /// Engine is done.
    case noteTargetApp

    case transcribe(CapturedAudio)
    case playCue(Cue)
    case showPill(PillState)
    case hidePill
    case recordInHistory(FinalText)
    case insert(FinalText, into: TargetApp)

    /// Leave the words on the clipboard, for the user to paste where Cheppu
    /// could not type them.
    ///
    /// The one thing Cheppu ever puts on the user's clipboard and does not take
    /// back off it. What they had copied is gone, which is the deliberate cost
    /// of a Dictation that would otherwise be nowhere they could reach.
    case leaveOnTheClipboard(FinalText)

    /// Keep the notice on screen for as long as it takes to read, and then take
    /// the Pill down.
    ///
    /// The waiting belongs to the Clock, exactly as the Cap's does: nothing in
    /// Cheppu holds a timer of its own, and a suite that had to wait out the
    /// notice would be a suite that waited.
    case leaveTheNoticeUp
}

/// The lifecycle of a Dictation, and the whole of Cheppu's decision-making.
///
/// Events in, effects out, and nothing else: no clock, no microphone, no Engine,
/// no pasteboard. That is what makes every rule about how a Dictation behaves
/// assertable as a list of effects, in order, with nothing granted or installed.
public struct DictationMachine: Sendable {
    /// How long the Hotkey has to be held for letting go of it to stop the
    /// Dictation rather than leave it running.
    ///
    /// A fixed constant rather than a setting (#1). It is the only thing
    /// telling Toggle and Hold apart, and a number the user could move would
    /// turn one key doing the obvious thing into two gestures they have to keep
    /// in mind.
    ///
    /// A quarter of a second is longer than anyone's tap and shorter than
    /// anyone's press, so neither gesture has to be performed carefully to be
    /// read correctly.
    public static let holdThreshold: Duration = .milliseconds(250)

    /// How long one Dictation may run before it stops itself.
    ///
    /// A fixed constant rather than a setting (#1), and long enough that nobody
    /// dictating a paragraph ever meets it: five minutes is a Dictation that
    /// has been left running rather than one being spoken into.
    public static let cap: Duration = .seconds(5 * 60)

    /// How long the Clipboard Fallback's notice stays on screen.
    ///
    /// Long enough to be read out of the corner of an eye that was on the work
    /// and did not expect to be interrupted, and short enough that the Pill is
    /// gone before the user's next Dictation. It says where the words are; the
    /// words themselves stay on the clipboard, and in History, long after it
    /// has gone.
    public static let longEnoughToReadTheNotice: Duration = .seconds(5)

    /// The Cleanup this Dictation's words go through on their way to the
    /// Target App.
    ///
    /// Held here rather than reached for, because which rules are on is the
    /// user's and not the machine's: the app hands it whichever switches the
    /// Settings window (#15) is showing, and the machine applies them.
    private let cleanup: Cleanup

    private(set) var state: DictationState

    /// Whether the press currently holding the Hotkey down is the one that
    /// opened the Dictation that is running.
    ///
    /// The only thing letting go of the key needs to know, and the one thing
    /// the keyboard cannot tell it: whether a Dictation was already running
    /// when the key went down. A keyboard keeping its own copy of that would be
    /// wrong the moment a Dictation ended without it — a failure, a Cancel, the
    /// Cap — and the user's next press would do the opposite of what they
    /// meant.
    ///
    /// False for a press that came down on a Dictation already running, for one
    /// that turned out to be typing, and for one that was already down when
    /// Cheppu started watching. None of those has anything left to decide on
    /// the way up.
    private var thisPressOpenedTheDictation = false

    /// Who this Dictation is for, from the moment it stopped. Held here rather
    /// than looked up again when the words are ready, because by then the user
    /// may be somewhere else and the answer would be the wrong app.
    private var targetApp: TargetApp?

    /// The words this Dictation handed to the Insertion, while it is being
    /// carried out.
    ///
    /// Kept because what could not be typed is what is left to paste: the
    /// Clipboard Fallback leaves exactly the text the Target App was offered,
    /// trimmed and — where that app is a Terminal — with its Paragraph Breaks
    /// already flattened (#12). The user's next keystroke pastes it into the
    /// same window the Insertion was for, so a newline that was not safe to
    /// type there is not safe to leave there either.
    private var handedToInsertion: FinalText?

    /// - Parameter rules: which Cleanup rules a Dictation's words go through.
    ///   Every rule on unless the user has turned one off.
    public init(cleaningWith rules: CleanupRules = .all) {
        self.state = .idle
        self.cleanup = Cleanup(rules)
    }

    /// Takes an event and answers with what should happen, in the order it
    /// should happen.
    ///
    /// An event the current state has no answer for changes nothing and produces
    /// nothing. A stray press of the Hotkey, or a port reporting late, must not
    /// be able to derail a Dictation.
    public mutating func receive(_ event: DictationEvent) -> [DictationEffect] {
        switch (state, event) {
        case (.idle, .hotkeyPressed):
            state = .listening
            thisPressOpenedTheDictation = true
            // Nothing carried over from the Dictation before this one: the app
            // that received the last Insertion must never receive this one by
            // default, and neither must its words.
            targetApp = nil
            handedToInsertion = nil
            // Capture opens before the Cue plays: the sound is feedback, but a
            // word spoken before the microphone is open is gone. The Cap starts
            // with the microphone, so that its five minutes are five minutes of
            // audio rather than of whatever else a Dictation does first.
            return [
                .startCapturing, .startTheCap, .playCue(.dictationStarted),
                .showPill(.listening(.silent)),
            ]

        case (.listening, .hotkeyPressed):
            // A Dictation is already running, so this press is the second tap
            // of a Toggle, and the Dictation stops here rather than when the
            // key comes back up.
            //
            // On the way down for two reasons. The user has finished speaking,
            // so every millisecond between the press and the words appearing is
            // spent from the latency budget (`docs/product-experience.md` §7).
            // And a press that stopped nothing until it was let go of could
            // fail to stop anything at all: type with the key still down and
            // the press is spoiled, no release is ever reported, and the
            // Dictation would go on listening to everything typed after it.
            //
            // The cost is that pressing the Hotkey to type an accented
            // character mid-Dictation stops the Dictation. That is the
            // documented meaning of the key while one is running, and the words
            // are transcribed and kept rather than lost.
            return stopListening()

        case (.listening, .hotkeyReleased(let heldFor)):
            // A release of a press that did not open this Dictation is nothing
            // to it: the key was already down when Cheppu started watching, or
            // what the user did with it turned out to be typing.
            guard thisPressOpenedTheDictation else { return [] }
            thisPressOpenedTheDictation = false

            // Let go inside the threshold and the press was a tap, which leaves
            // the Dictation running until the next press — the whole of Toggle.
            // Held past it, letting go is the end of a Hold.
            guard heldFor >= Self.holdThreshold else { return [] }
            return stopListening()

        case (.listening, .hotkeyPressSpoiled(let heldFor)):
            guard thisPressOpenedTheDictation else {
                // A press that did not open this Dictation, so what it turned
                // into has nothing to do with it.
                return []
            }
            thisPressOpenedTheDictation = false

            guard heldFor < Self.holdThreshold else {
                // Past the threshold the press is a Hold, and the user has been
                // speaking into it. A key brushed at three seconds does not
                // throw that away — audio is effort they cannot repeat
                // (`docs/product-experience.md` §4) — so the Dictation ends
                // here exactly as a Hold ends, and the words are transcribed
                // and kept. It has to end here rather than wait for the key,
                // because a spoiled press is never reported released.
                return stopListening()
            }
            // This Dictation only ever existed because of a press that turns
            // out to have been an é. It is handed back where it stands: the
            // microphone closes, what it heard is let go of rather than
            // transcribed, and the Pill comes down.
            //
            // No stop Cue answers the start Cue that has already played, which
            // is the one place Cheppu leaves `docs/product-experience.md` §3's
            // pair unmatched. It is the least bad of three: a stop Cue would
            // say a Dictation had been taken and is being transcribed, which is
            // the more misleading sound of the two, and holding the start Cue
            // back until the threshold had passed would cost every real
            // Dictation the confirmation it exists to give the instant the key
            // goes down.
            return handBackTheDictation() + [.hidePill]

        case (.listening, .escapePressed):
            // Cancel. The user misspoke, or thought better of it: the whole
            // Dictation is thrown away where it stands. The microphone closes,
            // what it heard is let go of rather than transcribed, and nothing
            // is inserted or kept.
            //
            // It is answered with a Cue of its own, which is the whole of what
            // tells Cancel from Discard from outside Cheppu. The user did this
            // on purpose with their eyes on their work
            // (`docs/product-experience.md` §3), and Escape is not taken from
            // the app they are in (ADR-0006), so silence would leave them with
            // no way of knowing Cheppu heard it. The stop Cue would be worse
            // than silence: it says the words are on their way.
            return handBackTheDictation() + [.playCue(.dictationCancelled), .hidePill]

        case (.listening, .capReached):
            // Five minutes, and the user has not come back. The Dictation ends
            // exactly as it would have had they ended it themselves, and what
            // they did say is transcribed and kept: a forgotten Toggle is
            // someone who walked away, not someone who wanted their words
            // thrown away.
            return stopListening()

        case (.transcribing, .targetAppNoted(let app)):
            targetApp = app
            return []

        case (.listening, .inputLevelChanged(let level)):
            // Only while Listening. The last buffer the microphone heard can
            // land after it was closed, and a Pill that flicked back to
            // Listening over a Dictation already being transcribed would say
            // the one thing the two states exist to tell apart.
            return [.showPill(.listening(level))]

        case (.transcribing, .audioCaptured(let audio)):
            return [.transcribe(audio)]

        case (.transcribing, .rawTranscriptReceived(let transcript)):
            // Cleanup stands between the Raw Transcript and the Final Text, and
            // is the only thing that does: there is one Final Text, and History
            // and the Target App are given the same one.
            let finalText = cleanup.finalText(from: transcript)

            // Discard. The Engine heard no words in this Dictation, so there is
            // nothing to insert and nothing worth keeping, and it ends without
            // saying anything about it: a Hotkey tapped by accident must litter
            // neither the user's document nor their History.
            //
            // Measured on what would have been inserted rather than on what the
            // Engine handed back, because a Dictation with no speech in it
            // comes back as a space and a newline as often as it comes back
            // empty, and inserting those would be a stray tap that moved the
            // user's cursor. Measured after Cleanup for the same reason: a
            // Dictation that was one clearing of the throat has nothing in it
            // once the filler is gone.
            guard !finalText.normalisedForInsertion.text.isEmpty else {
                state = .idle
                return [.hidePill]
            }

            // Nothing had focus when the Dictation stopped, so there is nowhere
            // for the words to be typed. They are still the user's — History is
            // written all the same — and rather than waiting for an Insertion
            // that cannot come, the Dictation ends the way every Insertion that
            // does not land ends: on the clipboard, and said out loud.
            guard let targetApp else {
                return [.recordInHistory(finalText)]
                    + leaveOnTheClipboard(finalText.normalisedForInsertion)
            }

            state = .inserting
            // History first, always: a crash during Insertion then costs the
            // user an inconvenience rather than the thing they said.
            //
            // History is given the Final Text and the Target App a version of it
            // shaped for where it is going — trimmed, and with its Paragraph
            // Breaks flattened where that is a Terminal (#12). What is kept is
            // what was said; what is typed is what is safe to type there — and,
            // where it cannot be typed at all, what is left to paste.
            let asItWouldBeTyped = finalText.normalisedForInsertion(into: targetApp)
            handedToInsertion = asItWouldBeTyped
            return [.recordInHistory(finalText), .insert(asItWouldBeTyped, into: targetApp)]

        case (.inserting, .insertionSucceeded):
            state = .idle
            handedToInsertion = nil
            // The text appearing is the signal that it worked, so the Pill's
            // last job is to get out of the way.
            return [.hidePill]

        case (.inserting, .insertionFailed):
            // The Clipboard Fallback. The words could not be typed — the app
            // refused them, the user moved on, or the grant that types the
            // paste was taken away — so they are left where the user can put
            // them where they were going themselves.
            //
            // The words are already in History, written before the Insertion
            // was tried, so this is where they can be reached rather than the
            // only place they exist.
            guard let handedToInsertion else {
                // Unreachable: nothing enters Inserting without handing the
                // Insertion its words. Ending the Dictation is still better
                // than leaving a Pill up over a state that cannot happen.
                state = .idle
                return [.hidePill]
            }
            return leaveOnTheClipboard(handedToInsertion)

        case (.idle, .noticeRead):
            // The notice has been up long enough. The Pill's last job, as
            // always, is to get out of the way.
            //
            // Only from Idle. A Dictation started while the notice was up owns
            // the Pill now, and the notice it replaced must not be what takes
            // it down. The Clock cannot deliver this late in any case — the
            // next Dictation's Cap calls the wait off as it starts — so this is
            // belt as well as braces.
            return [.hidePill]

        case (.listening, .dictationFailed):
            state = .idle
            // Whatever the Hotkey is doing belongs to a Dictation that is over.
            // Letting go of it must not stop the next one.
            thisPressOpenedTheDictation = false
            // The microphone never opened, or stopped being able to hear, so
            // there is no Dictation left for the Cap to be counting for.
            return [.stopTheCap, .hidePill]

        case (.transcribing, .dictationFailed), (.inserting, .dictationFailed):
            state = .idle
            thisPressOpenedTheDictation = false
            handedToInsertion = nil
            return [.hidePill]

        case (.idle, .dictationFailed):
            // A Dictation that had already finished deciding when one of the
            // things it decided went wrong: the machine returns to Idle before
            // the last effects of a Dictation are carried out — writing
            // History, and taking the Pill down — so a failure among them
            // arrives here rather than in one of the three states above.
            //
            // The Pill is taken down again. It costs nothing where it is
            // already down, and where it is not it is the difference between a
            // Dictation the user watched fail and a Pill left on their screen
            // with nothing left running to take it away.
            return [.hidePill]

        default:
            return []
        }
    }

    /// Ends the Dictation with its words on the clipboard and the Pill saying
    /// so: the Clipboard Fallback, whichever way the Insertion failed to happen.
    ///
    /// The clipboard is written before the notice goes up, so that a user who
    /// reads it and pastes at once finds the words already there. The notice
    /// then stays up rather than the Pill coming down, because "done" is
    /// signalled by the text appearing (`docs/product-experience.md` §3) and
    /// here it did not appear: a Pill that vanished would say the Dictation
    /// worked.
    ///
    /// What was on the clipboard before is not put back. Everywhere else Cheppu
    /// borrows the pasteboard and gives it back (§5); here it deliberately
    /// keeps it, because the alternative is a Dictation the user cannot reach
    /// from anywhere but History.
    private mutating func leaveOnTheClipboard(_ finalText: FinalText) -> [DictationEffect] {
        state = .idle
        handedToInsertion = nil
        return [.leaveOnTheClipboard(finalText), .showPill(.onTheClipboard), .leaveTheNoticeUp]
    }

    /// Hands back the Dictation that is Listening without transcribing it.
    ///
    /// The other end of `stopListening()`, and the whole of what Cancel and a
    /// press that turned out to be typing have in common: the microphone
    /// closes, what it heard goes nowhere, and the Cap stops counting for a
    /// Dictation that is over. Nobody is asked who has focus, because nothing
    /// is going anywhere.
    ///
    /// What the user is told about it is the caller's, and it is the only
    /// difference between the two: Cancel is answered out loud because they
    /// asked for it, and a press that was really an é is taken back in silence
    /// because they never asked for anything.
    private mutating func handBackTheDictation() -> [DictationEffect] {
        state = .idle
        thisPressOpenedTheDictation = false
        return [.stopCapturing, .stopTheCap]
    }

    /// Ends the Dictation that is Listening, whatever ended it: either
    /// Activation, a press spoiled deep into a Hold, or the Cap.
    ///
    /// Who has focus is read first and at once: it is the definition of the
    /// Target App, and everything after this — closing the microphone, the Cue
    /// — takes long enough for the user to have clicked into another window.
    ///
    /// The microphone closes before the stop Cue plays, so the Cue is not one of
    /// the sounds the Engine is later asked to transcribe. The Pill says
    /// "transcribing" before the Engine is asked, so the pause that follows is
    /// never mistaken for a hang.
    private mutating func stopListening() -> [DictationEffect] {
        state = .transcribing
        // Whatever the Hotkey is doing from here belongs to a Dictation that
        // has stopped Listening — a key still held five minutes into a Hold the
        // Cap has just ended, say. Letting go of it must not stop the next one.
        thisPressOpenedTheDictation = false
        return [
            .noteTargetApp, .stopCapturing, .stopTheCap, .playCue(.dictationStopped),
            .showPill(.transcribing),
        ]
    }
}
