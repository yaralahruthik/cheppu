---
status: accepted
---

# Spellings bias the Engine, and are paid for at the first Correction

Cheppu learns from the user fixing its words, and the obvious way to build that is a rule: the user changed *chip you* to *Cheppu*, so Cleanup swaps *chip you* for *Cheppu* from now on. It is free, deterministic, describable in one line, and it is what most dictation apps ship as a "replacements" list. We chose instead to keep only the word the user wants — a Spelling — and to hand it to the Engine, which hears the audio a second time through a small CTC model (FluidAudio's vocabulary rescorer, after NVIDIA's CTC word-spotter) and puts the Spelling in only where the sound supports it.

A rule has no ears. The day the user dictates "I'll chip you in for lunch", the rule writes "I'll Cheppu in for lunch", and `docs/product-experience.md` §2 says that is the day they start re-reading every output. §8 draws the other line: a Cleanup that rewrites words has made Cheppu an author. The rescorer is probabilistic where the rule is certain, but it is probabilistic about the one thing the rule cannot know — whether that sound was that word — and it costs nothing a user who never corrects will ever pay.

That cost is a second model of roughly 97 MB and a second pass over the audio on the stop-to-insert path. Onboarding could fetch the model with the rest of the Engine, and then the Engine Download would still be one moment and the promise "no network access after the model download" would still be one sentence. We chose to offer it at the first Correction instead, with its size said at that moment, and again from Settings for as long as it is missing. 97 MB for every user, most of whom will never make a Correction, to spare the few who do a button — that is the wrong side of the trade. The Engine Download is now one named thing that happens in two moments, and the check script's one allowed file is still the whole truth.

## Considered options

- **A replacement rule in Cleanup**: rejected above. It is also the only option that keeps what the Engine heard on disk, beside what was meant, which History has never done.
- **FluidAudio's Unified manager, which has boosting built in**: it needs a different export of Parakeet — the `parakeet_unified_*` bundles — so it is a different Engine Download, a different decode pipeline, and two Ceilings measured again. The rescorer itself is engine-independent: it takes a transcript, its token timings and the audio, all of which the batch manager Cheppu already uses hands back. So the Engine keeps its pipeline and adds one call.
- **Fetching the second model with the rest of the Engine at Onboarding**: rejected above, for the 97 MB.
- **Fetching it silently at the first Correction**: a download the user did not start, on a connection they did not choose to spend, is the stall §12 warns about. The Hotkey already has the pattern — what choosing something costs is said at the moment it is chosen — and this applies it to a download.
- **Reading the Target App after Insertion to find what the user fixed there**: it would catch every Correction rather than only the ones made in History, and it is the one thing §10 says Cheppu structurally cannot do.

## Consequences

- The Engine is in two parts, and `EngineDownload` lists two repositories. The second part lives under `Cheppu/Engine/` beside the first, so everything Cheppu put on the machine is still one folder.
- The CTC pass runs only when at least one Spelling exists and the Settings switch is on, so the stop-to-insert path of a user who never corrects is unchanged. A `DiagnosticNote` records how long the pass took, in ADR-0012's closed vocabulary, so a missed budget is attributable.
- Spellings are a file of their own beside `History.jsonl`, under ADR-0009's discipline — `0600` in a `0700` folder, one per line, readable with `cat` — and `Scripts/check-history-holds-text-only.sh` grows to cover the target that writes them. A Spelling holds the word as the user wants it and nothing of what the Engine heard.
- Both Ceilings go on measuring the bare Engine. A Spelling that makes the Corpus score better is not the Engine getting better, and a Ceiling lowered on the strength of one would be a test that had stopped measuring the Engine. The mechanism is proven by one fixture the bare Engine gets wrong and one committed Spelling that puts it right.
- README line 19 and `docs/product-experience.md` §10 say "no network access after the one-time model download", which is no longer the shape of the promise. Both become "no network access except to fetch the Engine" — the sentence Sparkle (#22) will need to sit beside anyway.
- The rescorer reads its token table from FluidAudio's own cache directory rather than from the directory it is handed (`VocabularyBoostingSession.init` calls `CtcModels.defaultCacheDirectory`). Keeping the second part under `Cheppu/Engine/` needs either a symlink from that cache directory or a small change upstream. Neither is decided here; the issue carries it.
- FluidAudio declines to spot a term shorter than three characters, because "or" would become "VR". The one-to-three-word, three-letter bound on what a Correction leaves behind is that floor made into a rule the user can read, rather than a threshold they would have to discover.
