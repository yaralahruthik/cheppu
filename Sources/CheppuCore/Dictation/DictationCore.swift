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
    private var machine: DictationMachine

    /// Events waiting their turn. One Dictation's effects are carried out in
    /// order and to the end before the next event is looked at, because the
    /// order the ports are called in is the order the user experiences.
    private var queued: [DictationEvent] = []
    private var isDraining = false

    private let hotkey: any HotkeyPort
    private let cleanup: any CleanupSwitches
    private let audio: any AudioCapturePort
    private let engine: any EnginePort
    private let insertion: any InsertionPort
    private let clipboard: any ClipboardPort
    private let history: any HistoryPort
    private let feedback: any FeedbackPort
    private let permissions: any PermissionPort
    private let clock: any ClockPort
    private let diagnostics: any DiagnosticsPort

    /// When the Hotkey went down, as the Clock read it.
    ///
    /// The one thing the core keeps of its own: the press has to be timed from
    /// somewhere, and reading the Clock at both ends is what lets the suite hold
    /// the key down for a second without waiting one.
    private var hotkeyPressedAt: Date?

    /// - Parameter cleanup: which Cleanup rules a Dictation's words go through
    ///   on their way to the Target App. A port rather than a value, so that a
    ///   switch the user moves in Settings is read by the next Dictation
    ///   without anything being told about it (ADR-0010).
    /// - Parameter diagnostics: where what happened is written down, so that a
    ///   problem can be sent to somebody who can fix it without sending what
    ///   was said. Told rather than asked: nothing here waits on it.
    public init(
        cleaningWith cleanup: any CleanupSwitches,
        hotkey: any HotkeyPort,
        audio: any AudioCapturePort,
        engine: any EnginePort,
        insertion: any InsertionPort,
        clipboard: any ClipboardPort,
        history: any HistoryPort,
        feedback: any FeedbackPort,
        permissions: any PermissionPort,
        clock: any ClockPort,
        diagnostics: any DiagnosticsPort
    ) {
        self.machine = DictationMachine()
        self.cleanup = cleanup
        self.hotkey = hotkey
        self.audio = audio
        self.engine = engine
        self.insertion = insertion
        self.clipboard = clipboard
        self.history = history
        self.feedback = feedback
        self.permissions = permissions
        self.clock = clock
        self.diagnostics = diagnostics
    }

    /// Starts watching for Activations, so that the Hotkey runs a Dictation
    /// while any other app has focus.
    ///
    /// Throwing means the Hotkey cannot be watched —
    /// `HotkeyFailure.accessibilityDenied` — which the app says out loud rather
    /// than leaving the user with a key that does nothing.
    public func watchForActivations() async throws {
        do {
            try await hotkey.observe { [weak self] gesture in
                await self?.activated(by: gesture)
            }
        } catch {
            // Written down because nothing else will say it. Every other
            // failure ends a Dictation somebody was watching; this one is a key
            // that does nothing, which from outside the app is indistinguishable
            // from a key nobody pressed.
            diagnostics.record(.theHotkeyCouldNotBeWatched(FailureName(of: error)))
            throw error
        }
        diagnostics.record(.watchingForTheHotkey)
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
    /// between two Dictations, and the press that failed is already over. The
    /// failure the user is told about — an Insertion that did not land — never
    /// arrives here as an error at all.
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

        case .escapePressed:
            // Untimed, unlike the three above: how long Escape was held is not
            // the difference between two gestures, and there is only one thing
            // it can mean.
            try? await receive(.escapePressed)
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
    /// returns to Idle, and the error is passed on — unless the refusal was a
    /// permission, in which case the Pill says which one and stays up to be read
    /// (#17). The Insertion is the one exception, and it is the reason the rest
    /// can be this blunt — an Insertion that did not land is answered rather
    /// than thrown, with the words on the clipboard and the Pill saying so.
    public func receive(_ event: DictationEvent) async throws {
        queued.append(event)
        guard !isDraining else { return }

        isDraining = true
        defer { isDraining = false }

        do {
            while !queued.isEmpty {
                let event = queued.removeFirst()
                let before = machine.state
                let effects = machine.receive(event)
                writeDown(whatMoved: before, by: event)
                for effect in effects {
                    if let reported = try await perform(effect) {
                        queued.append(reported)
                    }
                }
            }
        } catch {
            queued.removeAll()
            let (ended, worthWritingDown) = whatEnded(by: error)
            diagnostics.record(worthWritingDown)
            let before = machine.state
            // Nothing on the way back to Idle can fail — the Pill has to come
            // down, or say which permission is missing and stay up — but a
            // second failure while unwinding the first has nowhere useful to go,
            // and losing the app to it would be worse than losing the
            // Dictation.
            let effects = machine.receive(ended)
            writeDown(whatMoved: before, by: ended)
            for effect in effects {
                _ = try? await perform(effect)
            }
            throw error
        }
    }

    /// Writes down that a Dictation moved, where it did.
    ///
    /// Only where the state actually changed. An Input Level arrives many times
    /// a second and a stray Hotkey press between two Dictations arrives whenever
    /// the user's hand does; neither is a thing that happened to a Dictation,
    /// and a log with a line for each of them would bury the four that matter
    /// and put a disk write on the stop-to-insert path
    /// (`docs/product-experience.md` §7).
    ///
    /// The note is handed over rather than awaited, so what this costs the
    /// Dictation is the comparison above it and nothing else.
    private func writeDown(whatMoved before: DictationState, by event: DictationEvent) {
        let after = machine.state
        guard before != after else { return }
        diagnostics.record(
            .dictationMoved(from: before, to: after, by: DiagnosticNote.WhatHappened(event)))
    }

    /// What a failure means to the Dictation it ended, and what the log is told
    /// about it.
    ///
    /// A refusal the user can undo is named, because saying which permission it
    /// was and putting them in front of the switch is the difference between a
    /// Dictation that failed and one that failed quietly
    /// (`docs/product-experience.md` §9). Everything else is a Dictation that
    /// ended, and there is nothing to say about it that the user could act on.
    ///
    /// The failure is asked rather than the port, because a permission taken
    /// away is not a port going wrong: it is the same port answering the way it
    /// always does, with the one answer macOS will change its mind about.
    ///
    /// Only the microphone is asked. It is the one port a Dictation can be
    /// refused by: the keyboard is asked for once, by `watchForActivations()`,
    /// which is not on this path and where a refusal is the app's to say rather
    /// than a Dictation's — there is no Dictation to put a Pill up for.
    private func whatEnded(by error: Error) -> (DictationEvent, DiagnosticNote) {
        guard let permission = (error as? AudioCaptureFailure)?.permission else {
            // Named by what it is rather than by what it says about itself,
            // which is the whole of `FailureName`.
            return (.dictationFailed, .somethingFailed(FailureName(of: error)))
        }
        // The same split the log makes as the one the user is shown, decided
        // once: somebody reading a week of these is looking for exactly this,
        // and a Dictation and a log that answered it separately could come to
        // disagree about which failure it was.
        return (.permissionMissing(permission), .permissionMissing(permission))
    }

    /// Takes the Cap from the Clock, five minutes into a Dictation.
    ///
    /// It does not throw where `receive(_:)` does, for the same reason `hear(_:)`
    /// does not: the Clock has nowhere to put an error it was handed back, and
    /// the Dictation the Cap ended is the one that failed.
    private func capReached() async {
        try? await receive(.capReached)
    }

    /// Takes the end of the notice from the Clock.
    ///
    /// It does not throw where `receive(_:)` does, for the same reason
    /// `capReached()` does not: the Clock has nowhere to put an error it was
    /// handed back, and nothing taking the Pill down can fail in any case.
    private func noticeRead() async {
        try? await receive(.noticeRead)
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

        case .startTheCap:
            // The waiting is the Clock's. What comes back comes back through
            // the same door every other event does, so that a Cap which ends
            // over a Dictation that is already stopping is a decision the
            // machine gets to ignore.
            await clock.waitOut(DictationMachine.cap) { [weak self] in
                await self?.capReached()
            }
            return nil

        case .stopTheCap:
            await clock.stopWaiting()
            return nil

        case .noteTargetApp:
            return .targetAppNoted(await insertion.focusedApp())

        case .transcribe(let spoken):
            let transcript = try await engine.transcribe(spoken)
            // The user's switches are read here, on the way back from the
            // Engine, because this is the last moment before Cleanup runs. Read
            // at each Dictation rather than held from launch, exactly as the
            // Cue switch is: a rule turned off in Settings is off for the words
            // being spoken while the window is still open, and there is nothing
            // to keep in step (ADR-0010).
            machine.clean(with: await cleanup.rules())
            return .rawTranscriptReceived(transcript)

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
            // A History that will not take the words does not take the
            // Dictation with it (ADR-0009). It is written first because it is
            // the last resort, not because it is the point: a full disk must
            // not also cost the user the Insertion, which is the one place the
            // words were actually going. If the Insertion then fails too, the
            // Clipboard Fallback is still there — so the words are lost only
            // where every one of the three has gone wrong at once.
            try? await history.append(entry)
            return nil

        case .insert(let finalText, let targetApp):
            do {
                try await insertion.insert(finalText, into: targetApp)
                return .insertionSucceeded
            } catch {
                // Every way an Insertion does not land is the same way here,
                // including one nothing in Cheppu has a name for. The words
                // exist and were not typed, and what the user needs is the same
                // in all of them; a fallback that only caught the two failures
                // the core can name would be silence in the case nobody
                // foresaw, which is the one `docs/product-experience.md` §4
                // rules out.
                return .insertionFailed
            }

        case .leaveOnTheClipboard(let finalText):
            await clipboard.leave(finalText)
            return nil

        case .askFor(let permission):
            await permissions.askFor(permission)
            return nil

        case .leaveTheNoticeUp:
            // The waiting is the Clock's, as the Cap's is, and what comes back
            // comes back through the same door every other event does.
            await clock.waitOut(DictationMachine.longEnoughToReadTheNotice) { [weak self] in
                await self?.noticeRead()
            }
            return nil
        }
    }
}
