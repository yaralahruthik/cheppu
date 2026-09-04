import CheppuCore
import Foundation

@testable import CheppuFeedback

/// A speaker nobody can hear: it writes down what it was asked to play instead
/// of playing it, so that running the suite never makes a sound on the machine
/// running it.
actor FakeSpeaker: Speaker {
    private(set) var heard: [Cue] = []

    func play(_ cue: Cue) async {
        heard.append(cue)
    }
}

/// The Cue switch, as the user left it — and as they can move it mid-Dictation.
actor FakeCueSwitch: CueSwitch {
    private var on: Bool

    init(on: Bool) {
        self.on = on
    }

    func areCuesOn() async -> Bool {
        on
    }

    /// The user turns the Cues off, because they have walked into a meeting.
    func turn(on: Bool) {
        self.on = on
    }
}
