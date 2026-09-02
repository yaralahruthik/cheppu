---
status: accepted
---

# Transcribe after the Dictation stops, not while speaking

Most dictation apps stream provisional words into the target app as the user speaks. Cheppu transcribes only once the Dictation stops and inserts the final result in one Insertion. Provisional text gets revised, which both undermines trust in accuracy and makes Insertion into arbitrary apps far harder (deleting and retyping in someone else's text field). Parakeet on Apple Silicon transcribes a one-minute Dictation in well under a second, so the perceived cost is a breath, not a wait.

## Consequences

- The Pill has to carry the "it heard me" signal during listening, since no text is appearing yet. That is why it shows a live input level.
- A visible "transcribing" state is required so a pause after stop is never mistaken for a hang.
- Streaming can be added later as an Engine capability, but the Insertion model must not be redesigned around it.
