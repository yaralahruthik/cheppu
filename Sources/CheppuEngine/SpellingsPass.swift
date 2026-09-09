import CheppuCore
import FluidAudio
import Foundation

/// The second time the Engine hears the audio: the small CTC model, the user's
/// Spellings, and the one question worth asking of them — was that sound this
/// word.
///
/// This is what ADR-0014 chose over a replacement rule. A rule has no ears, so
/// the day the user dictates "I'll chip you in for lunch" it writes "I'll
/// Cheppu in for lunch"; the rescorer is probabilistic about the one thing the
/// rule cannot know, and puts a Spelling in only where the acoustics support
/// it. No string is ever swapped for another.
///
/// It is an actor because loading the models takes seconds and must happen
/// once, and because a Dictation reaches it from wherever the core is running.
actor SpellingsPass {
    /// Where the second part of the Engine sits: `Cheppu/Engine/<repository
    /// folder>`, beside the first.
    private let directory: URL

    /// The session, and the Spellings it was built for.
    ///
    /// Rebuilt when they change, because the terms are tokenised into it: a
    /// session kept across a Correction would be one reading the Spellings the
    /// user had yesterday. Loading the models again is not part of that — they
    /// are held separately, and they are what the seconds go into.
    private var models: CtcModels?
    private var session: VocabularyBoostingSession?
    private var builtFor: Spellings?

    /// How the rescorer is asked to behave, which is the whole difference
    /// between a Spelling and the replacement rule ADR-0014 rejects.
    ///
    /// FluidAudio's defaults leave its "spotter-anchored rescue" pass running
    /// with no similarity floor under it, which puts a term in wherever the
    /// spotter thought it heard one — at a string similarity of nothing. That
    /// exists to recover brand names the primary model mangles, over
    /// vocabularies of hundreds of terms. Over one Spelling it is a disaster:
    /// measured on the Accuracy Corpus with a single Spelling of *Cheppu*, it
    /// rewrote "the keyboard", "encoder", "operating" and forty other spans to
    /// *Cheppu*. That is a rule with no ears wearing a rescorer's clothes, and
    /// it is the thing this whole mechanism was chosen instead of.
    ///
    /// The floors FluidAudio added for exactly that over-fire are what is set
    /// here — the same pair its own inverse-text-normalised preset uses. With
    /// them, one Spelling of *Cheppu* turns "Chapo" and "Chepo" into the name
    /// in all three fixtures and touches nothing else: the Corpus goes from
    /// 3.81% to 3.00% of what the Engine heard, and 9.29% to 8.47% of what the
    /// user reads, measured on 10 September 2026 (Apple M4 Pro, FluidAudio
    /// 0.15.6). The Ceilings do not move, because they are measured on the bare
    /// Engine and this is not it.
    private static let putItInOnlyWhereTheSoundSupportsIt = VocabularyRescorer.Config(
        spotterRescueMinSimilarity: 0.30,
        spotterRescueMultiWordMinSimilarity: 0.50
    )

    init(directory: URL) {
        self.directory = directory
    }

    /// Whether the part of the Engine that can hear where a Spelling was said
    /// is on the machine.
    ///
    /// Read from the manifest the last finished download left, exactly as the
    /// first part is, so that an interrupted fetch is not mistaken for a
    /// finished one.
    nonisolated func isOnTheMachine() -> Bool {
        EngineDownload.isEngineComplete(in: directory)
    }

    /// The transcript with each Spelling put in where the sound supports it, or
    /// nothing where none of them was heard.
    ///
    /// Nothing is also the answer to every way this can go wrong — models that
    /// will not load, a tokenizer that will not read, a CTC pass that fails.
    /// Boosting must never break transcription: the words the user just said
    /// are worth more than the spelling of one of them, and a Dictation that
    /// failed because a Spelling could not be checked would be the worst trade
    /// in the app.
    func rescoring(
        _ text: String, tokenTimings: [TokenTiming], audio: [Float], against spellings: Spellings
    ) async -> String? {
        guard !spellings.isEmpty, !tokenTimings.isEmpty, !audio.isEmpty else { return nil }
        guard let session = try? await session(reading: spellings) else { return nil }

        let rescored = await session.rescore(
            text: text, tokenTimings: tokenTimings, audioSamples: audio)
        return rescored?.text
    }

    /// The session for these Spellings, made once and kept.
    private func session(reading spellings: Spellings) async throws -> VocabularyBoostingSession {
        if let session, builtFor == spellings { return session }

        let models = try await loadedModels()
        joinFluidAudiosCacheToOurs()
        let made = try await VocabularyBoostingSession(
            vocabulary: whatToListenFor(spellings, through: CtcTokenizer.load(from: directory)),
            ctcModels: models,
            config: Self.putItInOnlyWhereTheSoundSupportsIt
        )

        session = made
        builtFor = spellings
        return made
    }

    private func loadedModels() async throws -> CtcModels {
        if let models { return models }

        // Loaded straight out of the directory Cheppu put them in rather than
        // through `ModelHub`, which would work back to a cache directory of
        // FluidAudio's own and, finding nothing there, have nowhere to go with
        // `offlineMode` on.
        let loaded = try await CtcModels.loadDirect(
            from: directory, variant: EngineFiles.spellingsVariant)
        models = loaded
        return loaded
    }

    /// The user's Spellings, in the shape the spotter scores against.
    ///
    /// Tokenised here, against the tokenizer sitting in Cheppu's own directory.
    /// FluidAudio's own convenience for this — `loadWithCtcTokens` — downloads
    /// the models on its own to get at a tokenizer, which is the one thing
    /// `ModelHub.offlineMode` exists to make impossible.
    ///
    /// A Spelling that tokenises to nothing is left out rather than passed on:
    /// there is nothing for the spotter to look for.
    private func whatToListenFor(
        _ spellings: Spellings, through tokenizer: CtcTokenizer
    ) -> CustomVocabularyContext {
        let listeningFor = spellings.entries.compactMap { spelling -> CustomVocabularyTerm? in
            let tokens = tokenizer.encode(spelling.text)
            guard !tokens.isEmpty else { return nil }
            return CustomVocabularyTerm(text: spelling.text, ctcTokenIds: tokens)
        }
        return CustomVocabularyContext(terms: listeningFor)
    }
}

extension SpellingsPass {
    /// Where FluidAudio looks for the tokenizer, whatever directory it was
    /// handed.
    ///
    /// `VocabularyBoostingSession.init` builds its rescorer from
    /// `CtcModels.defaultCacheDirectory(for:)` rather than from the directory
    /// the models were loaded out of, so the tokenizer is looked for under
    /// `FluidAudio/Models/` even though Cheppu keeps the second part under
    /// `Cheppu/Engine/`. Until that is fixed upstream, the two are joined by a
    /// link — which is the fallback ADR-0014's issue names, and the reason the
    /// second part is still in one folder with everything else Cheppu put on
    /// the machine.
    ///
    /// Anything already there and working is left alone — a directory another
    /// app using FluidAudio downloaded for itself, or a link it made. It holds
    /// the same repository's files, so the tokenizer read out of it is the same
    /// tokenizer; and taking it out from under them to point at Cheppu's copy
    /// would be Cheppu breaking somebody else's app to save itself a step.
    ///
    /// The one thing replaced is a link pointing at nothing, which is what an
    /// earlier Cheppu leaves behind when its folder is moved or deleted. That
    /// belongs to nobody and would otherwise be a Spelling that silently
    /// stopped being read.
    nonisolated func joinFluidAudiosCacheToOurs() {
        let cache = CtcModels.defaultCacheDirectory(for: EngineFiles.spellingsVariant)
        let files = FileManager.default

        if files.fileExists(atPath: cache.path) { return }

        // `fileExists` follows the link, so getting here with one present means
        // it leads nowhere.
        if (try? files.destinationOfSymbolicLink(atPath: cache.path)) != nil {
            try? files.removeItem(at: cache)
        }

        try? files.createDirectory(
            at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.createSymbolicLink(at: cache, withDestinationURL: directory)
    }
}
