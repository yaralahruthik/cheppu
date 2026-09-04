#!/bin/bash
# History holds what was said and when, on this machine, where nobody but its
# owner can read it. Like the network and the audio promises, this is structural
# rather than a policy (see docs/product-experience.md §10), so it is checked
# rather than reviewed.
#
# Three things are checked, because History is the one part of Cheppu that keeps
# anything at all:
#
#   1. The target that writes it cannot name a Dictation's audio, its Raw
#      Transcript, or the app the words went into. What it cannot name it cannot
#      write down.
#   2. It is kept in the user's own Application Support and nowhere a second
#      account, an iCloud sync or a backup service would pick it up.
#   3. The file and the folder around it are readable by their owner and by
#      nobody else.
set -euo pipefail

cd "$(dirname "$0")/.."

HISTORY="Sources/CheppuHistory"
FILE="$HISTORY/HistoryFile.swift"

# The target has to be there. Without this the greps below would pass by finding
# nothing, which is what a renamed or deleted target looks like to a check
# written in `grep`.
if [ ! -d "$HISTORY" ]; then
	echo "error: $HISTORY is missing — History is written there and nowhere else" >&2
	exit 1
fi

# What the target actually does, with what it says about itself left out: these
# files explain at length which things History does not keep and where it is
# careful not to put itself, and a check that read the prose would fail on the
# promise being written down.
code() {
	grep -rnE --include='*.swift' "$1" "$HISTORY" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*)' || true
}

# What an entry must never hold. The core hands History a `HistoryEntry` and
# nothing else, and this is what keeps it that way as the store grows.
FORBIDDEN='CapturedAudio|RawTranscript|WordTiming|TargetApp|bundleIdentifier|processIdentifier'

FOUND=$(code "$FORBIDDEN")
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: History holds Final Text and a timestamp only — no audio, no Raw Transcript, no Target App (see above)" >&2
	exit 1
fi

# And it is the only thing that writes it. A second target opening the file
# would be a second answer to what History holds and who may read it.
FOUND=$(grep -rln --include='*.swift' 'History.jsonl' Sources | grep -v "^$HISTORY/" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: only $HISTORY may open History — what a second writer put in it is nobody's promise (see above)" >&2
	exit 1
fi

# Somewhere private to this account. Documents and Desktop are synced off the
# machine by iCloud Drive; a shared folder or a group container is readable by
# something that is not the user.
SOMEWHERE_ELSE='iCloud|ubiquit|Ubiquit|documentDirectory|desktopDirectory|downloadsDirectory|sharedPublicDirectory|Group Containers|/Users/Shared'

FOUND=$(code "$SOMEWHERE_ELSE")
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: History is kept in the user's own Application Support, never anywhere shared or synced (see above)" >&2
	exit 1
fi

if ! grep -qE 'applicationSupportDirectory, in: \.userDomainMask' "$FILE"; then
	echo "error: $FILE must keep History in this user's own Application Support" >&2
	exit 1
fi

# Readable and writable by their owner, and by nobody else: 0600 for the file,
# 0700 for the folder it sits in.
for REQUIRED in 'onlyTheUsersOwn: Int = 0o600' 'aFolderOnlyTheUsersOwn: Int = 0o700'; do
	if ! grep -qE "$REQUIRED" "$FILE"; then
		echo "$FILE is missing $REQUIRED"
		echo "error: History and the folder around it must be readable by nobody but the user" >&2
		exit 1
	fi
done

# Twice on every write: once for the file, once for the folder. Writing
# atomically replaces the file, so the new one is only as private as the
# account's umask; and `createDirectory` ignores the attributes it is handed for
# a folder that is already there, which on a real machine it nearly always is —
# the Engine Download makes `Cheppu/` before anybody has dictated anything.
if [ "$(grep -c 'setAttributes' "$HISTORY/HistoryStore.swift")" -lt 2 ]; then
	echo "error: the store must set the permissions of both History and the folder around it on every write" >&2
	exit 1
fi

echo "History holds text only, kept where only its owner can read it."
