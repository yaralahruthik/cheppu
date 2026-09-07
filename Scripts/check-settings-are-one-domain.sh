#!/bin/bash
# Everything the user sets lives in one place: the standard user defaults domain,
# reached from one file. A second target reading or writing a preference would be
# a switch with two answers; a settings target that wrote a file of its own would
# be the configuration file #15 says Cheppu does not have.
set -euo pipefail

cd "$(dirname "$0")/.."

KEPT_IN="Sources/CheppuSettings/Preferences.swift"

if grep -rln "UserDefaults" Sources | grep -v "^$KEPT_IN$"; then
	echo "error: preferences are kept in $KEPT_IN and read from there (see the files above)" >&2
	exit 1
fi

# History is the one thing Cheppu writes to a file, and it is not a preference
# (ADR-0009). Settings must not grow a file of its own beside it.
if grep -rnE "FileManager|\.write\(to:|contentsOf:" Sources/CheppuSettings; then
	echo "error: a setting is a preference, not a file the user has to find" >&2
	exit 1
fi

echo "Settings are one domain, read from one file."
