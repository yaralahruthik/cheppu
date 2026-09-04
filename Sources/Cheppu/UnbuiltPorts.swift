import CheppuCore
import CheppuEngine

// The ports a Dictation needs and nobody has built yet.
//
// A `DictationCore` is handed all of its ports at once, so the ones whose
// tickets have not landed have to be something rather than nothing. They do
// nothing, and they are here rather than behind an optional port, so that the
// seam the real ones wire into is already the shape they will arrive in.
//
// This is glue: it holds no decisions of its own, which is why it is not tested.

/// The Engine, on a machine with nowhere to keep it.
///
/// An account with no Application Support has nowhere for the Engine to live,
/// so there is nothing a Dictation could be transcribed by. Cheppu goes on
/// watching the Hotkey and goes on asking for Accessibility all the same: an
/// app that quietly did nothing at all would be the one outcome
/// `docs/product-experience.md` §4 rules out, and each Dictation instead fails
/// where the Engine would have been. Saying so where the user can read it waits
/// for #18's log.
struct EngineWithNowhereToLive: EnginePort {
    func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript {
        throw ParakeetEngine.Failure.engineNotDownloaded
    }
}
