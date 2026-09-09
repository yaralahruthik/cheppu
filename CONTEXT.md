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
The on-device speech-to-text model that turns audio into a Raw Transcript, and reads the user's Spellings while it does. The MVP ships exactly one. It is in two parts: what every Dictation needs, and the smaller part that only Spellings need, which hears the audio a second time to find where a Spelling was said.
_Avoid_: model, backend, provider, recognizer

**Engine Download**:
The download that puts the Engine's files on the machine under Application Support, and the only network access Cheppu ever makes. It happens in two moments and never on its own: Onboarding fetches what every Dictation needs, and the part only Spellings need is offered at the first Correction, with what it weighs said at that moment and never before, and offered again from Settings for as long as it is missing. Resumable, so a fetch that stopped is picked up where it stopped by the next offer taken, and never at launch, which is not a moment the user chose to spend their connection on.
_Avoid_: model download, install, setup, second download

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
The list of recent Final Texts kept on the machine so a Dictation is never lost. Written before Insertion is attempted, so a Dictation whose Insertion failed is in it too. Holds Final Text and a timestamp only — never audio, never the Raw Transcript, and never which app the words went into — keeps the hundred most recent and drops the rest, and is emptied in one action (ADR-0009). The one place a Correction is made, and the one place Spellings are read and removed by hand: a short section above the Dictations, there only while there is a Spelling to show or the part of the Engine they need to be offered. Emptying History leaves the Spellings, which are useful after the Dictations they came from are gone.
_Avoid_: log, transcripts, recordings

**Correction**:
The user changing a word or phrase of a Final Text, inside Cheppu, to what they actually said. The only way Cheppu ever finds out it was wrong: nothing is read out of the Target App after Insertion, so a word fixed there is a word Cheppu never hears about. Made by editing the entry in History, in place, and read off as the difference between what the entry said and what it says now. A Correction changes the Final Text History keeps, and the timestamp does not move; nothing is inserted again and the clipboard is not touched, because the words are already where they went. Each changed span of one to three words and at least three letters is left behind as a Spelling. A change outside those bounds — a sentence reworded, a row emptied, "to" made "too" — is still an edit of History and teaches nothing, silently, in the manner of a Discard. What the Engine heard in the Spelling's place is used at that moment and kept nowhere.
_Avoid_: edit, fix, feedback, training, learning

**Spelling**:
A word or phrase the user has shown they say, written the way they want it written. Left behind by a Correction, and read by the Engine so that the next time the sound is heard, the Spelling is what it produces — where the sound supports it, and never as a rule that swaps one string for another, because a rule has no ears and would swap the word where the user meant the other one. A set of words with no memory of what each replaced, so two Spellings cannot conflict: where the user has left two behind for one sound, the Engine takes the closer and the user removes the other. Read only while the part of the Engine that can hear where one was said is on the machine, and only while the Settings switch says to; off keeps them and stops reading them, so a Spelling suspected of misfiring can be ruled out in one flick. Nothing is heard twice until the first one exists, so a user who never corrects pays nothing on the stop-to-insert path. Kept on the machine under the promises History is kept under: readable, removable one at a time in the History window, emptied in one action of their own that Emptying History does not perform, and never leaving the machine. Not measured by the Accuracy Corpus, whose Ceilings watch the bare Engine; proven instead by one fixture the bare Engine gets wrong and one Spelling that puts it right.
_Avoid_: vocabulary, dictionary, custom word, learned word, term, boost

**Diagnostics Log**:
The local file of what Cheppu did, kept so that a problem can be sent to somebody who can fix it without sending what was said. It records the states a Dictation moved through, what moved it between them, the refusals it met, and — because every line says when it happened and how long after the one before it — how long each of those took, which is where a stop-to-insert budget that has been missed is read off. It holds no audio, no Raw Transcript and no Final Text, and cannot: nothing a line is made of can carry a word, and a failure is written down by the type it is rather than by what it says about itself. It says nothing of the Target App either, for the reason History does not. Two files and no more, each of a size, so it cannot grow without end. It is the whole of the diagnostic story — no telemetry, no crash reporter, no analytics, and no network path (ADR-0012) — and it sits in `Application Support/Cheppu/` beside History and the Engine, where the user can read it before they decide to share it and delete it in the same drag (ADR-0009). A note is taken and let go of rather than waited on, because notes are taken on the stop-to-insert path and nothing on it may wait for a disk.
_Avoid_: telemetry, analytics, crash report, debug log

**Settings**:
The one window everything the user can set is on: the Hotkey, the three Cleanup switches, the Cues, launch at login, what macOS says about each permission the chosen Hotkey needs, the one action that empties History, and one row for Spellings — whether they are read, how many there are, and the one action that forgets them all, or, while the part of the Engine they need is missing, that it is and the offer to fetch it. One screen, no tabs, and nothing to scroll for. It asks for no permission the Hotkey does not need: Input Monitoring is a row on it only while the Globe key is the Hotkey, and is asked for at the moment that key is chosen and at no other. Every switch takes effect where it is flicked rather than on the way out, because there is no way out — the window has no OK and no Cancel. What it moves is kept in the standard user defaults domain and read where it is used, never held (ADR-0010); there is no configuration file anybody is expected to find.
_Avoid_: preferences, options, config, panel

**Onboarding**:
The first launch, and the only window Cheppu opens without being asked: each permission the chosen Hotkey needs, the Engine Download, and one Dictation into a field Cheppu owns, in that order and one screen at a time. Not a wizard: nothing remembers a page. The step is the first of those things that is not true yet, read afresh each time the screen is drawn (ADR-0013), so a permission granted last week is a step nobody sees, a download a dropped connection ended is picked up where it stopped rather than started again, and a grant taken away while the window is open puts the user back in front of the pane it is granted on. The "Step 2 of 4" the user reads is counted from that same reading rather than kept anywhere, and counts this user's steps: a Hotkey needing a third permission is a sequence with one more thing in it. The practice Dictation is every other Dictation — the same Hotkey, microphone, Engine and Insertion — and differs only in its Target App, so that a first attempt cannot fail for a reason that belongs to somebody else's text box. It has landed when words are pasted into that field, which is how an Insertion arrives and is not how typing arrives: the one step that exists to prove a Dictation works cannot be ended without one. It ends on a screen naming the Hotkey, because the user is about to close the window and press it. Seen once: it is over when the user reaches that screen, and a sequence left halfway through is owed to them again at the next launch.
_Avoid_: setup wizard, welcome flow

### Accuracy

**Accuracy Fixture**:
One piece of the author speaking, and the words they actually said: a 16 kHz mono `.wav` and a `.txt` sharing a name. The author's own voice and vocabulary rather than a public benchmark set, because what is being measured is whether Cheppu hears the person using it, and a good score on somebody else's read-aloud corpus would say nothing about that. Committed at exactly what the Engine hears in, so that what is measured is the Engine and not a resampler on the way to it. Made in an app of the user's own and converted, never by a script that opens the microphone: a script that did would ask macOS for Microphone access on behalf of a terminal and grant it to everything ever run there. The file it was converted from is kept beside it and read by nothing, because the same sentence cannot be said twice.
_Avoid_: sample, clip, test case, recording

**Accuracy Corpus**:
Every Accuracy Fixture, taken together. It covers technical terms, proper nouns and long-form dictation, and covers them by name rather than by claim — the three are files the suite insists on finding, so the coverage is a fact about the repository rather than a sentence in a comment. Measured as one number rather than as an average of rates, so that ten seconds of "testing one two three" cannot weigh as much as two minutes of dictation. A corpus that quietly shrinks is a Ceiling that quietly stops meaning anything, so a fixture that has lost half of itself is an error rather than a fixture skipped.
_Avoid_: dataset, test set, benchmark

**Reference Transcript**:
What was said in an Accuracy Fixture, written down by the person who said it. What was said rather than what they meant to say: a word stumbled over is in the audio and belongs in the reference too, because the Engine has to hear the user on an ordinary day and not only on a rehearsed one. Punctuation and case are in it for the reader's sake and count for nothing — the measurement erases both, since they are Cleanup's business and are tested there.
_Avoid_: ground truth, expected output, label, gold standard

**Word Error Rate**:
How wrong the Engine was over the Accuracy Corpus: the words it heard as some other word, the words it missed and the words it invented, over the words that were actually said. The denominator is what was said rather than what was heard, so an Engine that invents a hundred words is not rewarded with a bigger one. Measured two ways, because "wrong" is two questions. *As spoken* forgives the ways two faithful transcripts of the same sounds get written differently — a number in digits, a compound split in two, a contraction, an American spelling of a word the author spells the British way — and is what published speech-recognition rates are measured under. *As written* forgives none of them, because they are still words the user goes back and fixes. Neither is the true one, which is why there is a Ceiling for each: the Engine no longer hearing a word is not the same event as the Engine rendering it differently, and one number would report the two identically.
_Avoid_: accuracy, WER, score, quality

**Ceiling**:
How wrong the Engine is allowed to be before CI goes red. Never invented up front: each is the first rate measured on the Accuracy Corpus plus a small absolute margin, recorded beside the day, the chip and the Engine version it was measured with, so that the test catches Cheppu getting worse rather than asserting a standard it has never met. Raising one is allowed and is meant to be uncomfortable, and lowering one after a genuine improvement is the other half of the same discipline — a Ceiling left far above an Engine that has got better is a test that has stopped measuring anything. Not the Cap, which is a limit on how long one Dictation may run.
_Avoid_: threshold, budget, target, baseline
