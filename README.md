<h1 align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./docs/brand/cheppu-lockup-dark.svg">
    <img alt="Cheppu — చెప్పు" src="./docs/brand/cheppu-lockup.svg" width="260">
  </picture>
</h1>

**Cheppu** (Telugu: "tell me") is a local-first voice dictation app for macOS.

Press a key. Speak. The words appear where your cursor is. Nothing leaves your Mac.

## What it is

A menu bar app that turns speech into text in whatever app you are typing in. It is built around two goals, in this order:

1. **Accuracy.** What you said is what gets inserted. The transcription engine is chosen for the lowest error rate that runs on your machine, not for the smallest download.
2. **Simplicity.** One hotkey, one engine, one path from voice to text. No modes, no prompts, no accounts.

Everything runs on-device. There is no server, no telemetry, and no network access except to fetch the engine.

## How it works

1. Tap the hotkey to start dictating, or hold it down to dictate only while held. The default hotkey is the right Option key on its own. Any bare modifier or key chord can be set instead.
2. A small floating pill shows that Cheppu is listening, with a live input level that moves with your voice. It never takes the keyboard from the app you are typing in, and it steps out of the way of the field you are dictating into. A short sound confirms start and stop, and the sounds can be turned off for dictating in a meeting.
3. Tap again, or release the key. Cheppu transcribes the audio on-device.
4. The text is inserted at your cursor in the app you were using. Your clipboard is left as you had it.

If Cheppu cannot insert into the focused app — it refused the paste, you moved to another window while it was transcribing, or Accessibility was taken away — the text is placed on your clipboard and the pill says so. That is the one time your clipboard is not put back as you had it: what you said is there instead, for you to paste where you meant it to go. Every dictation is also kept in History, so nothing you said is lost. A dictation with no speech in it disappears silently, and one left running stops itself after five minutes.

Press Escape while listening to cancel: the audio is thrown away and nothing is inserted or kept. Cheppu never takes the key from the app you are in — it can read your keystrokes and cannot swallow them, by construction ([ADR-0006](./docs/adr/0006-escape-cancels-a-dictation-without-taking-the-key.md)) — so Escape also does whatever it would have done where you are typing, and a sound of its own tells you the dictation is gone.

## What ships in the MVP

- One transcription engine: NVIDIA Parakeet TDT v3, running on Apple Silicon via CoreML. English only.
- Tap-to-toggle and hold-to-talk on a single configurable hotkey.
- Transcription after you stop speaking, not live partials. Final results only.
- Deterministic cleanup: sentence capitalisation, filler-word removal, and paragraph breaks on long pauses, each switchable.
- A five-minute cap per dictation, so a forgotten toggle cannot record forever.
- A recording pill with input level, plus start and stop sounds that can be turned off from the menu bar ([ADR-0007](./docs/adr/0007-the-cues-can-be-silenced-and-the-pill-cannot.md)).
- Text-only History of the last 100 dictations, opened from the menu bar, copied one at a time and cleared in one action. It is one file under `~/Library/Application Support/Cheppu/`, readable by nobody but you ([ADR-0009](./docs/adr/0009-history-is-a-file-of-its-own-not-a-preference.md)). Every dictation is written to it before insertion is attempted, so a failure on the way out costs you nothing. Audio is discarded after transcription.
- Corrections: fix a word in History and Cheppu gets it right next time. Editing an entry in place changes what History keeps — the timestamp does not move, nothing is inserted again, your clipboard is untouched — and leaves the word you wanted behind as a **spelling**. Spellings are not a find-and-replace list: the engine hears the audio a second time through a small CTC model and puts one in only where the sound supports it, so "I'll chip you in for lunch" is safe from a spelling of *Cheppu* ([ADR-0014](./docs/adr/0014-spellings-bias-the-engine-and-are-paid-for-at-the-first-correction.md)). They live in a file of their own beside History, are listed and removed one at a time in the History window, and survive clearing History. Reading them needs a second part of the engine, offered at your first correction with its size on the button and never fetched before that.
- A settings window that fits on one screen, opened from the menu bar: the hotkey, the cleanup toggles, sounds, launch at login, what macOS says about each permission your hotkey needs, History's one clear action, and one row for spellings — whether they are read, how many there are, and the one action that forgets them all. No tabs, no OK button — every switch takes effect where you flick it and is read again by the next dictation ([ADR-0010](./docs/adr/0010-settings-are-read-where-they-are-used.md)).
- A configurable hotkey: any bare modifier, or any chord. Press "Change…" and press the key you want. It works on the very next press, in whatever app you are in, and survives a relaunch. Pick a chord macOS already uses and Cheppu says what macOS does with it before it takes it — you would get both, because Cheppu cannot take a keystroke from another app ([ADR-0006](./docs/adr/0006-escape-cancels-a-dictation-without-taking-the-key.md)). Only the one key you chose is ever told apart from the ones you type ([ADR-0011](./docs/adr/0011-one-question-of-a-key-and-only-the-one-the-user-chose.md)).
- Terminal awareness: paragraph breaks are never pasted into a terminal, where a newline can run a command. An emulator Cheppu has never heard of is treated as one too ([ADR-0008](./docs/adr/0008-terminals-are-found-by-what-a-text-surface-looks-like.md)).
- A first launch that walks you through it once: the permissions your hotkey needs, each with one line saying why and a button that opens the right System Settings pane; the model, with a real size and a real progress bar, resuming where it stopped if the connection drops; and one dictation into a box inside Cheppu's own window, so a first attempt cannot fail because of another app's quirks. It ends by naming your hotkey, and never appears again ([ADR-0013](./docs/adr/0013-the-first-launch-is-read-rather-than-counted.md)).
- Signed and notarized builds via GitHub Releases and Homebrew, with in-app updates via Sparkle.
- No telemetry, no crash reporter and no analytics. A local log file is the whole diagnostic story: `~/Library/Application Support/Cheppu/Diagnostics.log`, beside History, holding the states each dictation moved through and how long each of them took, and never a word of what you said — nothing a line of it is made of can carry one. It rotates into a second file and keeps no more than the two, so it cannot grow without end, and you can read it before you decide to send it to anybody ([ADR-0012](./docs/adr/0012-the-log-is-told-rather-than-asked.md)).

## What deliberately does not ship in the MVP

- Live streaming transcription while you speak.
- Language-model rewriting, prompts, or "smart" modes.
- Multiple engines, engine selection, or non-English languages.
- Voice-activity auto-stop.
- Audio recordings kept on disk.
- Cloud transcription of any kind.
- Find-and-replace text rules. A rule has no ears, so it swaps the word where you meant the other one; spellings are the alternative ([ADR-0014](./docs/adr/0014-spellings-bias-the-engine-and-are-paid-for-at-the-first-correction.md)).

Each of these is a real feature that a real user wants. They are out because each one adds a way for the core path to be slower, less accurate, or less predictable, and the MVP has to earn trust on that path first.

## Requirements

- macOS 15 or later
- Apple Silicon
- About 600 MB of disk for the model, downloaded on first launch

## Permissions

Cheppu asks for two permissions, each with a one-line reason at the moment it is needed — and for a third only if the hotkey you chose needs it:

- **Microphone**: to hear you, asked for by the first launch, and by the first dictation that needs it on any machine that has never been through one.
- **Accessibility**: to insert text into other apps and to see the hotkey while another app has focus. macOS has no prompt for this one — it is a switch in System Settings — so Cheppu says why in one line and opens the right pane for you. Until it is granted, and again if it is ever taken away, the menu bar menu says the hotkey cannot work rather than leaving you with a key that does nothing.

Settings says what macOS currently thinks of each of them, without you having to start a dictation to find out, and puts a button next to any it does not have that opens the right pane.

A permission granted once can be taken away later, and macOS tells nobody when that happens. Cheppu never meets one in silence. Dictate with the microphone switched off and the pill says which permission is missing and stays up long enough to be read, and Cheppu says why in one line and offers the pane it is granted on — once, until you grant it back. Take away Accessibility and the hotkey stops arriving; Cheppu keeps asking macOS whether it may still watch the keyboard, so within a couple of seconds it says the same thing rather than leaving you with a key that does nothing. The menu bar names every permission that is missing for as long as it is, Settings says so the moment you look, and anything you had already said is in History either way.

Choosing the Fn/Globe key as your hotkey adds one more, **Input Monitoring**, and needs the macOS "Press 🌐 key to" setting changed to "Do Nothing" — without both, macOS acts on the press before Cheppu ever sees it. Cheppu explains both at the moment you choose that key, not before, and asks for Input Monitoring then and never otherwise. On any other hotkey it is not asked for, not mentioned, and not a row in Settings.

## Running it locally

There is no release to install yet — the signed, notarized build and the Homebrew cask are still to come — so running Cheppu means building it. That is one certificate and two commands.

### Make a signing identity first

Do this before granting Cheppu anything, and Accessibility gets granted once rather than once per build.

macOS files a permission under the code that asked for it, and it knows that code by its signature. An ad-hoc signature is pinned to the exact bytes it was made from, so every rebuild is a different app to the system: grant Accessibility, rebuild, and the switch in System Settings still reads as on while the hotkey quietly stops arriving — with nothing to be done about it but removing the entry and adding it again. A signature made with the same identity every time is the same app every time, and the grant outlives the rebuild.

Any code signing identity does, and a self-signed one costs a minute: Keychain Access → Certificate Assistant → **Create a Certificate…**, named `Cheppu Local`, identity type **Self Signed Root**, certificate type **Code Signing**.

### Build it and open it

```sh
CHEPPU_SIGN_IDENTITY="Cheppu Local" ./Scripts/make-app.sh
open dist/Cheppu.app
```

Without `CHEPPU_SIGN_IDENTITY` the bundle is signed ad-hoc and the script says so. It runs perfectly well; it is only the grant that does not survive. Run the app from `dist/Cheppu.app` and never with `swift run` — a grant is filed under the bundle that asked for it, so running the executable directly asks for the Microphone and Accessibility on behalf of your terminal and hands them to everything you ever run in it.

There is no Dock icon and no window. Cheppu is the icon in the menu bar.

### What the first launch asks for

One window, one screen at a time, reading what is true this instant rather than counting: a permission you granted last week is a screen you never see, and a relaunch halfway through opens where you left off.

1. **Microphone**, with the macOS prompt behind it.
2. **Accessibility**, which macOS has no prompt for — the screen says why in a line and has a button that opens the pane it is a switch in. This is the one the hotkey needs.
3. **The Engine**, 600 MB, started by you rather than on your behalf, and resuming rather than starting over if the connection drops. Already on the machine, and the screen is skipped.
4. **One dictation**, into a field Cheppu owns, so that a first attempt cannot fail for a reason belonging to somebody else's text box. It counts when text is *pasted* in, so typing your sentence into it will not get you past it.
5. **The last screen** names your hotkey, and the sequence never appears again.

If Cheppu has been built on this machine before, delete any existing Cheppu row under System Settings → Privacy & Security → Accessibility before granting it again. A row left over from a different signature reads as enabled and does nothing.

### Dictating

The hotkey is the **right Option key** on its own, because it does nothing by itself in any app. Tap it to start and tap again to stop; hold it down and it dictates only while held; press Escape while it is listening and the whole dictation is thrown away — without the key being taken from the app you are in. One you walk away from stops itself after five minutes.

Everything else is in the menu bar: **History…**, **Settings…**, **Play Sounds**, and **Quit Cheppu**, with any permission you are missing named at the top of the menu for as long as it is missing.

### Rebuilding

`make-app.sh` removes `dist/Cheppu.app` before it writes it, so quit Cheppu before building over it:

```sh
osascript -e 'quit app "Cheppu"'
CHEPPU_SIGN_IDENTITY="Cheppu Local" ./Scripts/make-app.sh
open dist/Cheppu.app
```

Two things do not work from a local build, by design rather than by accident. **Launch at login** needs an installed app, so `SMAppService` refuses to register one run out of `dist/`, and the switch snaps back off rather than claiming a launch that will not happen. **In-app updates** are not built yet.

Everything Cheppu has put on your machine is in one folder, and deleting it is a clean slate:

```
~/Library/Application Support/Cheppu/
  Engine/            # the model
  History.jsonl      # the last 100 dictations: text and a timestamp, nothing else
  Diagnostics.log    # states and durations, and never a word of what you said
```

The log is where to look when the hotkey does nothing. `the Hotkey cannot be watched: accessibilityDenied` is what a missing or stale grant says.

## Building

Cheppu is a Swift package of nine targets. `CheppuCore` is the headless core — it decides what happens and imports no OS framework. `CheppuEngine` is Parakeet, and the download that puts it on the machine. `CheppuAudio` is the microphone: the one place Cheppu opens an audio device and asks for Microphone access. `CheppuKeyboard` is the Hotkey: the one place Cheppu watches keys it was not sent and asks for Accessibility. `CheppuInsertion` is the pasteboard and the one keystroke Cheppu ever types. `CheppuFeedback` is the pill and the sounds: the one place Cheppu draws over another app's window or makes a noise. `CheppuHistory` is the History store, the spellings beside it and the window both are read in: the one place Cheppu writes what you said, or what you taught it, to the disk. `CheppuSettings` is everything you can set and the one window you set it in: the only place Cheppu reads or writes a preference. `Cheppu` is the menu bar app that performs what the core decides, including the window the first launch is walked through.

The engine is in two parts, and both live under `~/Library/Application Support/Cheppu/Engine/`, beside History and the log, so everything Cheppu put on your machine is one folder you can find and delete. The first part is Parakeet TDT v3 — 480 MB of CoreML bundles from [`FluidInference/parakeet-tdt-0.6b-v3-coreml`](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), fetched at the first launch, and what every dictation needs. The second is 103 MB from [`FluidInference/parakeet-ctc-110m-coreml`](https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml) — a mel spectrogram, an audio encoder, a token table and its tokenizer — and only spellings need it, so it is not fetched at all until you make your first correction and press the button that says what it weighs ([ADR-0014](./docs/adr/0014-spellings-bias-the-engine-and-are-paid-for-at-the-first-correction.md)). Both are fetched by the same resumable download, from the one file in Cheppu that may open a connection.

```sh
swift build                     # build the core, the Engine, the microphone, the keyboard, the Insertion, the Pill, History, Settings and the app
swift test                      # run the suite
./Scripts/make-app.sh           # assemble dist/Cheppu.app
./Scripts/check-core-is-headless.sh
./Scripts/check-the-download-is-the-only-network-path.sh
./Scripts/check-no-audio-reaches-the-disk.sh
./Scripts/check-the-hotkey-never-swallows-a-keystroke.sh
./Scripts/check-cheppu-types-one-keystroke.sh
./Scripts/check-cheppu-tells-one-key-apart.sh
./Scripts/check-the-pill-never-takes-focus.sh
./Scripts/check-cleanup-is-a-pure-function.sh
./Scripts/check-history-holds-text-only.sh
./Scripts/check-settings-are-one-domain.sh
./Scripts/check-the-log-says-nothing-of-what-was-said.sh
./Scripts/add-an-accuracy-fixture.sh <recording> <name>   # add to the accuracy corpus
```

The suite runs with no permissions granted, no Engine downloaded, no network and no audio device. Nothing in it opens a microphone, creates an event tap, touches your clipboard, types a key, puts a window on your screen or makes a sound, and the only files it writes are in a temporary directory of its own — your own History is never opened, read or cleared by it, and the only preferences it writes are in a domain of its own, so nothing you set is changed by it — so running it never asks your terminal for Microphone or Accessibility access, never disturbs what you had copied, and is silent. Running it needs a toolchain that ships the Swift Testing runtime, which today means Xcode; the Command Line Tools alone can build the app but not run the suite. See [ADR-0003](./docs/adr/0003-swift-package-manager-instead-of-an-xcode-project.md).

Transcribing for real needs the 480 MB Engine, so those tests are off by default and off in CI:

```sh
CHEPPU_LIVE_ENGINE=1 swift test --filter LiveEngineTests
```

They fetch the Engine into `~/Library/Application Support/Cheppu/Engine`, transcribe speech synthesised with `say`, and check that a minute of it comes back in well under a second. See [ADR-0005](./docs/adr/0005-cheppu-fetches-the-engine-itself.md) for why Cheppu fetches the Engine itself rather than letting its dependency do it.

### Accuracy

Everything above runs with nothing downloaded and nothing plugged in, which is what keeps it fast — and none of it can answer the only question that decides whether Cheppu is usable: are the words right. `CheppuAccuracyTests` can. It loads the real Parakeet, transcribes committed audio of the author's own voice, and measures the word error rate against what was actually said:

```sh
CHEPPU_ACCURACY=1 swift test --filter CheppuAccuracyTests
```

The fixtures are the author's voice and vocabulary — technical terms, proper nouns and long-form dictation — rather than a public benchmark set, because a good score on somebody else's read-aloud corpus would say nothing about whether the app is usable by the person using it. Each is two files sharing a name in `Tests/CheppuAccuracyTests/Fixtures`: a 16 kHz mono `.wav` and a `.txt` of what was said. Add one by recording it in an app of your own — Voice Memos, or QuickTime Player — and handing the file over:

```sh
./Scripts/add-an-accuracy-fixture.sh ~/Desktop/recording.m4a long-form-dictation
```

The script converts rather than records. A script that opened the microphone itself would ask macOS for Microphone access on behalf of your terminal and grant it to everything you ever run there; permissions belong to purpose-built bundles.

The file you recorded is kept in `Tests/CheppuAccuracyTests/Originals` and read by nothing. It is excluded from the build rather than made a resource, so it never reaches the test binary — but the same sentence cannot be said twice, and a fixture downsampled to 16 kHz is not recoverable if the Engine ever hears in at something else.

Every fixture is scored twice, because "wrong" is two questions. **What the Engine heard** forgives the ways two faithful transcripts of the same sounds get written differently — "3" for "three", "core ml" for "CoreML", "you're" for "you are", "quantized" for "quantised" — and is the number comparable with a published speech-recognition rate. **What the user reads** forgives none of them, because they are still words you go back and fix. Both have a ceiling, so a red run says which one moved: Parakeet no longer hearing a word is not the same event as Parakeet rendering it differently.

Spellings are not measured by the ceilings, and deliberately: a spelling that made the corpus score better is not the engine getting better, and a ceiling lowered on the strength of one would be a test that had stopped measuring the engine. The mechanism has a test of its own beside them. It transcribes the whole corpus twice — once bare, once with a single committed spelling of *Cheppu*, the one word every user of this app will say and the one the bare engine hears as "Chapo" and "Chepo" — and asserts both that the name comes out right and that nothing else moved. On 10 September 2026 (Apple M4 Pro, FluidAudio 0.15.6) that one spelling took the corpus from 3.81% to 3.00% of what the engine heard and from 9.29% to 8.47% of what the user reads, with no other word touched. The second half of that test is the important one: a spelling that put the word in everywhere would pass the first half and would be exactly the find-and-replace rule [ADR-0014](./docs/adr/0014-spellings-bias-the-engine-and-are-paid-for-at-the-first-correction.md) rejects.

The ceilings in [`AccuracyCeiling.swift`](./Tests/CheppuAccuracyTests/AccuracyCeiling.swift) are each the first measured rate plus two points, not a target somebody picked, so the test catches Cheppu getting worse rather than asserting a standard it has never met. It runs in CI as a job of its own on an Apple Silicon runner — the only hardware Cheppu supports, and the only hardware a CoreML ceiling means anything on — so that a model load never sits between a push and the answer to "does it still build". The checks that the corpus is a corpus (every fixture has both its halves, and all three kinds of speech are covered) need no Engine and run in the fast suite.

## The mark

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./docs/brand/cheppu-mark-dark.svg">
    <img alt="The Cheppu mark: a text caret whose stem is a level meter" src="./docs/brand/cheppu-mark.svg" width="104">
  </picture>
</p>

Cheppu's mark is a text caret whose stem is a level meter: two rails holding the place where the words will land, and three bars saying that something is being heard between them. It draws the promise rather than the machinery — the words appear where your cursor is — and the bars carry the Pill's own rhythm, tallest in the middle, so what you install and what you watch while you dictate are visibly one thing.

It is drawn on a 24-unit grid, and these numbers are the whole of it: rails 14 × 2.4 with a 1.2 radius, at y 2 and y 19.6; three bars 2.4 wide with the same radius, centred on x 8.5, 12 and 15.5, of heights 8, 13 and 8, each centred on y 12. Clear space is four units on every side of the 14 × 20 bounding box, and nothing enters it, the wordmark included. Below 16 pt the gaps between the bars close, so nothing smaller than that ships, and the mark is never outlined — it is solid so that it can be found at a glance in a menu bar that is mostly thin outline glyphs.

Ink is `#211F1C`, terracotta `#C2551F`, ground `#FAF7F2`. Terracotta marks the middle bar on the app icon and in material like this file, and never in the menu bar, where the mark is a template and macOS picks the colour — for the appearance you are in, and for the highlight drawn while the menu is open. The wordmark is *Cheppu* set in Space Grotesk Medium, and the name in the script it comes from is చెప్పు set in Noto Sans Telugu Medium.

The lockup at the top of this file is the mark, the wordmark, and the name in Telugu. The mark stands the height of the text beside it — the wordmark's cap line down to the Telugu baseline — and the wordmark begins six units out, clear space and a half. Both runs of text are outlined rather than set, because an SVG rendered as an image fetches no fonts: set as text, the wordmark would arrive in whatever the reader had to hand, and చెప్పు in nothing at all. That leaves the words with no source but the file they are in, so [`Scripts/draw-the-lockup.py`](./Scripts/draw-the-lockup.py) states the shaping and the spacing instead, and [`cheppu-lockup.svg`](./docs/brand/cheppu-lockup.svg) and [`cheppu-lockup-dark.svg`](./docs/brand/cheppu-lockup-dark.svg) are drawn from it rather than edited by hand.

The mark lives in [`docs/brand/`](./docs/brand/) as three SVGs: [`cheppu-mark.svg`](./docs/brand/cheppu-mark.svg) for light backgrounds, [`cheppu-mark-dark.svg`](./docs/brand/cheppu-mark-dark.svg) for dark ones, and [`cheppu-mark-template.svg`](./docs/brand/cheppu-mark-template.svg), which paints in `currentColor` and is the same shape the menu bar glyph is drawn from. That glyph is drawn in code rather than shipped as an asset: [`MenuBarIcon.swift`](./Sources/Cheppu/MenuBarIcon.swift) states these numbers once more, fits the mark's 14 × 20 of ink into the 18 points AppKit lays a status item out at, and leaves half a point of air above and below so the rails do not sit on the edge. The shape is said twice, so it changes twice or not at all.

## Status

Pre-alpha. The product is being designed in the open before code is written. See [`CONTEXT.md`](./CONTEXT.md) for the project vocabulary, [`docs/adr/`](./docs/adr/) for the decisions and their reasons, and [`docs/product-experience.md`](./docs/product-experience.md) for what we think a good dictation app has to get right.

The MVP is done when all of these are true:

- The author uses it as their only dictation tool for two weeks of daily work.
- The word-error-rate test on the committed audio fixtures passes in CI.
- A fresh macOS user account can go from downloading the DMG to a first successful dictation in under five minutes, unassisted.
- A signed, notarized build is on GitHub Releases and installable via Homebrew.

## Inspiration

Cheppu exists because tools like [Spokenly](https://spokenly.app) and Superwhisper showed how good on-device dictation on a Mac can be. Cheppu narrows that idea to a single, open, local path and tries to make that one path excellent.

## License

MIT.
