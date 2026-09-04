import AppKit
import CheppuCore
import Foundation

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

/// Whether the Cues may be heard.
///
/// Read rather than held, and read at each Cue rather than at launch, so that
/// turning them off silences the Dictation under way rather than the next one
/// after a restart.
public protocol CueSwitch: Sendable {
    func areCuesOn() async -> Bool
}

/// The Cue switch, as macOS keeps it: a preference under Cheppu's own domain.
///
/// On unless the user has said otherwise: someone who has not been to Settings
/// has not asked for a Dictation they cannot hear. The Settings window (#15) is
/// what moves it; this is where it is read from and written to until then.
public struct SystemCueSwitch: CueSwitch {
    /// The one key. Named for what it holds rather than for the switch that
    /// shows it, so that renaming the control in Settings cannot silently
    /// forget what the user chose.
    static let key = "CuesAreOn"

    public init() {}

    /// Answered without suspending, unlike the port it satisfies, so that the
    /// menu can be built from it as it is opened rather than a moment
    /// afterwards.
    public func areCuesOn() -> Bool {
        UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true
    }

    /// Turns the Cues on or off, for a user dictating in a meeting.
    public func turnCues(on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.key)
    }
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
