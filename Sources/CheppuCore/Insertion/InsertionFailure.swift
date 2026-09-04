/// Why the Final Text did not land.
///
/// It lives in the core rather than beside the pasteboard for the same reason
/// `AudioCaptureFailure` and `HotkeyFailure` do: the core is what has to act on
/// it, and it cannot see the frameworks that would name it, so a failure only
/// the Insertion could describe would arrive as an opaque `Error` — which is
/// the same as not being told.
///
/// Every one of these ends with the Final Text in History and nothing typed
/// anywhere. Leaving it on the clipboard and saying so out loud is #14's.
public enum InsertionFailure: Error, Equatable {
    /// The Target App is not the app a keystroke would reach any more: focus
    /// moved to another app between the Dictation stopping and the Final Text
    /// being ready, or nothing has focus at all.
    ///
    /// The words go nowhere rather than into whichever window happened to be
    /// in front when they were ready: a Dictation typed into the wrong app is
    /// worse than one the user has to paste themselves, because they have to
    /// find it and take it back out again.
    case focusMoved

    /// macOS would not let Cheppu synthesise the paste keystroke. Insertion
    /// needs the same Accessibility the Hotkey does, so this is what a grant
    /// taken away mid-session looks like from here.
    case keystrokeRefused
}
