---
status: accepted
---

# Parakeet via FluidAudio as the sole MVP Engine

macOS 26 ships an on-device engine (SpeechAnalyzer), so the obvious path is to use it and add nothing. We chose instead to ship NVIDIA Parakeet TDT v3 through the FluidAudio Swift package as the only Engine in the MVP, behind a small Engine abstraction. Accuracy is the product's first goal, and Parakeet has a measurably lower English word error rate than Apple's engine while running in well under real time on Apple Silicon. It also lets the app support macOS 15, where SpeechAnalyzer does not exist.

## Considered options

- **Apple SpeechAnalyzer only**: zero download, no dependencies, but macOS 26 only and lower accuracy. The author's daily use of it in other dictation tools found it adequate, not excellent.
- **whisper.cpp large-v3-turbo**: strongest multilingual accuracy, but a C++ dependency and several times slower than Parakeet on the same hardware.
- **Two engines in the MVP**: rejected because a second engine doubles the surface to get right and the MVP goal is one excellent path, not choice.

## Consequences

- First run must download roughly 600 MB of model files before the first Dictation. Onboarding has to make that feel deliberate, not broken.
- English only in the MVP. Language selection is deferred until a second Engine exists.
- The Engine abstraction exists from day one so that adding Apple or Whisper later is additive, not a rewrite.
