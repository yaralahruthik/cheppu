#!/bin/bash
# Audio never reaches the disk. Like the network promise, this is structural
# rather than a policy (see docs/product-experience.md §10), so it is checked
# rather than reviewed.
#
# Two things are checked, because either one alone would be easy to walk past:
#
#   1. Nothing anywhere in Cheppu opens an audio file. Not in the microphone,
#      not in the Engine, not in a debugging aid someone left behind.
#   2. The one target that ever holds a Dictation's audio touches no filesystem
#      API at all. There is nothing for it to legitimately read or write, so the
#      cheapest way to know audio cannot leak out of it is that it has no way to
#      write anything.
set -euo pipefail

cd "$(dirname "$0")/.."

AUDIO_FILES='AVAudioFile|AVAudioRecorder|AVAssetWriter|AVAssetExportSession|ExtAudioFile|AudioFileCreate|AudioFileOpen|AudioFileWrite|AudioFileInit'

FILESYSTEM='FileManager|FileHandle|OutputStream|FilePath|fopen|fwrite|Data\(contentsOf:|\.write\(to:|URL\(fileURLWithPath:|appendingPathComponent|\.appending\(path:'

FOUND=$(grep -rnE --include='*.swift' "$AUDIO_FILES" Sources || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: nothing in Cheppu may open an audio file — a Dictation's audio is discarded, never written (see above)" >&2
	exit 1
fi

FOUND=$(grep -rnE --include='*.swift' "$FILESYSTEM" Sources/CheppuAudio || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the microphone touches no filesystem, so that a Dictation's audio has nowhere to go but the Engine (see above)" >&2
	exit 1
fi

echo "No audio reaches the disk."
