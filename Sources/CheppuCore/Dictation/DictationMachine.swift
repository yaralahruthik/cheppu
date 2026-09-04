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
/// reporting back what it was asked to do. Cancel, Discard and the Cap arrive
/// with their own tickets.
public enum DictationEvent: Equatable, Sendable {
    case activationStarted
    case activationStopped

    /// The Hotkey was tapped, which is a Toggle: it starts a Dictation when
    /// none is running and stops the one that is.
    ///
    /// One event rather than two because only the machine knows which of the
    /// two a tap means. A keyboard that decided for itself would have to keep a
    /// copy of whether a Dictation is running, and every way a Dictation ends
    /// without the Hotkey — the Cap, a Cancel, a failure — would leave that
    /// copy wrong and the next tap doing the opposite of what the user meant.
    case activationToggled

    /// Who had focus at the moment the Dictation stopped, which is who the
    /// Insertion is for. Nothing, where no app had focus at all.
    case targetAppNoted(TargetApp?)

    case audioCaptured(CapturedAudio)
    case inputLevelChanged(InputLevel)
    case rawTranscriptReceived(RawTranscript)
    case insertionSucceeded

    /// A port could not do what it was asked.
    ///
    /// Which port, and what the user is told about it, is the Clipboard Fallback
    /// ticket's. All this event settles is that a Dictation always has a way
    /// back to Idle, so a failure costs the user one Dictation and not the app.
    case dictationFailed
}

/// Something the machine has decided should happen.
///
/// An effect is a decision, not a doing: `DictationCore` is the only thing that
/// turns one into a call on a port.
public enum DictationEffect: Equatable, Sendable {
    case startCapturing
    case stopCapturing

    /// Ask who has focus, so that the Insertion has somewhere to go once the
    /// Engine is done.
    case noteTargetApp

    case transcribe(CapturedAudio)
    case playCue(Cue)
    case showPill(PillState)
    case hidePill
    case recordInHistory(FinalText)
    case insert(FinalText, into: TargetApp)
}

/// The lifecycle of a Dictation, and the whole of Cheppu's decision-making.
///
/// Events in, effects out, and nothing else: no clock, no microphone, no Engine,
/// no pasteboard. That is what makes every rule about how a Dictation behaves
/// assertable as a list of effects, in order, with nothing granted or installed.
public struct DictationMachine: Sendable {
    private(set) var state: DictationState

    /// Who this Dictation is for, from the moment it stopped. Held here rather
    /// than looked up again when the words are ready, because by then the user
    /// may be somewhere else and the answer would be the wrong app.
    private var targetApp: TargetApp?

    public init() {
        self.state = .idle
    }

    /// Takes an event and answers with what should happen, in the order it
    /// should happen.
    ///
    /// An event the current state has no answer for changes nothing and produces
    /// nothing. A stray tap of the Hotkey, or a port reporting late, must not be
    /// able to derail a Dictation.
    public mutating func receive(_ event: DictationEvent) -> [DictationEffect] {
        switch (state, event) {
        case (.idle, .activationStarted), (.idle, .activationToggled):
            state = .listening
            // Nothing carried over from the Dictation before this one: the app
            // that received the last Insertion must never receive this one by
            // default.
            targetApp = nil
            // Capture opens before the Cue plays: the sound is feedback, but a
            // word spoken before the microphone is open is gone.
            return [.startCapturing, .playCue(.dictationStarted), .showPill(.listening(.silent))]

        case (.listening, .activationStopped), (.listening, .activationToggled):
            state = .transcribing
            // Who has focus is read first and at once: it is the definition of
            // the Target App, and everything after this — closing the
            // microphone, the Cue — takes long enough for the user to have
            // clicked into another window.
            //
            // The microphone closes before the stop Cue plays, so the Cue is
            // not one of the sounds the Engine is later asked to transcribe.
            // The Pill says "transcribing" before the Engine is asked, so the
            // pause that follows is never mistaken for a hang.
            return [
                .noteTargetApp, .stopCapturing, .playCue(.dictationStopped),
                .showPill(.transcribing),
            ]

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
            // Cleanup stands between the Raw Transcript and the Final Text from
            // its own ticket onwards. Until then the words go in as heard.
            let finalText = FinalText(transcript.text)

            // Nothing had focus when the Dictation stopped, so there is nowhere
            // for the words to be typed. They are still the user's — History is
            // written all the same — and the Dictation ends rather than waiting
            // for an Insertion that cannot come. Saying so out loud, and
            // leaving the text on the clipboard, is #14's.
            guard let targetApp else {
                state = .idle
                return [.recordInHistory(finalText), .hidePill]
            }

            state = .inserting
            // History first, always: a crash during Insertion then costs the
            // user an inconvenience rather than the thing they said.
            return [
                .recordInHistory(finalText),
                .insert(finalText.normalisedForInsertion, into: targetApp),
            ]

        case (.inserting, .insertionSucceeded):
            state = .idle
            // The text appearing is the signal that it worked, so the Pill's
            // last job is to get out of the way.
            return [.hidePill]

        case (.listening, .dictationFailed), (.transcribing, .dictationFailed),
            (.inserting, .dictationFailed):
            state = .idle
            return [.hidePill]

        default:
            return []
        }
    }
}
