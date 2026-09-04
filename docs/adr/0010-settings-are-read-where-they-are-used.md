---
status: accepted
---

# Settings are read where they are used, not held

#15 gives the user a window with every switch on it. That raises a question the app has not had to answer before: where the answer to "is this rule on?" lives, and when it is read.

Cheppu keeps every switch in the standard user defaults domain under its bundle identifier (ADR-0004), in one file — `Preferences` — and reads each one at the moment it matters, rather than at launch:

- The **Cue switch** is read as each Cue is about to play, which is what it has done since #10.
- The **three Cleanup rules** are read on the way back from the Engine, immediately before Cleanup turns the Raw Transcript into Final Text. `DictationCore` takes a `CleanupSwitches` port rather than a `CleanupRules` value, and hands the machine whatever the user has set as each Dictation passes through.
- **Launch at login** is not kept in the domain at all. `SMAppService` holds it, and Cheppu reads it back from there — including straight after moving it.
- **Permission statuses** are read from macOS every time the window is drawn, and the window is drawn again whenever Cheppu comes back to the front, because granting one happens in another app and macOS tells nobody.

The alternative was to hand the switches to whoever needs them at launch and push new values when the user moves one. It works, and it is what the `DictationMachine` comment anticipated, but it makes the user's own settings a thing that has to be kept in step: the Settings window, the menu bar's Cue tick, and a `DictationCore` that already exists all hold copies, and each new reader is a new chance for one of them to be stale. The case that breaks it is the ordinary one — someone opens Settings *because* the last Dictation was not what they wanted, flicks a rule, and says the next sentence — and a push that arrived a moment late is a Dictation cleaned the old way with the new switch on screen in front of them. Reading at the point of use has no such moment.

The cost is a preference read on the stop-to-insert path, which `docs/product-experience.md` §7 protects. `UserDefaults` answers from a cache in the process; a lookup is measured in microseconds against a path that has just run a speech model. Reading it once per Dictation, rather than once per word or once per Cue frame, is what keeps that true.

There is no configuration file. A preference is a handful of switches the user set in a window; a file they are expected to find and edit is a second interface with no labels on it. History is the deliberate exception, and it is not a preference — it is everything the user said this week, and it is a file for the reasons ADR-0009 gives.

## Consequences

- `CueSwitch` moves into the core as a port beside `CleanupSwitches`, and `SystemCueSwitch` becomes part of `Preferences`. `PillAndCues` is handed the switch rather than reaching for it, so the target that makes the sound no longer knows where the answer is kept.
- `Preferences` keeps the key `CuesAreOn` it has been writing since #10. A user who turned the sounds off from the menu bar before there was a window still has them off after there is one.
- One key per Cleanup rule, not one value holding all three. A rule added later then arrives on for everyone, rather than off for everyone whose saved value never mentioned it.
- Every switch is on unless the user has said otherwise, and reading a switch nobody has moved writes nothing. The defaults are what Cheppu does, not something it saves on the user's behalf — a launch that wrote them down would freeze today's answers into a machine that never asked for them.
- Launch at login is read back from the system after being moved, so an attempt that would not take — an unsigned build run out of a build directory, or a user who switched Cheppu off in Login Items — leaves the switch where the system says it is rather than where the click put it.
- The Settings window and the menu bar move the same Cue switch, and the window says so: moving it redraws the menu, so the tick and the sound can never disagree.
- `Scripts/check-settings-are-one-domain.sh` fails the build if any target other than `Preferences` reaches for `UserDefaults`, or if the Settings target grows a file of its own. The promise is structural rather than reviewed, like the network, audio and History promises before it.
