---
status: accepted
---

# Escape Cancels a Dictation without taking the key

Pressing Escape while a Dictation is Listening Cancels it. The spec for the MVP (#1) puts it as "Escape is only intercepted while Listening; at all other times it passes through untouched", which reads as Cheppu swallowing the keystroke for the length of a Dictation. Cheppu does not swallow it, at any time. Its watch on the keyboard is a listen-only `CGEvent` tap, which can read an event and can neither change nor drop one, so an Escape that Cancels a Dictation also reaches the app the user is typing in and does whatever Escape does there.

Swallowing it would mean creating the tap as a `.defaultTap` instead, which is the difference between an app that can see every keystroke on the machine and an app that can also take any of them. `Scripts/check-the-hotkey-never-swallows-a-keystroke.sh` exists to keep that from happening by accident, and `docs/product-experience.md` §1 is the reason: a dictation app is trusted before it is liked, and "it cannot eat your keystrokes" is a property of how it is built rather than a promise about what its callback does. Buying a tidier Escape with that is the wrong trade.

What the user loses is that Escape does two things at once: the false start is thrown away *and* the sheet they were dictating into closes. What they gain is that no bug, now or later, can make Cheppu drop a key they meant for someone else.

## Consequences

- Cancel is answered with a Cue of its own (`Cue.dictationCancelled`). It is the only signal that Cheppu heard the Escape at all, because the app the user is in reacts exactly as it would have anyway. It is not the stop Cue, which would say the words are on their way.
- Escape is reported by the Hotkey port wherever it is pressed, and the machine ignores it unless a Dictation is Listening. Nothing about the key's journey to the focused app depends on that decision, so there is no state in which Cheppu has to hurry to make it.
- The one thing Cheppu learns about a key it was not sent is whether it was Escape. The key code is read to answer that and goes no further; every other key remains "the user typed something", as it was. `Scripts/check-cheppu-tells-one-key-apart.sh` keeps it to the one question, because an app that can read what you type is one that could keep it.
- If Escape-only-for-Cheppu is ever wanted, it needs a different mechanism than the tap — and this ADR reopened, not the tap's options changed.
