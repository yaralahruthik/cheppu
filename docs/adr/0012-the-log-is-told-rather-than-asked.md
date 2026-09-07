---
status: accepted
---

# The Diagnostics Log is told rather than asked, and holds a vocabulary rather than messages

#18 asks for "a local log file the user can share when diagnosing a problem without sharing what they said", and adds the constraint that decides how it is built: "whatever is written sits on the stop-to-insert path, which has a latency budget — logging must not spend meaningfully from it." Two decisions follow from those two sentences, and neither is what a logger normally is.

## A note is handed over, not awaited

`DiagnosticsPort.record(_:)` is the only port in Cheppu that is neither `async` nor `throws`. Every other one is a request the core waits on, because the core needs the answer: the microphone hands back what it heard, the Engine hands back a Raw Transcript, History refuses when the disk is full. The log has no answer worth waiting for, and it is written at the two moments a Dictation can least afford to wait — as the user stops speaking, and as the words land (`docs/product-experience.md` §7).

So the note is stamped where it is taken and written somewhere else. What that buys is that the file's timings are honest about moments nothing ever waited for: the line says when the Dictation moved, not when the disk got round to writing that it had. `Scripts/check-the-log-says-nothing-of-what-was-said.sh` fails the build if that signature grows an `async` or a `throws`, because a port that can be awaited is a disk on the stop-to-insert path however carefully today's implementation avoids it.

The queue behind it is bounded and its overflow is written down rather than swallowed. A disk that has stopped answering must cost the user a gap in a file they may never open rather than the app, and a log that quietly skipped an hour would send whoever reads it looking for a Dictation that never failed.

## What is written is a closed vocabulary, and it has no `String` in it

"The log contains no audio, no Raw Transcript and no Final Text, verified by dictating known text and searching the log for it" is an acceptance criterion that a normal logger cannot pass twice. `log.debug("transcribed \(text)")` is one line away at all times, and the tests that grep the file only ever prove that nobody has written that line *yet*.

So there is no way to write a message. `DiagnosticNote` is an enumeration whose cases carry states, permissions, durations and counts, and no `String` anywhere — checked, so the next case added cannot quietly carry one. A `DictationEvent` is never put in a note, because the events carry the audio and the transcripts; `DiagnosticNote.WhatHappened` is the same list of events with everything they carry left off, and the `switch` between them is the one place a transcript could ever have reached the log.

Errors are the hole this leaves, because an error is the one thing on the path that comes from outside Cheppu's vocabulary. `localizedDescription` is where a log stops being a record of what happened and becomes whatever a framework felt like putting in a string — a `URLError` names its URL, a `CocoaError` names its file. So a failure is named by its *type*, which is written into the binary at build time and cannot be something somebody dictated. Cheppu's own failures say more, by conforming to `FailureSafeToName`, and the check reads their cases to hold them to it: a conformer with an associated value fails the build.

## Considered options

- **`os.Logger` / the unified system log.** One line, free, and what every Mac app does. Rejected because it takes the file away: the unified log is not something the user can read before deciding to share it, it is swept up by `sysdiagnose` along with everything else on the machine, and it is a `String` interface — the acceptance criterion above cannot be met by an API whose whole shape is "interpolate whatever you like". It is banned by name in the check.
- **A message with a severity, like every other logger.** Rejected for the same reason: the promise is about what cannot be in the file, and a format string is a promise about what nobody has typed yet.
- **Emitting notes as `DictationEffect`s from the machine.** Rejected. Logging is not a decision the user experiences, and every existing assertion about a Dictation is an exact list of effects — threading notes through them would make every one of those tests about logging as well. `DictationCore` already sees every event and the state on both sides of it, which is exactly and only what the log needs.
- **Writing the words the file shows in the core**, next to `PillState.words` and `Permission.name`. Rejected because those are decisions about what the *user* is told, and the core is where decisions are made; what a line of a log file looks like is the format of a file, and the file belongs to whoever writes it.

## Consequences

- The log cannot record what a Dictation said even by accident, and cannot be made to: it has no case that takes a word.
- It cannot record anything nobody has added a case for, which is the cost. A note worth taking is a change to `DiagnosticNote`, a line in `WrittenLine`, and a review of both.
- Nothing in Cheppu can wait on the log, so nothing in Cheppu can be slowed by it and nothing can be broken by it failing. A log that cannot be written is a log that cannot be written, and the Dictation carries on.
- It is bounded by two files of a known size, rotating, so it is the one thing Cheppu writes that cannot quietly grow for as long as somebody uses the app — the same reason History keeps a hundred Dictations and no more (ADR-0009).
- There is no telemetry, no crash reporter and no analytics dependency to add later without this ADR being reopened: the check pins Cheppu to its one dependency, and the Engine Download remains the only network path (ADR-0005).
