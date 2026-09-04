import Foundation

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

    /// When the Hotkey went down, as the Clock read it.
    ///
    /// The one thing the core keeps of its own: the press has to be timed from
    /// somewhere, and reading the Clock at both ends is what lets the suite hold
    /// the key down for a second without waiting one.
    private var hotkeyPressedAt: Date?

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

    /// Starts watching for Activations, so that the Hotkey runs a Dictation
    /// while any other app has focus.
    ///
    /// Throwing means the Hotkey cannot be watched —
    /// `HotkeyFailure.accessibilityDenied` — which the app says out loud rather
    /// than leaving the user with a key that does nothing.
    public func watchForActivations() async throws {
        try await hotkey.observe { [weak self] gesture in
            await self?.activated(by: gesture)
        }
    }

    /// Takes a gesture from whoever is watching the keyboard, and times it.
    ///
    /// Timing it is the whole of what happens here. Whether a press this long
    /// was a tap or a Hold is the machine's to answer, and so is what either of
    /// them means for a Dictation — the core only says when the key went down
    /// and how long it stayed there.
    ///
    /// It does not throw where `receive(_:)` does, for the same reason `hear(_:)`
    /// does not: the keyboard has nowhere to put an error it was handed back
    /// between two Dictations, and the press that failed is already over. What
    /// the user is told about a Dictation that failed is the Clipboard Fallback
    /// ticket's.
    private func activated(by gesture: HotkeyEvent) async {
        switch gesture {
        case .pressed:
            hotkeyPressedAt = await clock.now()
            try? await receive(.hotkeyPressed)

        case .released:
            let heldFor = await lengthOfThePress()
            hotkeyPressedAt = nil
            try? await receive(.hotkeyReleased(heldFor: heldFor))

        case .pressSpoiled:
            let heldFor = await lengthOfThePress()
            hotkeyPressedAt = nil
            try? await receive(.hotkeyPressSpoiled(heldFor: heldFor))
        }
    }

    /// How long the Hotkey has been down.
    ///
    /// Nothing, where there is no press to measure — the key was already down
    /// when Cheppu started watching. The machine ignores a release it never saw
    /// begin in any case, so what this answers there does not decide anything.
    ///
    /// A Clock that has gone backwards between the two readings — the machine's
    /// own is stepped by NTP, not counted from a fixed point — is answered with
    /// the threshold rather than with a span that ran the wrong way, so the
    /// press reads as a Hold and the Dictation stops. A Dictation that ends a
    /// moment early costs the user a sentence; one that never ends leaves the
    /// microphone open on everything they say next.
    private func lengthOfThePress() async -> Duration {
        guard let hotkeyPressedAt else { return .zero }
        let heldFor = Duration.seconds(await clock.now().timeIntervalSince(hotkeyPressedAt))
        return heldFor < .zero ? DictationMachine.holdThreshold : heldFor
    }

    /// The one door into a Dictation.
    ///
    /// Runs the event through the machine, performs what it asks for, and keeps
    /// going for as long as a port reports something back — capture handing over
    /// what it heard, the Engine returning a Raw Transcript, an Insertion
    /// landing — so that one press of the Hotkey runs to the end of what it set
    /// in motion.
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

        case .noteTargetApp:
            return .targetAppNoted(await insertion.focusedApp())

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

        case .insert(let finalText, let targetApp):
            try await insertion.insert(finalText, into: targetApp)
            return .insertionSucceeded
        }
    }
}
