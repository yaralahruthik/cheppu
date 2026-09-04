# Cheppu

**Cheppu** (Telugu: "tell me") is a local-first voice dictation app for macOS.

Press a key. Speak. The words appear where your cursor is. Nothing leaves your Mac.

## What it is

A menu bar app that turns speech into text in whatever app you are typing in. It is built around two goals, in this order:

1. **Accuracy.** What you said is what gets inserted. The transcription engine is chosen for the lowest error rate that runs on your machine, not for the smallest download.
2. **Simplicity.** One hotkey, one engine, one path from voice to text. No modes, no prompts, no accounts.

Everything runs on-device. There is no server, no telemetry, and no network access after the one-time model download.

## How it works

1. Tap the hotkey to start dictating, or hold it down to dictate only while held. The default hotkey is the right Option key on its own. Any bare modifier or key chord can be set instead.
2. A small floating pill shows that Cheppu is listening, with a live input level. A short sound confirms start and stop.
3. Tap again, or release the key. Cheppu transcribes the audio on-device.
4. The text is inserted at your cursor in the app you were using. Your clipboard is left as you had it.

If Cheppu cannot insert into the focused app, the text is placed on your clipboard and the pill tells you so. Every dictation is also kept in History, so nothing you said is lost. A dictation with no speech in it disappears silently, and one left running stops itself after five minutes.

Press Escape while listening to cancel: the audio is thrown away and nothing is inserted or kept. Cheppu never takes the key from the app you are in — it can read your keystrokes and cannot swallow them, by construction ([ADR-0006](./docs/adr/0006-escape-cancels-a-dictation-without-taking-the-key.md)) — so Escape also does whatever it would have done where you are typing, and a sound of its own tells you the dictation is gone.

## What ships in the MVP

- One transcription engine: NVIDIA Parakeet TDT v3, running on Apple Silicon via CoreML. English only.
- Tap-to-toggle and hold-to-talk on a single configurable hotkey.
- Transcription after you stop speaking, not live partials. Final results only.
- Deterministic cleanup: sentence capitalisation, filler-word removal, and paragraph breaks on long pauses, each switchable.
- A five-minute cap per dictation, so a forgotten toggle cannot record forever.
- A recording pill with input level, plus start and stop sounds.
- Text-only History of recent dictations. Audio is discarded after transcription.
- A settings window that fits on one screen: hotkey, cleanup toggles, sounds, launch at login, permissions status, and History.
- Terminal awareness: paragraph breaks are never pasted into a terminal, where a newline can run a command.
- A first-run flow that requests permissions, downloads the model, and has you dictate one sentence before you use it anywhere else.
- Signed and notarized builds via GitHub Releases and Homebrew, with in-app updates via Sparkle.
- No telemetry and no crash reporter. A local log file, never containing audio or text, is the whole diagnostic story.

## What deliberately does not ship in the MVP

- Live streaming transcription while you speak.
- Language-model rewriting, prompts, or "smart" modes.
- Multiple engines, engine selection, or non-English languages.
- Voice-activity auto-stop.
- Audio recordings kept on disk.
- Cloud transcription of any kind.

Each of these is a real feature that a real user wants. They are out because each one adds a way for the core path to be slower, less accurate, or less predictable, and the MVP has to earn trust on that path first.

## Requirements

- macOS 15 or later
- Apple Silicon
- About 600 MB of disk for the model, downloaded on first launch

## Permissions

Cheppu asks for two permissions, each with a one-line reason at the moment it is needed:

- **Microphone**: to hear you, asked for by the first dictation that needs it.
- **Accessibility**: to insert text into other apps and to see the hotkey while another app has focus. macOS has no prompt for this one — it is a switch in System Settings — so Cheppu says why in one line and opens the right pane for you. Until it is granted, the menu bar menu says the hotkey cannot work rather than leaving you with a key that does nothing.

Choosing the Fn/Globe key as your hotkey adds one more, Input Monitoring, and needs the macOS "Press 🌐 key to" setting changed to "Do Nothing". Cheppu explains both at the moment you choose that key, not before.

## Building

Cheppu is a Swift package of six targets. `CheppuCore` is the headless core — it decides what happens and imports no OS framework. `CheppuEngine` is Parakeet, and the one-time download that puts it on the machine. `CheppuAudio` is the microphone: the one place Cheppu opens an audio device and asks for Microphone access. `CheppuKeyboard` is the Hotkey: the one place Cheppu watches keys it was not sent and asks for Accessibility. `CheppuInsertion` is the pasteboard and the one keystroke Cheppu ever types. `Cheppu` is the menu bar app that performs what the core decides.

```sh
swift build                     # build the core, the Engine, the microphone, the keyboard, the Insertion and the app
swift test                      # run the suite
./Scripts/make-app.sh           # assemble dist/Cheppu.app
./Scripts/check-core-is-headless.sh
./Scripts/check-the-download-is-the-only-network-path.sh
./Scripts/check-no-audio-reaches-the-disk.sh
./Scripts/check-the-hotkey-never-swallows-a-keystroke.sh
./Scripts/check-cheppu-types-one-keystroke.sh
./Scripts/check-cheppu-tells-one-key-apart.sh
```

Run the app from `dist/Cheppu.app`, not with `swift run`. macOS files a Microphone or Accessibility grant under the bundle that asked for it, so running the executable directly asks for both on behalf of your terminal and grants them to everything you ever run in it.

The suite runs with no permissions granted, no Engine downloaded, no network and no audio device. Nothing in it opens a microphone, creates an event tap, touches your clipboard or types a key, so running it never asks your terminal for Microphone or Accessibility access and never disturbs what you had copied. Running it needs a toolchain that ships the Swift Testing runtime, which today means Xcode; the Command Line Tools alone can build the app but not run the suite. See [ADR-0003](./docs/adr/0003-swift-package-manager-instead-of-an-xcode-project.md).

Transcribing for real needs the 480 MB Engine, so those tests are off by default and off in CI:

```sh
CHEPPU_LIVE_ENGINE=1 swift test --filter LiveEngineTests
```

They fetch the Engine into `~/Library/Application Support/Cheppu/Engine`, transcribe speech synthesised with `say`, and check that a minute of it comes back in well under a second. See [ADR-0005](./docs/adr/0005-cheppu-fetches-the-engine-itself.md) for why Cheppu fetches the Engine itself rather than letting its dependency do it.

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
