# What makes a good voice dictation app

Cheppu's design brief. Every item here is a claim about the user's experience, not about implementation. If a feature or a shortcut in the code violates one of these, the code is wrong.

## 1. It is trusted before it is liked

A dictation app is used hundreds of times a day, mid-thought, in someone else's app. The user is not looking at it. They are looking at the email, the terminal, the chat box. The app gets one chance per dictation to be invisible and correct. The second time it inserts something wrong, or nothing, or into the wrong window, the user starts re-reading every output, and at that point they might as well type.

So the bar is not "usually works". It is: the user stops checking.

## 2. Accuracy is the product

Speed, polish, and features do not compensate for a wrong word. A single misheard "not" inverts a sentence. Choose the most accurate engine that runs on the hardware, even if it is bigger or slower. Prefer final results over provisional ones. Never trade accuracy for the appearance of speed.

Accuracy includes formatting. A transcript with no punctuation or capitalisation is technically correct and practically useless.

## 3. The user must always know the state

There are exactly four states the user cares about: idle, listening, transcribing, done. Each must be unambiguous through at least two senses, because the user's eyes are on their work.

- **Listening** shows a live input level. A static "recording" icon does not answer the question the user is actually asking, which is "can it hear me right now?"
- **Start and stop** each play a distinct sound. Dictation is often started by feel, without looking.
- **Transcribing** is visibly different from listening, so a pause is never mistaken for a hang.
- **Done** is signalled by the text appearing. Nothing else is needed.

## 4. Nothing you said is ever lost

Audio that was captured represents effort the user cannot repeat verbatim. Every dictation must end with its text somewhere the user can get it:

- Inserted into the target app, or
- On the clipboard with a visible notice, if insertion was not possible, and
- In History, always.

A crash, a permission problem, or a focus change must degrade to "the text is in History", never to silence.

## 5. Insertion behaves like typing

The text should land exactly where the cursor was, in the app that had focus when dictation started, with no side effects. That means:

- The clipboard is restored to what it held before. The one exception is the clipboard fallback of §4: where insertion was not possible there is nothing to restore it for, and the text stays there to be pasted.
- Focus does not move.
- No trailing or leading whitespace surprises. If the cursor was mid-sentence, the text joins sensibly.
- It works in native apps, Electron apps, browsers, and terminals alike.

## 6. One gesture, learned once

There is one hotkey. It supports two natural gestures: tap to toggle, hold to talk. Both feel like the same key doing the obvious thing. The user should never have to remember which mode they are in, because there are no modes.

The hotkey is configurable, because keyboards and hands differ. The default should be a key that does nothing on its own in any app and needs no permission the app did not already need, so that the first dictation costs the user nothing to set up.

## 7. Latency has a budget

From the moment the user stops speaking to the moment text appears, the delay should feel like a breath, not a wait. Longer than about a second and the user's attention drifts, and they start to doubt the app heard them at all. Transcription must therefore be well under real time on the target hardware, and the stop-to-insert path must have nothing on it that is not strictly necessary.

## 8. Cleanup is predictable or it is absent

Any transformation between what the engine heard and what gets inserted must be one the user can predict from a one-line description. Capitalising sentence starts and dropping "um" qualify. Rewriting for tone, summarising, or "fixing" grammar do not: they make the app an author, and the user can no longer trust that the output is what they said.

Every cleanup rule has a switch. Off must be a real option.

## 9. Permissions are asked for once, with a reason, at the right moment

Each macOS permission is requested exactly when it is first needed, with one sentence explaining why, and a direct path to the right System Settings pane. If a permission is later revoked, the app says so at the next dictation attempt rather than failing quietly.

## 10. Privacy is structural, not a policy

Audio and text stay on the machine. This is not a setting or a promise. The app has no network code paths after the model download. Audio is discarded after transcription. History holds text only, is stored locally, and can be cleared in one action.

## 11. Settings fit on one screen

If a setting needs a paragraph to explain, it is either the wrong setting or the wrong default. The MVP settings are: the hotkey, the cleanup toggles, start-at-login, and History. That is the whole screen.

## 12. First run is the whole first impression

The first launch has to do three things and make each feel intentional: request permissions, download the model, and let the user dictate one sentence successfully. A large model download that looks like a stall, or a permissions dance that sends the user hunting through System Settings, loses them before the first word.

## What we are measuring ourselves against

- Word error rate on the user's own voice and vocabulary, not a benchmark.
- Stop-to-insert latency, felt, not measured.
- The number of times per day the user re-reads the output before continuing.

The last one is the real metric. It should trend to zero.
