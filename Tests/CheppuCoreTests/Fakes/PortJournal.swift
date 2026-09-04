import Foundation

@testable import CheppuCore

/// The ordered record of everything a `DictationCore` told its ports to do.
///
/// Every fake port writes here, so one assertion can state the whole story of a
/// Dictation in the order the user would have experienced it — the Cue, the
/// Pill, the audio going to the Engine, the History write landing before the
/// Insertion. Ordering across ports is the point; a per-fake array could not
/// show it.
actor PortJournal {
    enum Call: Equatable {
        case cuePlayed(Cue)
        case pillShown(PillState)
        case pillHidden
        case capturingStarted
        case capturingStopped
        case transcribed(CapturedAudio)
        case appendedToHistory(HistoryEntry)
        case inserted(FinalText, into: TargetApp)
    }

    private(set) var calls: [Call] = []

    func record(_ call: Call) {
        calls.append(call)
    }
}
