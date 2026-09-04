#!/bin/bash
# Cleanup is a pure function: a Raw Transcript and its word timings in, Final
# Text out. Nothing else happens on the way — no file, no clock, no network, and
# never a language model — which is what lets a user predict what Cheppu did to
# their words from a one-line description (docs/product-experience.md §8)
# instead of re-reading everything it inserted.
#
# Two things are checked, because either one alone would be easy to walk past:
#
#   1. Nothing in Cleanup imports anything at all. The standard library and the
#      core's own types are the whole of what it can reach, so there is no
#      framework in scope to read a file with, no clock to ask, and nowhere a
#      model could be loaded from. This is the check that matters: a rule that
#      consulted anything would have to import it first.
#   2. Nothing in it names a clock, a file, a locale or work to be done later.
#      The same Raw Transcript has to produce the same Final Text on any machine,
#      in any region, in any order, forever.
#
# Both are checked over the whole of Sources/CheppuCore/Cleanup rather than one
# file, which is what makes the promise survive a rule being given a file of its
# own. Cleanup living in a directory of its own is what the check is anchored
# to, so the directory has to be there.
set -euo pipefail

cd "$(dirname "$0")/.."

CLEANUP=Sources/CheppuCore/Cleanup

if [ ! -d "$CLEANUP" ]; then
	echo "error: $CLEANUP is where Cleanup lives, and it is what this check is anchored to" >&2
	exit 1
fi

FOUND=$(grep -rnE --include='*.swift' "^[[:space:]]*(@[a-zA-Z_]+ )?import " "$CLEANUP" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: Cleanup imports nothing — a rule that reads a file, a clock or a model has to reach for it first (see above)" >&2
	exit 1
fi

IMPURE='Date|Clock|Timer|DispatchTime|FileManager|FileHandle|OutputStream|URL|URLSession|Process|Locale|Task|async|await|random'

FOUND=$(grep -rnE --include='*.swift' "\b($IMPURE)\b" "$CLEANUP" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: Cleanup is a pure function — the same Raw Transcript must give the same Final Text on any machine (see above)" >&2
	exit 1
fi

# And it does not know where the words are going. Terminal awareness (#12) is
# applied at the Insertion boundary rather than inside a rule, so that what is
# kept is what was said and a rule stays predictable from its one-line
# description whatever window happens to be in front. A rule that read the
# Target App would be the one way of making the same Raw Transcript give two
# different Final Texts that none of the checks above would catch.
#
# Code only, unlike the two checks above: a comment in a rule saying where
# Terminal awareness lives instead is the sort of thing this file's own prose
# asks for, and failing the build over it would teach the next person to leave
# the explanation out.
WHERE_THE_WORDS_ARE_GOING='TargetApp|isATerminal|Terminal\b'

FOUND=$(grep -rnE --include='*.swift' "\b($WHERE_THE_WORDS_ARE_GOING)" "$CLEANUP" |
	grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: Cleanup does not know where the words are going — Terminal awareness belongs at the Insertion boundary (ADR-0008)" >&2
	exit 1
fi

echo "Cleanup is a pure function."
