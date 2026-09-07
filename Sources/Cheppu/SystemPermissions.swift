import CheppuAudio
import CheppuCore
import CheppuKeyboard
import CheppuSettings

/// What macOS says about each of Cheppu's permissions, this instant, and the
/// one of them the app can ask for on the user's behalf.
///
/// Assembled here rather than in the Settings window because each answer
/// belongs to the target that owns that piece of the machine: the Microphone is
/// the audio target's, Accessibility and Input Monitoring are the keyboard's,
/// and the app is the one place all of them are in scope. No answer prompts for
/// anything, so opening Settings can never be the thing that asks a user for a
/// permission.
///
/// This is glue: it holds no decisions of its own, which is why it is not
/// tested.
struct SystemPermissions: Permissions {
    func status(of permission: Permission) -> PermissionStatus {
        let isGranted =
            switch permission {
            case .microphone: MicrophonePermission.isGranted
            case .accessibility: AccessibilityPermission.isGranted
            case .inputMonitoring: InputMonitoringPermission.isGranted
            }

        return isGranted ? .granted : .notGranted
    }

    func ask(for permission: Permission) {
        switch permission {
        // The one permission Cheppu asks for because of something the user
        // chose, at the moment they chose it. The Microphone is asked for by
        // the first Dictation that needs it, and Accessibility has no prompt to
        // show — it is a switch in System Settings.
        case .inputMonitoring: InputMonitoringPermission.request()
        case .microphone, .accessibility: break
        }
    }
}
