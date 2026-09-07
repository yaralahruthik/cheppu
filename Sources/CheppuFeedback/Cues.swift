import AppKit
import CheppuCore

/// Something that can make a short sound.
///
/// A seam so that the suite can assert what would have been heard without the
/// machine running it making a sound — and so that nothing in a test has to own
/// an audio device to find out whether a Cue was played.
protocol Speaker: Sendable {
    /// Plays this Cue's sound, and returns without waiting for it to finish. A
    /// Cue marks a moment; nothing about a Dictation waits on one.
    func play(_ cue: Cue) async
}

/// The Cues: the half of the feedback a user with their eyes on their work
/// actually gets.
///
/// Everything about which sound belongs to which moment is `CueTone`'s. All
/// this holds is the switch in front of them, which is the one thing about a
/// Cue that is the user's to decide.
actor Cues {
    private let speaker: any Speaker
    private let cueSwitch: any CueSwitch

    init(through speaker: any Speaker, when cueSwitch: any CueSwitch) {
        self.speaker = speaker
        self.cueSwitch = cueSwitch
    }

    func play(_ cue: Cue) async {
        guard await cueSwitch.areCuesOn() else { return }
        await speaker.play(cue)
    }
}

/// The Mac's speakers.
///
/// The three sounds are built once, when Cheppu launches, rather than at the
/// moment one is wanted: the start Cue plays over an open microphone, a fifth
/// of a second before the user's first word, and rendering a tone there would
/// be time spent while they are already speaking.
///
/// On the main actor because `NSSound` is AppKit, and playing is asked for from
/// whichever thread a Dictation reached this on.
@MainActor
final class SystemSpeaker: Speaker {
    /// One sound per Cue, or none where the Mac would not make one of what
    /// `CueTone` wrote. Readable so that a test can ask whether it did without
    /// anything being heard.
    private(set) var sounds: [Cue: NSSound]

    init() {
        sounds = Cue.allCases.reduce(into: [:]) { sounds, cue in
            sounds[cue] = NSSound(data: CueTone.of(cue).wav)
        }
    }

    func play(_ cue: Cue) {
        guard let sound = sounds[cue] else { return }

        // Stopped first, so that a Cue arriving on the heels of the one before
        // it — a Dictation cancelled the instant it started — plays rather than
        // being dropped by a sound that is still going.
        sound.stop()
        sound.play()
    }
}
