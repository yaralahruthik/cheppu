#!/bin/bash
# Puts a recording of your own voice into the accuracy corpus.
#
# The corpus is the author's voice and vocabulary rather than a public benchmark
# set, because what the word-error-rate test measures is whether Cheppu hears
# *you* — your accent, the proper nouns you use, the technical terms you say all
# day. A good score on somebody else's read-aloud corpus would say nothing about
# whether the app is usable.
#
# Record the audio in an app of your own — Voice Memos, or QuickTime Player's
# File > New Audio Recording — and hand the file to this script. It deliberately
# does not open the microphone itself: a script that did would ask macOS for
# Microphone access on behalf of your terminal, and grant it to everything you
# ever run in that terminal. Permissions belong to purpose-built bundles.
#
#     ./Scripts/add-an-accuracy-fixture.sh ~/Desktop/recording.m4a long-form-dictation
#
# Then write down what you actually said, word for word, in the .txt it makes.
# The reference is what *was said*, not what you meant to say: if you stumbled
# over a word, the stumble is in the recording and belongs in the reference too.
# Punctuation and capitals do not matter — the measurement erases both, because
# they are Cleanup's business and are tested there.
set -euo pipefail

cd "$(dirname "$0")/.."

FIXTURES="Tests/CheppuAccuracyTests/Fixtures"

# What Parakeet hears in. Committing at anything else would mean the test
# measures a resampler on the way to the Engine as well as the Engine.
SAMPLE_RATE=16000

if [ $# -ne 2 ]; then
	cat >&2 <<-USAGE
		usage: $0 <recording> <name>

		  <recording>  an audio file you recorded yourself, in any format macOS reads
		  <name>       what the fixture is called, in kebab-case

		The corpus must cover technical terms, proper nouns and long-form dictation,
		so these three names have to exist:

		  technical-terms       the words you say that a general model has not heard
		  proper-nouns          names of people, places, projects and products you use
		  long-form-dictation   a paragraph or more, said the way you would actually dictate it
	USAGE
	exit 2
fi

RECORDING="$1"
NAME="$2"

if [ ! -f "$RECORDING" ]; then
	echo "error: no such recording: $RECORDING" >&2
	exit 1
fi

if ! [[ "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
	echo "error: '$NAME' is not a kebab-case name" >&2
	exit 1
fi

mkdir -p "$FIXTURES"
WAV="$FIXTURES/$NAME.wav"
REFERENCE="$FIXTURES/$NAME.txt"

if [ -e "$WAV" ]; then
	echo "error: $WAV already exists — delete it first if you mean to replace it" >&2
	exit 1
fi

# Mono, 16 kHz, 16-bit: what the Engine reads, at a quarter the size of the
# float32 the microphone hands it, in a repository that has to carry these
# files forever.
afconvert -f WAVE -d "LEI16@$SAMPLE_RATE" -c 1 "$RECORDING" "$WAV"

if [ ! -e "$REFERENCE" ]; then
	cat > "$REFERENCE" <<-EMPTY
		Replace this line with exactly what you said in $NAME.wav, word for word.
	EMPTY
fi

echo "Added $WAV"
afinfo "$WAV" | sed -n '/Data format/p;/estimated duration/p'
echo
echo "Now write what you said in $REFERENCE, then measure:"
echo
echo "    CHEPPU_ACCURACY=1 swift test --filter CheppuAccuracyTests"
