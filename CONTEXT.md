# Cheppu

A local-first macOS voice dictation app. You press a key, speak, and the words appear where your cursor is. Nothing leaves the machine.

## Language

### Core flow

**Dictation**:
One complete cycle: activation, speech, transcription, and insertion. The unit everything else hangs off.
_Avoid_: recording, session, capture

**Activation**:
The gesture that starts and stops a Dictation, performed with the Hotkey. Two forms exist: Toggle and Hold.
_Avoid_: trigger, invoke

**Toggle**:
An Activation where a short tap of the Hotkey starts the Dictation and a second tap stops it.
_Avoid_: click mode, tap mode

**Hold**:
An Activation where the Dictation runs only while the Hotkey is held down and stops on release.
_Avoid_: push-to-talk, PTT, press-and-hold

**Spoiled Press**:
A press of the Hotkey that turns out to be typing — a key struck, or another modifier joined, inside the quarter-second that tells a tap from a Hold. Escape is not one of those keys: held with the Hotkey it Cancels, because someone reaching for it is throwing the Dictation away rather than typing. The Dictation it opened on the way down is taken back at once and never transcribed: it ends a Dictation the user never asked for, unlike Cancel and Discard, which end one they meant. The start Cue has already played and no stop Cue answers it, which is the price of starting on the way down. A key struck later belongs to a Hold, and what was said is kept.
_Avoid_: false trigger, accidental activation, misfire

**Hotkey**:
The single user-configurable key or key chord that performs Activation. Two shapes, and no third: a Bare Modifier or a Chord. Defaults to the right Option key on its own, which does nothing on its own in any app and needs no permission beyond the one watching the keyboard already needs. Changed from Settings, where it takes effect on the next press rather than the next launch — the watch reads it where it uses it (ADR-0010) — and where what choosing it costs is said at the moment it is chosen and never before: a Chord macOS already uses would be doubled rather than taken away, because Cheppu cannot swallow a keystroke (ADR-0006), and the Globe key needs Input Monitoring and a macOS setting or it does nothing at all. Only the one key the user chose is ever told apart from the ones they type (ADR-0011).
_Avoid_: shortcut, keybinding

**Bare Modifier**:
A Hotkey that is one modifier key held on its own — the fastest thing there is to press, and the default. Reported only while nothing else is held with it, and taken back as a Spoiled Press the moment the user types with it, because a modifier held with a letter is somebody typing an accented character rather than reaching for Cheppu.
_Avoid_: single key, modifier-only hotkey

**Chord**:
A Hotkey that is a key struck while exactly a set of modifiers is held — ⌃⌥D — and no more of them, so a chord with something extra held is somebody else's shortcut. Which side of the keyboard those modifiers are on does not matter, because it does not matter to macOS and is not what the user was shown. Never a Spoiled Press: a Chord was unambiguous the moment it was struck, so a key brushed during a Hold on one — a modifier included — is a key brushed during a Dictation, and what was said is kept. It ends when one of its own keys is let go of. The one key it is built on is the one key Cheppu tells apart from what the user types (ADR-0011).
_Avoid_: key combination, shortcut, combo

**Engine**:
The on-device speech-to-text model that turns audio into a Raw Transcript. The MVP ships exactly one.
_Avoid_: model, backend, provider, recognizer

**Engine Download**:
The one-time download that puts the Engine's files on the machine under Application Support. Resumable, and the only network access Cheppu ever makes.
_Avoid_: model download, install, setup

**Raw Transcript**:
The text exactly as the Engine produced it, before Cleanup.
_Avoid_: transcription, output

**Cleanup**:
The deterministic, rule-based transformation of a Raw Transcript into Final Text. Never involves a language model.
_Avoid_: post-processing, AI rewrite, formatting, enhancement

**Filler Word**:
One of a fixed, committed list of hesitation sounds — "um" and "uh", and the spellings the Engine gives them — that Cleanup drops. Only hesitation is on the list: "hmm", "ah" and "like" carry meaning, and dropping one would turn what the user said into something they did not.
_Avoid_: stop word, disfluency, verbal tic, hesitation marker

**Final Text**:
The text that is inserted into the Target App and kept in History. What the user thinks of as "what I said".
_Avoid_: result, cleaned transcript

**Insertion**:
Placing Final Text at the text cursor of the Target App as if the user had typed it.
_Avoid_: pasting, typing, injection, output

**Clipboard Fallback**:
What happens when Insertion is not possible: the Final Text is left on the clipboard and the Pill says so. What is left is the text the Insertion was handed rather than the text History keeps — trimmed, and with its Paragraph Breaks already flattened where the Target App is a Terminal — because the user's next keystroke is the paste, and it goes into the window the Insertion was for. What could not be typed is what is left to paste. Never silent, and never lost — the words are in History before Insertion is ever attempted. Every way an Insertion fails to land ends here, including one Cheppu has no name for, and the user is told the same thing about all of them, because what they do about it is the same. The one path on which what was on the clipboard before is *not* put back: the words the user could not have typed for them are worth more than the thing they had copied.
_Avoid_: copy mode, error

**Cancel**:
Aborting a Dictation while listening, via Escape. The audio is discarded and nothing is inserted or kept. Answered with a Cue of its own, because Escape is never taken from the app the user is in (ADR-0006) and there would otherwise be nothing to tell them Cheppu heard it.
_Avoid_: abort, stop

**Discard**:
Dropping a Dictation automatically because it was too short or produced no text. Silent by design, unlike Cancel.
_Avoid_: ignore, skip

**Cap**:
The five-minute limit on a single Dictation. Reaching it stops the Dictation and transcribes normally.
_Avoid_: timeout, max length

**Paragraph Break**:
A newline that Cleanup inserts where the speaker paused long enough between sentences to mean a new paragraph.
_Avoid_: line break, pause detection

**Target App**:
The application that has keyboard focus at the moment the Dictation stops, and that receives the Insertion.
_Avoid_: destination, frontmost app, active window

**Terminal**:
A Target App where a newline is Return rather than a line break, so a Paragraph Break inserted into one would run a command the user did not type. Every Paragraph Break becomes a single space before Insertion into one, at the Insertion boundary and never in a Cleanup rule — what is kept is what was said. The Clipboard Fallback is the other side of that same boundary: a newline Cheppu would not type into a Terminal is not one it leaves there to be pasted either. Known by a committed list of bundle identifiers, and otherwise by the keyboard not pointing at anything Cheppu recognises as somewhere text is written, so an emulator nobody has named yet — or one too busy to answer — is treated as one (ADR-0008).
_Avoid_: shell, console, command line

### Feedback and memory

**Pill**:
The small floating overlay that appears during a Dictation and shows its state and the live input level. It draws the two states a Dictation is in while it runs and says the two it can end in — the Clipboard Fallback, and a Missing Permission — in words, staying up long enough to be read before it goes.
_Avoid_: HUD, overlay, indicator, widget

**Input Level**:
How loud the microphone is hearing, from silence to the loudest it can hear, reported continuously while a Dictation is listening and drawn by the Pill.
_Avoid_: volume, amplitude, meter, VU

**Cue**:
A short sound played when a Dictation starts, when it stops, and when it is Cancelled. The Cancel Cue is distinct from the stop Cue, which says the words are on their way. Cues can be turned off, for dictating in a room with other people in it, and off is silent rather than quieter; the Pill cannot be turned off (ADR-0007).
_Avoid_: beep, chime, sound effect

**Notice**:
What the Pill says in words rather than draws, and what it stays up for after a Dictation is over — long enough to be read, and then gone. There are two. A Clipboard Fallback's says the words are on the clipboard, and says where they are and never why they are there: what the user does next is paste, whichever way the Insertion failed. A Missing Permission's names the permission, because which one it is *is* what the user does next.
_Avoid_: toast, alert, banner, message

**Missing Permission**:
A permission Cheppu needs that macOS does not currently grant — never answered for, refused, or granted once and taken away since. Never met in silence: the Dictation that meets one ends with the Pill naming it in a Notice, Cheppu says why in one line and offers the pane it is granted on, and the menu bar goes on offering that pane for as long as it is missing. Which permission it is is the whole of what the user can act on, so it is carried from the refusal to the sentence they read to the pane a button opens rather than being decided again at each. A refusal no pane can undo — no microphone attached — is not one of these (`AudioCaptureFailure.permission`). Cheppu keeps asking macOS whether it may still watch the keyboard, because nothing tells an app when a grant goes and a Hotkey that has quietly stopped arriving is indistinguishable from one nobody pressed; the Microphone is not part of that question, since a microphone switched off must not be what stops the key arriving.
_Avoid_: permission error, unauthorised, revoked

**History**:
The list of recent Final Texts kept on the machine so a Dictation is never lost. Written before Insertion is attempted, so a Dictation whose Insertion failed is in it too. Holds Final Text and a timestamp only — never audio, never the Raw Transcript, and never which app the words went into — keeps the hundred most recent and drops the rest, and is emptied in one action (ADR-0009).
_Avoid_: log, transcripts, recordings

**Settings**:
The one window everything the user can set is on: the Hotkey, the three Cleanup switches, the Cues, launch at login, what macOS says about each permission the chosen Hotkey needs, and the one action that empties History. One screen, no tabs, and nothing to scroll for. It asks for no permission the Hotkey does not need: Input Monitoring is a row on it only while the Globe key is the Hotkey, and is asked for at the moment that key is chosen and at no other. Every switch takes effect where it is flicked rather than on the way out, because there is no way out — the window has no OK and no Cancel. What it moves is kept in the standard user defaults domain and read where it is used, never held (ADR-0010); there is no configuration file anybody is expected to find.
_Avoid_: preferences, options, config, panel

**Onboarding**:
The first-run sequence: permissions, Engine download, and one successful Dictation in a field the app controls.
_Avoid_: setup wizard, welcome flow
