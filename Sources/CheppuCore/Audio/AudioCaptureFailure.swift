/// Why a Dictation has no microphone.
///
/// It lives in the core rather than beside the microphone because the core is
/// what has to act on it. The core cannot see AVFoundation, so an error only
/// the audio target could name would reach it as an opaque `Error` — which is
/// the same as not being told, and the Audio capture port's whole promise is
/// that a refusal is never a silent no-op.
///
/// These are the answers the user can tell apart. Saying them out loud, and
/// pointing at the right System Settings pane, is #17's and Onboarding's.
public enum AudioCaptureFailure: Error, Equatable {
    /// Microphone access was refused, or granted once and taken away since.
    case accessDenied

    /// There is no input device to open — none attached, or the one that was
    /// there has gone.
    case noMicrophone

    /// Capture was stopped without having been started. Cheppu's own mistake
    /// rather than the user's, and said out loud rather than answered with an
    /// empty Dictation, which would look like a Dictation that heard nothing.
    case notCapturing

    /// The permission standing in the way, where one is — which is what the app
    /// has to name and which pane it has to open.
    ///
    /// Here rather than in the app, exactly as `HotkeyFailure.permission` is, so
    /// that the sentence a user reads and the pane a button opens are chosen
    /// from the same answer.
    ///
    /// Nothing, for the two failures a System Settings pane cannot fix. A
    /// microphone that is not attached is not the user refusing Cheppu
    /// something, and sending them off to grant a permission they already have
    /// would be Cheppu blaming them for an unplugged cable.
    public var permission: Permission? {
        switch self {
        case .accessDenied: .microphone
        case .noMicrophone, .notCapturing: nil
        }
    }
}
