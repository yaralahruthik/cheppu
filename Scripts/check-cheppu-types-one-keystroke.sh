#!/bin/bash
# Cheppu types one keystroke, ever: the paste that puts the Final Text where the
# cursor is. An app that is allowed to watch every key on the machine and is
# also allowed to press them is trusted twice over, so — like the network and
# audio promises — this is structural rather than a policy (see
# docs/product-experience.md §1) and is checked rather than reviewed.
set -euo pipefail

cd "$(dirname "$0")/.."

ALLOWED="Sources/CheppuInsertion/Keystrokes.swift"

FORBIDDEN='CGEvent\(keyboardEventSource:|CGEvent\(source:|CGEvent\(scrollWheelEvent2Source:|CGEvent\(mouseEventSource:|\.post\(tap:|\.postToPid\(|CGEventPost|CGPostKeyboardEvent'

FOUND=$(grep -rnE --include='*.swift' "$FORBIDDEN" Sources | grep -v "^$ALLOWED:" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the paste in $ALLOWED is the only event Cheppu may synthesise (see above)" >&2
	exit 1
fi

# And it is one key rather than a keyboard: a second key code in that file would
# be a second thing Cheppu can type, whatever the comment above it said.
KEYS=$(grep -cE ': CGKeyCode = ' "$ALLOWED" || true)
if [ "$KEYS" -ne 1 ]; then
	echo "$ALLOWED names $KEYS keys"
	echo "error: Cheppu synthesises exactly one keystroke, the paste" >&2
	exit 1
fi

echo "Cheppu types one keystroke."
