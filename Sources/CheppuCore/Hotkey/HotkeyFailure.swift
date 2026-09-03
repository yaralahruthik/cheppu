/// Why Cheppu cannot see the Hotkey.
///
/// It lives in the core rather than beside the keyboard for the same reason
/// `AudioCaptureFailure` does: the core is what has to act on it, and it cannot
/// see the framework that would name it, so a failure only the keyboard could
/// describe would arrive as an opaque `Error` — which is the same as not being
/// told.
///
/// Saying it out loud, and pointing at the right System Settings pane, is the
/// app's; noticing a grant that was taken away later is #17's.
public enum HotkeyFailure: Error, Equatable {
    /// Accessibility access has not been granted, or was granted once and taken
    /// away since. Watching the keyboard while another app has focus is what
    /// needs it, so without it the Hotkey does nothing at all — which is
    /// exactly the silence the app has to speak into.
    case accessibilityDenied
}
