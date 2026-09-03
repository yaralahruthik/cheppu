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

    /// Events waiting their turn. One Dictation's effects are carried out in
    /// order and to the end before the next event is looked at, because the
    /// order the ports are called in is the order the user experiences.
    private var queued: [DictationEvent] = []
    private var isDraining = false

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

    /// Starts watching for Activations, so that a tap of the Hotkey runs a
    /// Dictation while any other app has focus.
    ///
    /// Throwing means the Hotkey cannot be watched —
    /// `HotkeyFailure.accessibilityDenied` — which the app says out loud rather
    /// than leaving the user with a key that does nothing.
    ///
    /// The app cannot call this yet, because a core needs an Insertion for a
    /// Dictation to end in and that is #7. Until then it watches the Hotkey
    /// itself, for the Accessibility half of this, and the suite is what drives
    /// a Dictation from a tap.
    public func watchForActivations() async throws {
        try await hotkey.observe { [weak self] gesture in
            await self?.activated(by: gesture)
        }
    }

    /// Takes a gesture from whoever is watching the keyboard.
    ///
    /// It does not throw where `receive(_:)` does, for the same reason `hear(_:)`
    /// does not: the keyboard has nowhere to put an error it was handed back
    /// between two Dictations, and the tap that failed is already over. What
    /// the user is told about a Dictation that failed is the Clipboard Fallback
    /// ticket's.
    private func activated(by gesture: HotkeyEvent) async {
        switch gesture {
        case .tapped:
            try? await receive(.activationToggled)
        }
    }

    /// The one door into a Dictation.
    ///
    /// Runs the event through the machine, performs what it asks for, and keeps
    /// going for as long as a port reports something back — capture handing over
    /// what it heard, the Engine returning a Raw Transcript, an Insertion
    /// landing — so that one tap of the Hotkey runs to the end of what it set in
    /// motion.
    ///
    /// An event that arrives while an earlier one is still being carried out
    /// waits its turn rather than interleaving with it, and returns once queued.
    ///
    /// A port that throws ends that Dictation: the Pill comes down, the machine
    /// returns to Idle, and the error is passed on. Turning the failure into
    /// Clipboard Fallback, and telling the user about it, is the Clipboard
    /// Fallback ticket's job.
    public func receive(_ event: DictationEvent) async throws {
        queued.append(event)
        guard !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        do {
            while !queued.isEmpty {
                for effect in machine.receive(queued.removeFirst()) {
                    if let reported = try await perform(effect) {
                        queued.append(reported)
                    }
                }
            }
        } catch {
            queued.removeAll()
            // Nothing on the way back to Idle can fail — the Pill only has to
            // come down — but a second failure while unwinding the first has
            // nowhere useful to go, and losing the app to it would be worse than
            // losing the Dictation.
            for effect in machine.receive(.dictationFailed) {
                _ = try? await perform(effect)
            }
            throw error
        }
    }

    /// Takes a level from whoever is holding the microphone.
    ///
    /// It does not throw where `receive(_:)` does, because the microphone has
    /// nowhere to put an error it was handed back mid-Dictation, and because
    /// nothing a level sets in motion can fail: the Pill is the whole of it.
    private func hear(_ level: InputLevel) async {
        try? await receive(.inputLevelChanged(level))
    }

    /// Carries out one effect, and answers with what the port reported, if it
    /// reported anything the machine needs to hear about.
    private func perform(_ effect: DictationEffect) async throws -> DictationEvent? {
        switch effect {
        case .startCapturing:
            // The level arrives many times over one Dictation, so it comes back
            // through the same door every other event does rather than being
            // handed to the Pill behind the machine's back. That is what makes
            // a level heard after the microphone closed a decision the machine
            // gets to ignore.
            try await audio.startCapturing { [weak self] level in
                await self?.hear(level)
            }
            return nil

        case .stopCapturing:
            return .audioCaptured(try await audio.stopCapturing())

        case .transcribe(let spoken):
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
