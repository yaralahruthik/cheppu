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
    case audioCaptured(CapturedAudio)
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
    case transcribe(CapturedAudio)
    case playCue(Cue)
    case showPill(PillState)
    case hidePill
    case recordInHistory(FinalText)
    case insert(FinalText)
}

/// The lifecycle of a Dictation, and the whole of Cheppu's decision-making.
///
/// Events in, effects out, and nothing else: no clock, no microphone, no Engine,
/// no pasteboard. That is what makes every rule about how a Dictation behaves
/// assertable as a list of effects, in order, with nothing granted or installed.
public struct DictationMachine: Sendable {
    private(set) var state: DictationState

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
        case (.idle, .activationStarted):
            state = .listening
            // Capture opens before the Cue plays: the sound is feedback, but a
            // word spoken before the microphone is open is gone.
            return [.startCapturing, .playCue(.dictationStarted), .showPill(.listening)]

        case (.listening, .activationStopped):
            state = .transcribing
            // The microphone closes first, so the stop Cue is not one of the
            // sounds the Engine is later asked to transcribe. The Pill says
            // "transcribing" before the Engine is asked, so the pause that
            // follows is never mistaken for a hang.
            return [.stopCapturing, .playCue(.dictationStopped), .showPill(.transcribing)]

        case (.transcribing, .audioCaptured(let audio)):
            return [.transcribe(audio)]

        case (.transcribing, .rawTranscriptReceived(let transcript)):
            // Cleanup stands between the Raw Transcript and the Final Text from
            // its own ticket onwards. Until then the words go in as heard.
            let finalText = FinalText(transcript.text)
            state = .inserting
            // History first, always: a crash during Insertion then costs the
            // user an inconvenience rather than the thing they said.
            return [.recordInHistory(finalText), .insert(finalText)]

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
