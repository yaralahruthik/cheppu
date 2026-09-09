import Foundation

// Cheppu's core decides; the ports do. Each one is the narrowest description of
// a thing the core needs done that it cannot do itself, and each has exactly two
// implementations: the real one in whichever target owns that piece of the OS —
// the app, the Engine, the microphone — and a fake in the core suite.
//
// This is what lets the whole of Cheppu's behaviour be tested with no
// permissions granted, no Engine downloaded, no network, and no audio hardware.

/// What the user did with the Hotkey.
///
/// The port reports the key going down and coming back up, and nothing about
/// how either was produced — a bare modifier, a chord, or a test. Which of them
/// is a Toggle and which a Hold is not in here: telling those apart takes the
/// Clock and the answer to "is a Dictation already running", and the keyboard
/// has neither. So the port reports the gesture and the machine decides, which
/// is what keeps a press after the Cap has ended a Dictation a start rather
/// than a stop nobody is waiting for.
public enum HotkeyEvent: Equatable, Sendable {
    /// The Hotkey went down on its own: nothing else held, and nothing typed
    /// with it yet.
    case pressed

    /// The Hotkey came back up, ending a press that was reported.
    case released

    /// The press turned out to be typing: a key was struck, or another modifier
    /// joined it, while the Hotkey was held.
    ///
    /// Reported the moment it happens rather than when the key finally comes up,
    /// because a Dictation that should never have started is one the microphone
    /// should not still be open for.
    case pressSpoiled

    /// Escape went down.
    ///
    /// Reported wherever the user pressed it and whatever else was held at the
    /// time, because whether it means anything is not the keyboard's to decide:
    /// Escape is Cancel while a Dictation is Listening and is the user's own
    /// business at every other moment. It is reported rather than taken —
    /// Cheppu's watch on the keyboard can read a key and cannot swallow one
    /// (ADR-0006) — so the app the user is in receives it either way.
    case escapePressed
}

/// Where Activation gestures come from.
public protocol HotkeyPort: Sendable {
    /// Starts reporting what the user does with the Hotkey, replacing any
    /// handler already installed.
    ///
    /// Throwing means Cheppu may not watch the keyboard —
    /// `HotkeyFailure.accessibilityDenied` — so that a Hotkey which cannot work
    /// is something the app says out loud rather than a key that does nothing.
    func observe(_ handler: @escaping @Sendable (HotkeyEvent) async -> Void) async throws
}

/// Which key the user dictates with.
///
/// Read rather than held, exactly as the Cue switch and the Cleanup rules are,
/// and read at the moment watching starts rather than at launch (ADR-0010).
/// Changing the Hotkey is therefore a matter of watching again with what the
/// user just chose, and takes effect on the very next press.
public protocol HotkeyChoice: Sendable {
    func hotkey() async -> Hotkey
}

/// The microphone.
public protocol AudioCapturePort: Sendable {
    /// Begins capturing, reporting how loud it is hearing as it goes. Called
    /// first of everything a Dictation does, so that no speech is lost to the
    /// Cue that follows it.
    ///
    /// Throwing means the Dictation has no microphone — access refused, or a
    /// device that would not open — and the core takes the Dictation down
    /// rather than listening to nothing.
    ///
    /// A refusal throws `AudioCaptureFailure.accessDenied`, which is the core's
    /// own vocabulary rather than the microphone's, so that the core can tell a
    /// refusal from a device that would not open.
    ///
    /// The report may suspend, so that the levels reach the core in the order
    /// they were heard. Whoever holds the microphone is responsible for the
    /// hand-off never reaching the audio thread, which cannot afford to wait.
    func startCapturing(reporting: @escaping @Sendable (InputLevel) async -> Void) async throws

    /// Ends capturing and hands over what was captured.
    ///
    /// The audio belongs to the caller from here: whoever was holding it lets
    /// go, so that nothing outlives the Dictation that produced it.
    func stopCapturing() async throws -> CapturedAudio
}

/// The on-device speech-to-text model.
public protocol EnginePort: Sendable {
    /// Turns captured audio into a Raw Transcript with per-word timings.
    ///
    /// Called once the Dictation has stopped. There is no streaming or
    /// partial-result path.
    func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript
}

/// Putting the Engine on the machine.
///
/// Separate from `EnginePort` because the two are asked for at different moments
/// by different callers: Onboarding downloads once, a Dictation transcribes many
/// times. One object in the app target satisfies both, which is where the
/// ordering between them — nothing transcribes before the download has finished
/// — actually lives.
public protocol EngineDownloadPort: Sendable {
    /// Whether every file the Engine needs is already on the machine.
    ///
    /// Answered from disk, without the network, so that the ordinary launch —
    /// the Engine is already here — costs nothing.
    func isEngineDownloaded() async -> Bool

    /// Fetches whatever the Engine is missing, reporting progress as it arrives.
    ///
    /// Called again after an interrupted attempt, it carries on from where the
    /// last one stopped rather than starting the 600 MB over. Returning normally
    /// means the Engine is ready; throwing leaves what did arrive in place for
    /// the next attempt to build on.
    ///
    /// The report is a notification and not a request: nothing waits on it, so
    /// it is handed over synchronously rather than made something the download
    /// has to await before fetching the next chunk.
    func downloadEngine(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws

    /// Whether the part of the Engine that only Spellings need is on the
    /// machine.
    ///
    /// Answered from disk, without the network, like the question above it: it
    /// is asked every time the Settings window or the History window is drawn,
    /// and neither of those is a moment the user chose to spend their
    /// connection on.
    func isTheSpellingsPartDownloaded() async -> Bool

    /// Fetches that part, reporting progress as it arrives.
    ///
    /// Called only where somebody pressed a button. A download the user did not
    /// start, on a connection they did not choose to spend, is the stall
    /// `docs/product-experience.md` §12 warns about — so this is never called
    /// at launch, and never on the way past (ADR-0014).
    ///
    /// Resumable on the same terms as the first part: an attempt that stopped
    /// is picked up where it stopped by the next press of either button.
    func downloadTheSpellingsPart(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws
}

/// Placing Final Text at the text cursor of the Target App.
public protocol InsertionPort: Sendable {
    /// Which app has keyboard focus this instant, or nothing if none has.
    ///
    /// Asked when the Dictation stops, which is what makes the Target App the
    /// app the user was in when they finished speaking rather than the one they
    /// started in.
    func focusedApp() async -> TargetApp?

    /// Inserts the Final Text at the text cursor of the Target App, as if it
    /// had been typed.
    ///
    /// The Target App is passed rather than looked up again because the
    /// Insertion is *for* that app: throwing `InsertionFailure.focusMoved`
    /// where it is no longer the app with focus is what stops a Dictation
    /// landing in whichever window came to the front while the Engine was
    /// working. The check belongs next to the keystroke rather than up here,
    /// where anything between the two would be a window for focus to move in.
    ///
    /// Throwing means it did not land, whatever the reason, and the Clipboard
    /// Fallback is what the user gets instead: the words on the clipboard, and
    /// the Pill saying so. An error this port has no name for is answered the
    /// same way as one it does, because there is no failure of an Insertion
    /// that leaves the user needing something else.
    func insert(_ finalText: FinalText, into targetApp: TargetApp) async throws
}

/// The clipboard, as somewhere to leave what could not be typed.
///
/// One direction only. Borrowing the pasteboard to paste with, and giving it
/// back, belongs to whoever performs the Insertion and never leaves that file;
/// what the core decides is the one thing Cheppu ever leaves on the user's
/// clipboard on purpose.
public protocol ClipboardPort: Sendable {
    /// Leaves the Final Text on the clipboard, replacing whatever was there.
    ///
    /// Called only on the Clipboard Fallback, and never followed by putting
    /// back what it displaced: the words the user could not have typed for them
    /// are worth more than the thing they had copied, and this is the one place
    /// Cheppu makes that trade (`docs/product-experience.md` §4).
    func leave(_ finalText: FinalText) async
}

/// The local store that makes sure nothing said is ever lost.
public protocol HistoryPort: Sendable {
    /// Appends one Dictation's Final Text. Called before Insertion is attempted,
    /// on every path out of Transcribing.
    func append(_ entry: HistoryEntry) async throws
}

/// The Spellings the Engine reads.
///
/// Read rather than held, exactly as the Cue switch and the Cleanup rules are,
/// and read at the Dictation that is about to be transcribed rather than at
/// launch (ADR-0010). A Spelling left behind by a Correction made a moment ago
/// is therefore read by the very next thing the user says, with nothing to keep
/// in step and nothing to restart.
///
/// Separate from the switch below because they are two questions with two
/// answers: what the user has taught Cheppu, and whether Cheppu is listening
/// for it. Off keeps the Spellings and stops reading them.
public protocol SpellingsPort: Sendable {
    func spellings() async -> Spellings
}

/// Whether the Engine reads the user's Spellings.
///
/// One line of the Settings window, read where it is used, so that a Spelling
/// suspected of misfiring can be ruled out in one flick and put back in
/// another (ADR-0010).
public protocol SpellingsSwitch: Sendable {
    func areSpellingsRead() async -> Bool
}

/// Whether the Cues may be heard.
///
/// Read rather than held, and read at each Cue rather than at launch, so that
/// turning them off silences the Dictation under way rather than the next one
/// after a restart.
///
/// A port rather than something the Pill owns, because the switch belongs to
/// the user: it is one line of the Settings window and one item of the menu
/// bar, and both of them move the same thing (ADR-0010).
public protocol CueSwitch: Sendable {
    func areCuesOn() async -> Bool
}

/// Which Cleanup rules the user has on.
///
/// Read rather than held, exactly as the Cue switch is, and read at the moment
/// the words are about to be cleaned rather than when the app launched. That is
/// what makes a switch flicked in Settings the switch the very next Dictation
/// goes through, with nothing to keep in step and nothing to restart
/// (ADR-0010).
public protocol CleanupSwitches: Sendable {
    func rules() async -> CleanupRules
}

/// The Pill and the Cues — the two senses through which the user knows the
/// state without looking at Cheppu.
public protocol FeedbackPort: Sendable {
    func showPill(_ state: PillState) async
    func hidePill() async
    func play(_ cue: Cue) async
}

/// Saying which permission Cheppu does not have, and offering the way to the
/// pane it is granted on.
///
/// A port of its own rather than part of the Feedback port, because it is not
/// one of the two senses a Dictation is known through: the Pill and the Cues
/// say what is happening to a Dictation, and this asks the user to leave what
/// they are doing and go and grant something
/// (`docs/product-experience.md` §9).
public protocol PermissionPort: Sendable {
    /// Names the permission and offers the way to its pane.
    ///
    /// Called by the Dictation that met the refusal, which is the moment the
    /// user is owed the answer. It returns once they have been told rather than
    /// once they have answered: a Dictation waiting on somebody to read an
    /// alert would be a Hotkey that does nothing while it is up.
    ///
    /// How often one is worth putting in front of somebody who has already been
    /// told is whoever implements this port's, because they are the only one who
    /// can see whether the permission has come back since.
    func askFor(_ permission: Permission) async
}

/// Every reading of the time the core takes, and every wait it does.
///
/// Nothing in the core calls a system clock directly and nothing in it sleeps,
/// so a test can stamp a History entry, hold the Hotkey down for a second, and
/// leave a Dictation running for five minutes, without waiting for any of them.
public protocol ClockPort: Sendable {
    func now() async -> Date

    /// Waits out a span and then does what it was given to do, unless the wait
    /// is called off before it ends.
    ///
    /// The waiting belongs here rather than to the core. Cheppu waits for two
    /// things — the Cap, and the notice a Clipboard Fallback leaves on screen —
    /// and a core that ran its own timer would be a core whose five minutes
    /// could only be reached by waiting five minutes.
    ///
    /// It returns once the wait has begun rather than when it ends, because
    /// arming the Cap happens on the way into a Dictation and must cost it
    /// nothing.
    ///
    /// One wait at a time: starting another calls off the one before it, so a
    /// Clock can never be counting for two Dictations at once. That is what
    /// makes a Dictation started while a notice is still up take the Pill over
    /// rather than have it pulled out from under it.
    func waitOut(_ span: Duration, then whatFollows: @escaping @Sendable () async -> Void) async

    /// Calls off the wait that is under way, if there is one, so that what
    /// follows it never happens.
    func stopWaiting() async
}

/// The Diagnostics Log: what Cheppu did, kept on the machine so that a problem
/// can be sent to somebody who can fix it without sending what was said.
///
/// The whole of Cheppu's diagnostic story. There is no telemetry, no crash
/// reporter and no analytics behind this port — one file, written by the
/// machine it is about, that the user reads before they decide to share it.
///
/// It is the one port that is told rather than asked. Every other one is a
/// request the core waits on; a note is handed over and let go of, because
/// notes are written on the path between somebody finishing a sentence and the
/// words appearing, and nothing on that path may wait for a disk
/// (`docs/product-experience.md` §7). Whoever implements it stamps the note as
/// it arrives and writes it later, so the log's timings are the moments things
/// happened rather than the moments the disk got round to them.
///
/// Neither half of that is what a logger usually is, so both are on record
/// (ADR-0012).
///
/// Nothing it does can fail as far as the core is concerned. A log that could
/// not be written must never be what costs the user a Dictation: it is the
/// least important thing Cheppu does and it is on the path of the most
/// important one.
public protocol DiagnosticsPort: Sendable {
    func record(_ note: DiagnosticNote)
}
