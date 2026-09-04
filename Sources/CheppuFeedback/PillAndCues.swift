import CheppuCore

/// The Feedback port: the Pill on screen and the Cues out loud.
///
/// The two senses a Dictation is known through (`docs/product-experience.md`
/// §3), and nothing else. Every decision about which state is shown when, and
/// which Cue answers which moment, was made in the core before this is called;
/// what is here is a renderer, which is why the sequence a Dictation produces
/// is asserted at the core seam rather than in front of a screen.
///
/// The two halves are deliberately separate underneath. The Pill has to reach
/// the main thread, and the Cues have a switch of their own in front of them,
/// so a user who has turned the Cues off still sees everything and a Dictation
/// under a menu still hears everything.
public struct PillAndCues: FeedbackPort {
    private let pill: Pill
    private let cues: Cues

    /// The real Pill, over the Mac's own screen and speakers.
    ///
    /// - Parameter cueSwitch: whether the user wants to hear a Dictation. Handed
    ///   in rather than read from here, because where the switch is kept is the
    ///   preferences' business and this target's business is the sound
    ///   (ADR-0010).
    @MainActor
    public init(when cueSwitch: any CueSwitch) {
        self.pill = Pill()
        self.cues = Cues(through: SystemSpeaker(), when: cueSwitch)
    }

    public func showPill(_ state: PillState) async {
        await pill.show(state)
    }

    public func hidePill() async {
        await pill.hide()
    }

    public func play(_ cue: Cue) async {
        await cues.play(cue)
    }
}
