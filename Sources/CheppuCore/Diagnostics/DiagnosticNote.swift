/// One line of the Diagnostics Log: something Cheppu did, and never anything
/// the user said.
///
/// A closed vocabulary rather than a message. Every other logger in the world
/// takes a string, and a string is the one shape that can hold a Raw Transcript
/// — by a debugging line somebody left in, or by an error whose description
/// turns out to carry what it was handed. Nothing in here carries a `String` at
/// all, and the two places one is made are in `FailureName`, out of a type
/// rather than a value. So "the log holds no audio, no Raw Transcript and no
/// Final Text" is a thing the compiler enforces rather than a thing the next
/// person to touch this remembers
/// (`docs/product-experience.md` §10).
///
/// It says nothing about the Target App either, for the same reason History
/// does not: which windows somebody dictates into is a record of their day.
///
/// Why a vocabulary rather than a message is ADR-0012.
public enum DiagnosticNote: Equatable, Sendable {
    /// A Dictation moved from one state to the next, and what moved it.
    ///
    /// The whole of the story a log has to tell about a Dictation, and the
    /// whole of its timings too: what is written next to each of these is when
    /// it happened, so how long somebody spoke for, how long the Engine took,
    /// and how long the words took to land are the gaps between three lines
    /// rather than three numbers Cheppu had to stop and measure
    /// (`docs/product-experience.md` §7).
    ///
    /// Only where the state actually changed. A Dictation reports its Input
    /// Level many times a second and none of them is a thing that happened to
    /// it, so a log that wrote a line per event would bury the four that
    /// matter and put a disk write on the stop-to-insert path.
    case dictationMoved(from: DictationState, to: DictationState, by: WhatHappened)

    /// A port could not do what it was asked, and the Dictation ended there.
    ///
    /// Named by what the failure is rather than by what it says about itself,
    /// which is the whole of `FailureName`.
    case somethingFailed(FailureName)

    /// macOS is no longer letting Cheppu do something a Dictation needs.
    ///
    /// A note of its own rather than one of the failures above, because it is
    /// the one the user can act on and the one somebody reading the log is
    /// looking for: a week of Dictations that all end here is a permission that
    /// was taken away, not an app that is broken (#17).
    case permissionMissing(Permission)

    /// Cheppu is watching for the Hotkey.
    ///
    /// Written every time the watch is established rather than once at launch,
    /// because it is established again whenever the user chooses a different
    /// key and again after every refusal the watch waits out (ADR-0010). A log
    /// that says this once an hour is a log of somebody's Accessibility being
    /// granted and taken away.
    case watchingForTheHotkey

    /// Cheppu may not watch the keyboard, so the Hotkey does nothing at all.
    ///
    /// The one failure that is not a Dictation's: there is no Dictation to fail,
    /// which is exactly what makes it invisible from the outside and worth
    /// writing down.
    case theHotkeyCouldNotBeWatched(FailureName)

    /// The Engine heard the audio a second time, to find where a Spelling was
    /// said, and this is how long that took.
    ///
    /// The one note that carries a measurement rather than being timed by the
    /// gap to the line before it. Every other timing in the log is the distance
    /// between two things that happened; this one happens inside a single move
    /// from Transcribing to Inserting, so a reader with a stop-to-insert budget
    /// that has been missed could otherwise tell that the Engine was slow and
    /// not whether it was the Spellings that made it so (ADR-0014).
    ///
    /// It says how long and nothing else. Which Spellings were read, how many
    /// there were, and whether any of them was put in are all things about what
    /// the user said, and none of them is in here — a `Duration` is a number,
    /// and a number cannot hold a word.
    case spellingsWereRead(Duration)

    /// Notes were taken faster than the disk would take them, and this many
    /// were let go of.
    ///
    /// The queue a note waits in is bounded, because it is the one part of the
    /// log that lives in memory and a disk that has stopped answering must cost
    /// the user a gap in a file rather than the app. This is what makes the gap
    /// a line rather than a silence: a log that quietly skipped an hour would
    /// send whoever reads it looking for a Dictation that never failed.
    case notesWereDropped(Int)

    /// What moved a Dictation from one state to the next.
    ///
    /// `DictationEvent` with everything it carries left off. A separate
    /// vocabulary rather than the event itself, because the events carry the
    /// audio, the Raw Transcript and the Final Text — putting one in a note
    /// would be the leak this whole type exists to make impossible — and
    /// because what the log is for is knowing which of them happened.
    public enum WhatHappened: Equatable, Sendable, CaseIterable {
        case theHotkeyWentDown
        case theHotkeyCameUp

        /// The press turned out to be typing, and the Dictation it opened was
        /// handed back.
        case thePressTurnedOutToBeTyping

        /// Escape, while Listening: the user threw the Dictation away.
        case escapeWasPressed

        /// Five minutes, and the Dictation stopped itself.
        case theCapWasReached

        /// The microphone handed over what it heard.
        case theAudioArrived

        /// The Engine handed back a Raw Transcript. A Dictation that ends here
        /// rather than going on to Insertion is a Discard: the Engine heard no
        /// words in it.
        case theRawTranscriptArrived

        case theInsertionLanded

        /// The words could not be typed, so they are on the clipboard and the
        /// Pill says so.
        case theInsertionDidNotLand

        case aPortFailed

        case aPermissionWasMissing

        /// Three of the events never move a Dictation between states, so a note
        /// is never written for one of them: the Target App being noted, an
        /// Input Level arriving, and a notice having been read. They are named
        /// here all the same, and named as what they are, because the switch
        /// below has no `default` — an event added later and forgotten stops the
        /// build rather than arriving in the log as a shrug.
        case theTargetAppWasNoted
        case theInputLevelChanged
        case theNoticeWasRead

        /// What happened, from the event that carried it — and nothing the
        /// event was carrying.
        ///
        /// This is the join between the two vocabularies, and the only place a
        /// Raw Transcript could ever have reached the log. It is one `switch`
        /// returning cases that hold nothing, which is what makes it checkable
        /// by reading it.
        public init(_ event: DictationEvent) {
            switch event {
            case .hotkeyPressed: self = .theHotkeyWentDown
            case .hotkeyReleased: self = .theHotkeyCameUp
            case .hotkeyPressSpoiled: self = .thePressTurnedOutToBeTyping
            case .escapePressed: self = .escapeWasPressed
            case .capReached: self = .theCapWasReached
            case .audioCaptured: self = .theAudioArrived
            case .rawTranscriptReceived: self = .theRawTranscriptArrived
            case .insertionSucceeded: self = .theInsertionLanded
            case .insertionFailed: self = .theInsertionDidNotLand
            case .dictationFailed: self = .aPortFailed
            case .permissionMissing: self = .aPermissionWasMissing
            case .targetAppNoted: self = .theTargetAppWasNoted
            case .inputLevelChanged: self = .theInputLevelChanged
            case .noticeRead: self = .theNoticeWasRead
            }
        }
    }
}
