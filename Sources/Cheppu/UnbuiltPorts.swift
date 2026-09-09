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
/// where the Engine would have been, and says so in the Diagnostics Log by the
/// name of the failure it threw.
///
/// It stands in for both of the Engine's ports, exactly as `ParakeetEngine`
/// satisfies both: the first launch has an Engine Download step whether or not
/// there is anywhere to put what it fetches, and a step that cannot be got past
/// is better than a button that does nothing and says nothing.
struct EngineWithNowhereToLive: EnginePort, EngineDownloadPort {
    func transcribe(_ audio: CapturedAudio) async throws -> RawTranscript {
        throw ParakeetEngine.Failure.engineNotDownloaded
    }

    func isEngineDownloaded() async -> Bool { false }

    func downloadEngine(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws {
        throw ParakeetEngine.Failure.engineNotDownloaded
    }

    func isTheSpellingsPartDownloaded() async -> Bool { false }

    func downloadTheSpellingsPart(
        reporting progress: @escaping @Sendable (EngineDownloadProgress) -> Void
    ) async throws {
        throw ParakeetEngine.Failure.engineNotDownloaded
    }
}
