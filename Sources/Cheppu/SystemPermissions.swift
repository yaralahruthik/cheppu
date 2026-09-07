import CheppuAudio
import CheppuCore
import CheppuKeyboard
import CheppuSettings

/// What macOS says about Cheppu's two permissions, this instant.
///
/// Assembled here rather than in the Settings window because each answer
/// belongs to the target that owns that piece of the machine: the Microphone is
/// the audio target's, Accessibility is the keyboard's, and the app is the one
/// place both are in scope. Neither answer prompts for anything, so opening
/// Settings can never be the thing that asks a user for a permission.
///
/// This is glue: it holds no decisions of its own, which is why it is not
/// tested.
struct SystemPermissions: Permissions {
    func status(of permission: Permission) -> PermissionStatus {
        let isGranted =
            switch permission {
            case .microphone: MicrophonePermission.isGranted
            case .accessibility: AccessibilityPermission.isGranted
            }

        return isGranted ? .granted : .notGranted
    }
}
