---
status: accepted
---

# Terminals are found by what a text surface looks like, not by what a Terminal looks like

A newline in a Terminal is Return. A Paragraph Break inserted into one runs whatever is on the line, which is the only place in Cheppu where inserting exactly what the user said is worse than inserting something slightly different. So #12 asks for Paragraph Breaks to be flattened to a single space when the Target App is a Terminal, and for Terminals to be identified "by a committed bundle identifier list plus a check of the focused element's accessibility role, so an unrecognised terminal emulator degrades to the safe behaviour rather than the dangerous one".

The bundle identifier list is straightforward. The role check, read the obvious way — a second committed list, of the accessibility roles Terminals have — cannot be built, because there is no such role. macOS has no `AXTerminal`: the emulators that expose an accessibility tree at all expose the same `AXTextArea` that TextEdit, Xcode and every mail window expose, and the recent ones that draw their screen on the GPU expose nothing to ask about at all ([Warp's own issue asking for one](https://github.com/warpdotdev/warp/issues/11160) is open). A list of Terminal roles would therefore match nothing that is not already on the bundle identifier list, and every emulator nobody had named yet would get the dangerous behaviour — the exact outcome the ticket adds the check to prevent.

So the list is inverted. `Terminal.textSurfaceRoles` names the roles that mean *somewhere text is written* — `AXTextArea`, `AXTextField`, `AXComboBox`, `AXWebArea` — and everything else is treated as a Terminal, including an app that answers nothing about what the keyboard is pointing at. That is the same rule as the ticket's, stated over the evidence that exists: Cheppu can enumerate text surfaces, and cannot enumerate Terminals.

The two halves then fail in opposite directions and cover each other. The bundle identifier list is exact and incomplete, and it is what keeps Terminal.app and iTerm2 safe despite both reporting an ordinary text area. The role check is inexact and complete, and it is what catches Ghostty, Alacritty, kitty, WezTerm and whatever is written next.

## Considered options

- **A committed list of Terminal accessibility roles**, as the ticket reads. Rejected because it would ship as dead code: there is no role to put in it that a Terminal has and an editor does not.
- **The bundle identifier list alone.** Simplest, and never wrong about an app on it. Rejected because "an emulator we have not heard of runs a command the user did not type" is precisely the failure the ticket exists to rule out, and the list of terminal emulators on macOS grows every year.
- **Reading the focused element's value to see whether it looks like a shell prompt.** Rejected outright. That is reading the user's Terminal in order to insert into it, which `docs/product-experience.md` §1 rules out; a dictation app that can see what is on your screen is one that could keep it.

## Consequences

- An app whose focused element Cheppu does not recognise loses its Paragraph Breaks. The cost is a line break the user can add back, against a command they did not run, and the asymmetry is the whole reason the list points the way it does. `Terminal.textSurfaceRoles` is the place to fix a false positive, and adding a role to it is cheap. It holds roles and not subroles: a search field's role is `AXTextField`, and `AXSearchField` — which is what it is a subrole of — would sit in the list matching nothing.
- The same is true when Accessibility has been revoked: the focused element cannot be read, so every app looks like a Terminal and every Dictation arrives on one line. That is a degradation and not a failure — Insertion itself needs the same grant to type the paste, so a Dictation in that state was not going to land anyway.
- The focused element is read with a fifth of a second's patience rather than the accessibility API's default six seconds, because it is read on the path between the user finishing speaking and their words appearing (`docs/product-experience.md` §7). An app too busy to answer in time is treated as a Terminal, so giving up early is safe as well as fast.
- A Terminal *inside* another app is not one. Dictating into VS Code's integrated terminal keeps its Paragraph Breaks, because the app with focus is an editor and the focused element is a text area. Nothing Cheppu can see from the outside tells the two panes apart, and the alternative — treating a whole editor as a Terminal — would cost every user their paragraphs to protect a pane most of them are not in.
- The behaviour lives at the Insertion boundary, in `FinalText.normalisedForInsertion(into:)`, and never in a Cleanup rule. Cleanup stays a pure function of the transcript and the user's switches, so History keeps the Paragraph Breaks and only the Terminal is spared them. `Scripts/check-cleanup-is-a-pure-function.sh` fails the build if a rule ever names the Target App.
- `TargetApp` carries the focused element's role, which is a property of the moment rather than of the app. So "has focus moved?" is asked with `isTheSameAppAs(_:)` — the process identifier, which is what the question means — rather than by comparing two whole readings. Clicking from a field to the button beside it no longer reads as the user leaving.
