#!/bin/bash
# Cheppu is handed every key the user presses, in whatever app they are in, and
# asks one question of the ones it was not sent: which position on the keyboard
# was that? The answer is compared against two keys and goes no further — Escape,
# which Cancels a Dictation, and the one key the user chose to dictate with
# (ADR-0011). Every other key remains "the user typed something". An app that can
# read what you type is an app that could keep it, so — like the network, the
# audio and the promise that a keystroke is never swallowed — this is structural
# rather than a policy (see docs/product-experience.md §10) and is checked rather
# than reviewed.
#
# Modifiers are not in scope here: which of them are held is the Hotkey itself,
# and it is what the user pressed Cheppu with rather than what they typed.
set -euo pipefail

cd "$(dirname "$0")/.."

# The tap that watches everyone else's keyboard, and the window where the user
# tells Cheppu which key they want. The second one is handed only the events
# already on their way to Cheppu and can hear nothing outside this app, which is
# the difference between being told a key and watching somebody type.
declare -a ALLOWED=(
	"Sources/CheppuKeyboard/Keyboard.swift"
	"Sources/CheppuSettings/HotkeyRecorder.swift"
)

FORBIDDEN='getIntegerValueField|CGEventGetIntegerValueField|keyboardEventKeycode|keyboardGetUnicodeString|\.unicodeString|\.keyCode\b'

KEPT_OUT=$(printf '%s\n' "${ALLOWED[@]}" | sed 's/^/^/;s/$/:/' | paste -sd '|' -)

FOUND=$(grep -rnE --include='*.swift' "$FORBIDDEN" Sources | grep -vE "$KEPT_OUT" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: only ${ALLOWED[*]} may read which key was pressed (see above)" >&2
	exit 1
fi

# And each of them asks once rather than being a reader: a second field read off
# an event in either file would be a second thing Cheppu learns about what was
# typed, whatever the comment above it said.
for file in "${ALLOWED[@]}"; do
	READS=$(grep -cE "$FORBIDDEN" "$file" || true)
	if [ "$READS" -ne 1 ]; then
		echo "$file reads $READS fields off a key event"
		echo "error: Cheppu asks one question of a key, and it is which position it was" >&2
		exit 1
	fi
done

echo "Cheppu tells one key apart."
