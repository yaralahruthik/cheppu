#!/bin/bash
# The Diagnostics Log holds what Cheppu did and never what was said, cannot grow
# without end, and is the whole of the diagnostic story — no telemetry, no crash
# reporter, no analytics. Like the network, the audio and the History promises,
# this is structural rather than a policy (see docs/product-experience.md §10),
# so it is checked rather than reviewed.
#
# Five things are checked:
#
#   1. Nothing a note is made of can carry a word. The vocabulary the core
#      writes down has no `String` in it anywhere, so there is no case for a Raw
#      Transcript to be put in — and the one string the log ever makes out of a
#      value is made out of a type name rather than out of the value.
#   2. Neither the vocabulary nor the target that writes it can name a
#      Dictation's audio, its transcripts or the app the words went into. What
#      they cannot name they cannot write down.
#   3. One target opens the log, and it is bounded: a size for each file and a
#      file before this one, which is what keeps two files on the disk and never
#      three.
#   4. The file is readable by its owner and by nobody else.
#   5. Nothing on a Dictation's path can ever wait for it: the port that takes
#      a note is not something that can be awaited or fail, so no disk can be
#      on the stop-to-insert path however the log is written later.
#   6. Nothing anywhere in Cheppu reports to anything but that file.
set -euo pipefail

cd "$(dirname "$0")/.."

VOCABULARY="Sources/CheppuCore/Diagnostics"
LOG="Sources/CheppuDiagnostics"
NOTE="$VOCABULARY/DiagnosticNote.swift"
NAME="$VOCABULARY/FailureName.swift"
FILE="$LOG/DiagnosticsFile.swift"

# Both have to be there. Without this the greps below would pass by finding
# nothing, which is what a renamed or deleted target looks like to a check
# written in `grep`.
for REQUIRED in "$VOCABULARY" "$LOG"; do
	if [ ! -d "$REQUIRED" ]; then
		echo "error: $REQUIRED is missing — the Diagnostics Log is written from there and nowhere else" >&2
		exit 1
	fi
done

# What the code actually does, with what it says about itself left out: these
# files explain at length which things the log does not keep, and a check that
# read the prose would fail on the promise being written down.
code() {
	grep -rnE --include='*.swift' "$1" "${@:2}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' || true
}

# 1. A note cannot carry a word of anybody's.
FOUND=$(code 'String' "$NOTE")
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: no note may carry a String — a closed vocabulary is what keeps the log from ever holding what was said (see above)" >&2
	exit 1
fi

# The one place the log makes a string out of something it was handed: out of
# the type a failure is, and out of a Cheppu failure that has said its own cases
# carry nothing. Two, and no third.
for REQUIRED in 'String(reflecting: type(of: failure))' 'String(describing: named)'; do
	if ! grep -qF "$REQUIRED" "$NAME"; then
		echo "error: $NAME must name a failure with $REQUIRED" >&2
		exit 1
	fi
done

MADE=$(code 'String\(' "$NAME" | wc -l | tr -d ' ')
if [ "$MADE" != "2" ]; then
	code 'String\(' "$NAME"
	echo "error: a failure is named by its type and by nothing else — $MADE ways of making a string, expected 2 (see above)" >&2
	exit 1
fi

# 2. What neither of them may name. The core hands the log a `DiagnosticNote`
# and nothing else, and the writer never sees an event at all.
# Whole words only, so that `theRawTranscriptArrived` — a case that carries
# nothing and is the whole point of the vocabulary — is not mistaken for the
# type it exists instead of.
NAMED='CapturedAudio|RawTranscript|WordTiming|FinalText|HistoryEntry|TargetApp|bundleIdentifier'
FORBIDDEN="(^|[^A-Za-z0-9_])($NAMED)([^A-Za-z0-9_]|\$)"

FOUND=$(code "$FORBIDDEN" "$VOCABULARY")
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: a note holds what happened only — no audio, no Raw Transcript, no Final Text, no Target App (see above)" >&2
	exit 1
fi

FOUND=$(code "(^|[^A-Za-z0-9_])($NAMED|DictationEvent)([^A-Za-z0-9_]|\$)" "$LOG")
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the log writes notes and never reaches past them to what a Dictation was carrying (see above)" >&2
	exit 1
fi

# A failure that says its own name has to be one that carries nothing. The
# protocol is a promise about the cases, and this is what holds anybody to it:
# every enumeration conforming to it is read, and a case with an associated
# value in one of them is a value that would be printed straight into the log.
CONFORMERS=$(grep -rlE --include='*.swift' '[:,][[:space:]]*FailureSafeToName' Sources || true)
for CONFORMER in $CONFORMERS; do
	CARRYING=$(awk '
		/[:,][[:space:]]*FailureSafeToName/ { inside = 1; depth = 0 }
		inside {
			if ($0 ~ /^[[:space:]]*case [A-Za-z_][A-Za-z0-9_]*\(/) print FILENAME ":" NR ":" $0
			depth += gsub(/{/, "{") - gsub(/}/, "}")
			if (depth <= 0 && NR > 1 && $0 ~ /}/) inside = 0
		}
	' "$CONFORMER")
	if [ -n "$CARRYING" ]; then
		echo "$CARRYING"
		echo "error: a failure that says its own name may carry nothing — what it carries would be written into the log (see above)" >&2
		exit 1
	fi
done

# 3. One writer, and a bound. A second target opening the file would be a second
# answer to what the log holds and how big it gets.
FOUND=$(grep -rln --include='*.swift' 'Diagnostics.log' Sources | grep -v "^$LOG/" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: only $LOG may open the Diagnostics Log — what a second writer put in it is nobody's promise (see above)" >&2
	exit 1
fi

for REQUIRED in 'roomForOne' 'func theOneBefore'; do
	if ! grep -qF "$REQUIRED" "$FILE"; then
		echo "error: $FILE is missing $REQUIRED — the log has to have a size it starts a new file at, and one file it keeps behind it" >&2
		exit 1
	fi
done

# 4. Readable and writable by its owner, and by nobody else: 0600 for the file,
# 0700 for the folder it sits in. It holds none of the user's words and it still
# says how much they dictate and when.
for REQUIRED in 'onlyTheUsersOwn: Int = 0o600' 'aFolderOnlyTheUsersOwn: Int = 0o700'; do
	if ! grep -qE "$REQUIRED" "$FILE"; then
		echo "error: $FILE is missing $REQUIRED — the log must be readable by nobody but the user" >&2
		exit 1
	fi
done

# 5. A note is taken and let go of. Taking one is not something a Dictation can
# await, which is what keeps a disk off the path between somebody finishing a
# sentence and the words appearing (docs/product-experience.md §7) whatever the
# log is made of later.
TAKING_A_NOTE=$(grep -E '^[[:space:]]*func record\(' Sources/CheppuCore/Ports/Ports.swift || true)
if [ -z "$TAKING_A_NOTE" ]; then
	echo "error: Sources/CheppuCore/Ports/Ports.swift must declare the port that takes a note" >&2
	exit 1
fi
if echo "$TAKING_A_NOTE" | grep -qE 'async|throws'; then
	echo "$TAKING_A_NOTE"
	echo "error: taking a note may not be awaited or fail — nothing on the stop-to-insert path may wait for a disk (see above)" >&2
	exit 1
fi

# 6. One file on this machine is the whole of it. A crash reporter, an analytics
# SDK or a line in the unified system log are all the same thing: something
# about a Dictation leaving the machine it happened on.
REPORTING='Sentry|Crashlytics|Bugsnag|Firebase|Mixpanel|Amplitude|PostHog|TelemetryDeck|Analytics|MetricKit|MXMetric|NSSetUncaughtExceptionHandler|OSLog|os_log|os\.Logger'

FOUND=$(grep -rnE --include='*.swift' "$REPORTING" Sources || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the Diagnostics Log is the whole diagnostic story — no telemetry, no crash reporter, no analytics (see above)" >&2
	exit 1
fi

# And nothing was added to the package to do it with. Cheppu has one dependency,
# and it is the Engine.
DEPENDENCIES=$(grep -cE '^[[:space:]]*\.package\(' Package.swift)
if [ "$DEPENDENCIES" != "1" ]; then
	grep -nE '^[[:space:]]*\.package\(' Package.swift
	echo "error: Cheppu has one dependency and it is the Engine — $DEPENDENCIES declared (see above)" >&2
	exit 1
fi

echo "The log says nothing of what was said, and is the whole diagnostic story."
