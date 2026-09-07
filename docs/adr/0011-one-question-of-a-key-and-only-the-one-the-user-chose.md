---
status: accepted
---

# One question of a key, and only the one the user chose

#16 lets the user set the Hotkey to a key chord — ⌃⌥D — as well as to a bare modifier. That reopens something ADR-0006 settled: the one thing Cheppu learns about a key it was not sent is whether it was Escape. A chord cannot work under that rule. Cheppu has to be able to tell one ordinary key apart from the rest, in whatever app the user is typing in.

The rule is widened by exactly one question, and the widening is bounded three ways:

- **The key code is read once, in one place.** `SystemKeyboard` reads `.keyboardEventKeycode` at a single call site, for key-down and key-up together, and compares the answer against two keys: Escape, and the position the Hotkey is built on. Nothing else is read off a key event, and the code goes no further than those two comparisons.
- **Nothing carries a key code out of that file.** `KeyStroke` has no case with a key code in it. What leaves is `hotkeyKeyPressed`, `hotkeyKeyReleased`, `escapePressed`, or `keyPressed` — which still means only "the user typed something".
- **Only the key the user chose is told apart.** The keyboard is handed one `Key?` by whoever knows the Hotkey, and a bare-modifier Hotkey hands it nothing: on the default Hotkey no key on the machine is distinguished from any other, exactly as before #16.

Key-up is watched as well as key-down where the Hotkey is a chord, because a Hold on one ends when the key is let go of, and a Dictation that only stopped when the modifiers came up would run on past the words. It is the same question asked of the same field, and it is asked only where a chord needs it: the tap is built without key-up at all on a bare-modifier Hotkey, so the default Hotkey is not sent a single key-up on the machine.

The alternative was to carry the key code up to `HotkeyGesture` and let the gesture decide, which is less code and puts the comparison next to the Hotkey it belongs to. It was rejected because the promise then stops being structural: every key the user types would cross a target boundary as a number, and what stopped Cheppu keeping it would be that nothing currently does.

There is a second reader, and it is a different thing: `HotkeyRecorder`, the Settings window listening for the key the user wants. It uses a local `NSEvent` monitor, which is handed only the events already on their way to Cheppu and can hear nothing outside this app. That is somebody telling Cheppu a key, not Cheppu watching somebody type, and it needs no permission at all.

## Consequences

- `Scripts/check-cheppu-tells-one-key-apart.sh` now allows two files — the tap and the recorder — and requires each of them to read exactly one field off a key event. A second read in either is a build failure, whatever the comment above it says.
- The recorder's monitor swallows the keys pressed at the Settings window while it is listening, so Command-Q on the way to a chord chooses a Hotkey rather than quitting. That is Cheppu's own window; the watch on everybody else's keyboard still cannot swallow a keystroke, and ADR-0006 is untouched.
- Because that watch cannot swallow one, choosing a Hotkey that is already a system shortcut does not take the shortcut away — it doubles it. ⌘Space set as the Hotkey starts a Dictation *and* opens Spotlight. The warning shown at the moment of choosing says that, rather than saying the shortcut will stop working, because what the user has to picture is what will happen.
- A chord is matched with the sides taken off — ⌃⌥D is ⌃⌥D whichever Control key it is — because that is what the user was shown and what macOS itself does. A Bare Modifier is the other way round: the right Option key is the default precisely because it is not the left one.
- A chord press is never spoiled. A bare modifier is ambiguous until the next keystroke settles it — held with a letter it types an accented character — and a chord never was: the user held ⌃⌥ and struck D, which is not something anybody does on the way to typing. So a key brushed during a Hold on a chord is left alone, and what was said is kept.
- Which key is watched for is read where it is used, at the moment watching starts (ADR-0010). Changing the Hotkey is watching again, and the next press is the new one — no relaunch, and nothing held anywhere that could come to disagree with what the user set.
- The Globe key is the one Hotkey that costs a permission of its own. Input Monitoring is asked about only by a Hotkey that uses it, so somebody dictating on the right Option key is never asked for it and never sees it mentioned.
