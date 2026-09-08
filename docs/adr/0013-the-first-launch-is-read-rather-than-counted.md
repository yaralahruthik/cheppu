---
status: accepted
---

# The first launch is read, not counted

#20 gives Cheppu the one sequence it shows without being asked: Microphone, Accessibility, the Engine Download, and one Dictation into a field Cheppu owns. A sequence of screens is usually a wizard — a page number kept somewhere, a Next button that raises it, and a Back button that lowers it — and that is not what this is.

Onboarding keeps no page number. `Onboarding` is handed what is true this instant — what macOS says about each permission the chosen Hotkey needs, how the Engine Download is going, and whether words have landed in the field — and answers with the first of those that is not done yet. There is one thing on disk, and it is not a position in the sequence: `OnboardingIsDone`, written when the user reaches the end.

The reason is that every step here is a fact about the machine rather than a page the user has turned. A permission can be granted in another app while the window is open, taken away a minute later, or have been granted last week by a build the user has since replaced. An Engine can already be on the machine, or be half-fetched by an attempt that a dropped connection ended. Each of those is a question with an answer, and the answer can change while the user is looking at it. A counter would have to be kept in step with all of them, and every case where it drifted would be the same failure: a first launch that either asks for something the user has already granted, or walks past something they have not.

Reading it has three consequences that a counter would have had to be taught one at a time, and each of them is somebody's actual first launch:

- Somebody who granted the Microphone to a build they ran last week opens on Accessibility. Nothing was skipped; that step was already done.
- Somebody who quits halfway through the download opens on the download, with what already arrived counted, rather than at the top.
- Somebody who turns Accessibility off in System Settings while the practice screen is up is put back on the Accessibility step, where the reason and the pane are — rather than left pressing a Hotkey that macOS has stopped handing keys to, which is the silence ADR-0011's ticket (#17) exists to rule out.

There is no Back button, because there is nothing to go back to: a step the user is past is a thing that is true, and the way to see it again is to make it untrue. There is no Skip either. Skipping the Microphone would produce a Cheppu that cannot hear, and the sequence exists to hand the user an app that works.

The completion flag is written at the end and nowhere else. Somebody who closes the window at the download has not dictated yet, and the next launch owes them the rest of it. Closing the window is always allowed — it is a window, and the menu bar keeps saying which permissions are missing for as long as they are (#17) — so the sequence can be left and is never a trap.

## Consequences

- `Onboarding` lives in the core beside `SettingsScreen` and `MenuBarMenu`: it decides which step, what each screen says and what its button reads, and the app performs it. It is a value with no memory, so every case above is a test rather than a walk-through.
- The permissions asked for are `Permission.neededBy(hotkey)`, exactly as in Settings, so a user dictating on the right Option key is never shown Input Monitoring and the count on the screen says "of 4" rather than "of 5".
- Onboarding is the only place Cheppu puts the macOS Microphone prompt up outside a Dictation. macOS shows it once; the screen offers the prompt until it has been shown and the System Settings pane afterwards, so a refusal is not a first launch nobody can get past.
- The Engine Download is started by the user pressing a button, not by the screen appearing. It is 600 MB over somebody else's connection, and ADR-0005 makes it the only network path Cheppu has; a path that opened itself would be one the user never agreed to.
- `MenuBarController` no longer fetches the Engine silently at launch for everyone. It shows the first launch on the launch that is owed one, and keeps the silent fetch for afterwards — a user who has already been shown the download once and had their Engine go missing is not made to watch it again.
- The step counter on the screen — "Step 2 of 4" — is counted from the same reading and kept nowhere. It says how far there is to go, which is what makes a sequence somebody finishes, without becoming a position anything can be wrong about.
- The practice step ends when words are *pasted* into the field, not when the field changes. An Insertion is a paste — the Final Text goes on the pasteboard and Command-V is typed — so this counts a Dictation and does not count somebody typing, or the stray key of a Hotkey chord landing in the field on the way past. A Command-V the user pressed themselves counts too, and should: what they are pasting is what a Clipboard Fallback just left there, which is a Dictation that ran.
- While the window is on the screen, nothing else says anything about a missing permission. The Hotkey watch meets the same refusal a first launch does and would otherwise put its alert (#17) over the top of the screen asking for the Microphone — two asks at once, in the wrong order, on the very first thing a user sees. It says it again the moment the window is gone.
- `Preferences` grows the one key that is not a switch the user can move. It is the only preference read as `false` when nobody has written it: every other one is on unless the user said otherwise, and a first launch that read as done would be the one launch nobody ever sees.
