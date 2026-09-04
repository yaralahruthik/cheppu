#!/bin/bash
# Cheppu is handed every key the user presses, in whatever app they are in, and
# learns exactly one thing about the ones it was not sent: was that Escape? An
# app that can read what you type is an app that could keep it, so — like the
# network, the audio and the promise that a keystroke is never swallowed — this
# is structural rather than a policy (see docs/product-experience.md §10) and is
# checked rather than reviewed.
#
# Modifiers are not in scope here: which of them are held is the Hotkey itself,
# and it is what the user pressed Cheppu with rather than what they typed.
set -euo pipefail

cd "$(dirname "$0")/.."

ALLOWED="Sources/CheppuKeyboard/Keyboard.swift"

FORBIDDEN='getIntegerValueField|CGEventGetIntegerValueField|keyboardEventKeycode|keyboardGetUnicodeString|\.unicodeString'

FOUND=$(grep -rnE --include='*.swift' "$FORBIDDEN" Sources | grep -v "^$ALLOWED:" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the one question in $ALLOWED is all Cheppu may ask of a key it was not sent (see above)" >&2
	exit 1
fi

# And it is one question rather than a reader: a second field read off an event
# in that file would be a second thing Cheppu learns about what was typed,
# whatever the comment above it said.
READS=$(grep -cE 'getIntegerValueField' "$ALLOWED" || true)
if [ "$READS" -ne 1 ]; then
	echo "$ALLOWED reads $READS fields off a key event"
	echo "error: Cheppu asks one question of a key it was not sent, and it is whether that key was Escape" >&2
	exit 1
fi

echo "Cheppu tells one key apart."
