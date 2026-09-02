/// A Dictation, driven.
///
/// The core owns a `DictationMachine` and the ports, and is the only place the
/// two meet: it hands each event to the machine and carries out the effects the
/// machine answers with, in order, feeding back what a port reports so the
/// machine can decide what happens next.
///
/// It holds every port even where a later ticket is what will first use one, so
/// that the seam the app target wires itself into does not move underneath it.
public actor DictationCore {
    private var machine = DictationMachine()

    private let hotkey: any HotkeyPort
    private let audio: any AudioCapturePort
    private let engine: any EnginePort
    private let insertion: any InsertionPort
    private let clipboard: any ClipboardPort
    private let history: any HistoryPort
    private let feedback: any FeedbackPort
    private let clock: any ClockPort

    public init(
        hotkey: any HotkeyPort,
        audio: any AudioCapturePort,
        engine: any EnginePort,
        insertion: any InsertionPort,
        clipboard: any ClipboardPort,
        history: any HistoryPort,
        feedback: any FeedbackPort,
        clock: any ClockPort
    ) {
        self.hotkey = hotkey
        self.audio = audio
        self.engine = engine
        self.insertion = insertion
        self.clipboard = clipboard
        self.history = history
        self.feedback = feedback
        self.clock = clock
    }

    /// The one door into a Dictation.
    ///
    /// Runs the event through the machine, performs what it asks for, and keeps
    /// going for as long as a port reports something back — an Engine returning a
    /// Raw Transcript, an Insertion landing — so that one tap of the Hotkey runs
    /// to the end of what it set in motion.
    ///
    /// A port that throws stops the Dictation where it stands. Turning a failure
    /// into Clipboard Fallback, and telling the user about it, is the Clipboard
    /// Fallback ticket's job.
    public func receive(_ event: DictationEvent) async throws {
        var pending = [event]
        while !pending.isEmpty {
            for effect in machine.receive(pending.removeFirst()) {
                if let reported = try await perform(effect) {
                    pending.append(reported)
                }
            }
        }
    }

    /// Carries out one effect, and answers with what the port reported, if it
    /// reported anything the machine needs to hear about.
    private func perform(_ effect: DictationEffect) async throws -> DictationEvent? {
        switch effect {
        case .startCapturing:
            try await audio.startCapturing()
            return nil

        case .stopCapturingAndTranscribe:
            let spoken = try await audio.stopCapturing()
            return .rawTranscriptReceived(try await engine.transcribe(spoken))

        case .playCue(let cue):
            await feedback.play(cue)
            return nil

        case .showPill(let state):
            await feedback.showPill(state)
            return nil

        case .hidePill:
            await feedback.hidePill()
            return nil

        case .recordInHistory(let finalText):
            let entry = HistoryEntry(finalText: finalText, recordedAt: await clock.now())
            try await history.append(entry)
            return nil

        case .insert(let finalText):
            try await insertion.insert(finalText)
            return .insertionSucceeded
        }
    }
}
