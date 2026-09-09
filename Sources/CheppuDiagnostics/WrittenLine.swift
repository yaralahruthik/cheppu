import CheppuCore
import Foundation

/// One note, as it appears in the file: when it happened, how long after the
/// line before it, and what it was.
///
///     2026-09-07T13:04:02.113+01:00  +0.000s  idle → listening, the Hotkey went down
///     2026-09-07T13:04:07.550+01:00  +5.437s  listening → transcribing, the Hotkey went down
///     2026-09-07T13:04:07.901+01:00  +0.351s  transcribing → inserting, the Raw Transcript arrived
///     2026-09-07T13:04:07.912+01:00  +0.011s  inserting → idle, the Insertion landed
///
/// The gap is written out rather than left to be worked out, because it is the
/// number somebody is reading the file for. Those four lines say the user spoke
/// for five and a half seconds, the Engine took a third of a second, and the
/// words landed eleven milliseconds later — which is the stop-to-insert budget
/// (`docs/product-experience.md` §7) measured on the machine that missed it,
/// rather than guessed at from a bug report.
///
/// The words are here rather than in the core, unlike the Pill's and the menu's.
/// What the Pill says is a decision about what the user is told, and the core is
/// where decisions are made; what a line of this file looks like is the format
/// of a file, and the file belongs to whoever writes it.
struct WrittenLine: Equatable {
    let note: DiagnosticNote

    /// When it happened, which is when the note was handed over rather than
    /// when the disk got round to it. That is the whole reason a Dictation can
    /// let go of a note and be timed by it all the same.
    let at: Date

    /// The moment written out, to the millisecond, with the machine's offset
    /// from UTC on it.
    ///
    /// Local time because the person reading the file is the person it happened
    /// to, and they are looking for "that time this morning"; the offset
    /// because the person they send it to is not.
    private static let asAMoment = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true, timeZone: .current)

    /// - Parameter previous: when the line before this one happened, or nothing
    ///   where this is the first since Cheppu started writing.
    func text(since previous: Date?) -> String {
        let gap = previous.map { at.timeIntervalSince($0) } ?? 0
        return
            "\(at.formatted(Self.asAMoment))  \(Self.gap(of: gap))  \(Self.words(for: note))"
    }

    /// How long since the line before, in seconds and milliseconds.
    ///
    /// Never negative, however the machine's clock moved between two lines: a
    /// gap that ran backwards is a clock that was stepped, not a Dictation that
    /// finished before it started, and a log that said otherwise would send
    /// whoever reads it looking for the wrong thing.
    private static func gap(of seconds: TimeInterval) -> String {
        String(format: "+%.3fs", max(seconds, 0))
    }

    /// What the note says, in the words of `CONTEXT.md`.
    private static func words(for note: DiagnosticNote) -> String {
        switch note {
        case .dictationMoved(let from, let to, let what):
            "\(name(of: from)) → \(name(of: to)), \(words(for: what))"
        case .somethingFailed(let failure):
            "a Dictation ended: \(failure)"
        case .permissionMissing(let permission):
            "macOS is not granting \(permission.name)"
        case .spellingsWereRead(let took):
            "the Spellings were read in \(seconds(of: took))"
        case .notesWereDropped(let howMany):
            "\(howMany) notes were dropped: the disk was not keeping up"
        case .watchingForTheHotkey:
            "watching for the Hotkey"
        case .theHotkeyCouldNotBeWatched(let failure):
            "the Hotkey cannot be watched: \(failure)"
        }
    }

    /// A span, in the seconds and milliseconds the gaps between lines are
    /// written in, so that the one measured timing in the file reads the same
    /// as every timing worked out from two of them.
    private static func seconds(of span: Duration) -> String {
        let whole = Double(span.components.seconds)
        let rest = Double(span.components.attoseconds) / 1e18
        return gap(of: whole + rest)
    }

    private static func name(of state: DictationState) -> String {
        switch state {
        case .idle: "idle"
        case .listening: "listening"
        case .transcribing: "transcribing"
        case .inserting: "inserting"
        }
    }

    private static func words(for what: DiagnosticNote.WhatHappened) -> String {
        switch what {
        case .theHotkeyWentDown: "the Hotkey went down"
        case .theHotkeyCameUp: "the Hotkey came up"
        case .thePressTurnedOutToBeTyping: "the press turned out to be typing"
        case .escapeWasPressed: "Escape was pressed"
        case .theCapWasReached: "the Cap was reached"
        case .theAudioArrived: "the audio arrived"
        case .theRawTranscriptArrived: "the Raw Transcript arrived"
        case .theInsertionLanded: "the Insertion landed"
        case .theInsertionDidNotLand: "the Insertion did not land"
        case .aPortFailed: "something failed"
        case .aPermissionWasMissing: "a permission was missing"
        case .theTargetAppWasNoted: "the Target App was noted"
        case .theInputLevelChanged: "the Input Level changed"
        case .theNoticeWasRead: "the notice was read"
        }
    }
}
