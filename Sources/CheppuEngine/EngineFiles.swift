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
