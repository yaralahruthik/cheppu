import FluidAudio
import Foundation

/// What the Engine is made of, and where it sits on this machine.
///
/// The names come from FluidAudio rather than from a list written out here, so
/// that the files Cheppu downloads and the files FluidAudio later opens cannot
/// drift apart across a version bump.
enum EngineFiles {
    /// The Hugging Face repository holding Parakeet TDT v3 compiled for CoreML.
    static let repository = Repo.parakeetV3

    /// The repository holding the second part of the Engine: the small CTC
    /// model that hears the audio again and finds where a Spelling was said.
    ///
    /// A second repository rather than more of the first, because it is a
    /// different model published in a different place — and because it is
    /// fetched at a different moment, by a user who has made a Correction
    /// (ADR-0014).
    static let spellingsRepository = Repo.parakeetCtc110m

    /// Which CTC model the second part is, in FluidAudio's own vocabulary.
    static let spellingsVariant = CtcModelVariant.ctc110m

    /// The version FluidAudio is asked to load, and the one whose file names the
    /// download is built from.
    static let version = AsrModelVersion.v3

    /// int8 rather than int4: ADR-0001 buys the Engine for its accuracy, and the
    /// int4 encoder trades some of that away for a download 150 MB smaller.
    static let encoderPrecision = ParakeetEncoderPrecision.int8

    /// The CoreML bundles the Engine is assembled from. Each name is a directory
    /// in the repository, not a file.
    static let bundles = ModelNames.ASR.requiredModelsV3(precision: encoderPrecision)

    /// The token table, a plain file at the repository root.
    static let vocabulary = ModelNames.ASR.vocabularyFile

    /// What the second part is made of: two CoreML bundles, the token table the
    /// spotter scores against, and the tokenizer that turns a Spelling into the
    /// tokens to score.
    ///
    /// The tokenizer is here because `VocabularyRescorer` loads one and cannot
    /// be given the terms already tokenised. Without it the second pass would
    /// have to tokenise by downloading on its own, which is the one thing
    /// `ModelHub.offlineMode` exists to make impossible.
    static let spellingsBundles = ModelNames.CTC.requiredModels

    /// The CTC token table, a plain file at that repository's root.
    static let spellingsVocabulary = ModelNames.CTC.vocabularyPath

    /// The tokenizer FluidAudio reads a Spelling with, beside it.
    static let spellingsTokenizer = "tokenizer.json"

    /// Whether a path inside the CTC repository is part of what Spellings need.
    ///
    /// That repository also carries the CTC head, the `.mlpackage` sources and
    /// the conversion scripts — none of which the rescorer opens, and all of
    /// which would be bytes the user waits for and never uses.
    static func isSpellingsFile(_ path: String) -> Bool {
        if path == spellingsVocabulary || path == spellingsTokenizer { return true }
        return spellingsBundles.contains { path.hasPrefix($0 + "/") }
    }

    /// Whether a path inside the repository is part of the Engine.
    ///
    /// The repository carries several encoders, several joints, and the
    /// `.mlpackage` sources they were compiled from — roughly 3.5 GB in all,
    /// against the 480 MB Cheppu actually runs. Everything the Engine does not
    /// open is bytes the user waits for and never uses.
    static func isEngineFile(_ path: String) -> Bool {
        if path == vocabulary { return true }
        return bundles.contains { path.hasPrefix($0 + "/") }
    }

    /// Where the Engine lives: `Cheppu/Engine/<repository folder>` inside
    /// Application Support.
    ///
    /// Under Cheppu's own folder rather than the one FluidAudio would pick on
    /// its own, so that everything Cheppu put on the machine sits in one place
    /// the user can find and delete.
    ///
    /// The last path component has to be the repository's folder name:
    /// FluidAudio works back to the directory it opens from the parent of the
    /// one it is handed.
    static func directory(inApplicationSupport applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Cheppu", isDirectory: true)
            .appendingPathComponent("Engine", isDirectory: true)
            .appendingPathComponent(repository.folderName, isDirectory: true)
    }

    /// Where the second part lives: `Cheppu/Engine/<repository folder>` inside
    /// Application Support, beside the first.
    ///
    /// The same folder as everything else Cheppu put on the machine, so that
    /// what the user deletes when they are done with Cheppu is still one drag
    /// (ADR-0009).
    static func spellingsDirectory(inApplicationSupport applicationSupport: URL) -> URL {
        spellingsDirectory(besideTheFirstPartAt: directory(inApplicationSupport: applicationSupport))
    }

    /// The same place, worked out from wherever the first part is.
    ///
    /// Said once rather than twice: "beside the first part" is the whole of
    /// where the second one goes, and a suite that puts the first somewhere of
    /// its own gets the second in the same folder without being told.
    static func spellingsDirectory(besideTheFirstPartAt firstPart: URL) -> URL {
        firstPart
            .deletingLastPathComponent()
            .appendingPathComponent(spellingsRepository.folderName, isDirectory: true)
    }

    /// `~/Library/Application Support`, or a throw if this account has no such
    /// place — which would mean the Engine has nowhere to live.
    static func defaultApplicationSupport() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}


/// One of the two parts the Engine is in: where it is published, and which of
/// the files published there Cheppu actually runs.
///
/// A value rather than two copies of the download, because everything the
/// download does — the listing, the resume, the size check, the digest, the
/// manifest — is the same for both, and the only difference between them is
/// which repository is asked and which of its files are wanted (ADR-0014).
struct EnginePart: Sendable {
    let repository: Repo
    let isPartOfIt: @Sendable (String) -> Bool

    /// What every Dictation needs: Parakeet TDT v3, fetched at Onboarding.
    static let everyDictationNeedsIt = EnginePart(
        repository: EngineFiles.repository, isPartOfIt: EngineFiles.isEngineFile)

    /// What only Spellings need, offered at the first Correction and never
    /// before.
    static let onlySpellingsNeedIt = EnginePart(
        repository: EngineFiles.spellingsRepository, isPartOfIt: EngineFiles.isSpellingsFile)
}
