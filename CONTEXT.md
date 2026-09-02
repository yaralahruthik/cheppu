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

**Hotkey**:
The single user-configurable key or key chord that performs Activation. Defaults to the right Option key on its own.
_Avoid_: shortcut, keybinding

**Engine**:
The on-device speech-to-text model that turns audio into a Raw Transcript. The MVP ships exactly one.
_Avoid_: model, backend, provider, recognizer

**Engine Download**:
The one-time fetch that puts the Engine's files on the machine under Application Support. Resumable, and the only network access Cheppu ever makes.
_Avoid_: model download, install, setup, fetch

**Raw Transcript**:
The text exactly as the Engine produced it, before Cleanup.
_Avoid_: transcription, output

**Cleanup**:
The deterministic, rule-based transformation of a Raw Transcript into Final Text. Never involves a language model.
_Avoid_: post-processing, AI rewrite, formatting, enhancement

**Final Text**:
The text that is inserted into the Target App and kept in History. What the user thinks of as "what I said".
_Avoid_: result, cleaned transcript

**Insertion**:
Placing Final Text at the text cursor of the Target App as if the user had typed it.
_Avoid_: pasting, typing, injection, output

**Clipboard Fallback**:
What happens when Insertion is not possible: Final Text is left on the clipboard and the Pill says so. Never silent.
_Avoid_: copy mode, error

**Cancel**:
Aborting a Dictation while listening, via Escape. The audio is discarded and nothing is inserted or kept.
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

### Feedback and memory

**Pill**:
The small floating overlay that appears during a Dictation and shows its state and the live input level.
_Avoid_: HUD, overlay, indicator, widget

**Cue**:
A short sound played when a Dictation starts and when it stops.
_Avoid_: beep, chime, sound effect

**History**:
The list of recent Final Texts kept on the machine so a Dictation is never lost. Holds text only, never audio.
_Avoid_: log, transcripts, recordings

**Onboarding**:
The first-run sequence: permissions, Engine download, and one successful Dictation in a field the app controls.
_Avoid_: setup wizard, welcome flow
