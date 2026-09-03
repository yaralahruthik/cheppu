#!/bin/bash
# Cheppu watches the keyboard and never touches it. A `CGEvent` tap is made one
# of two ways: `.listenOnly`, which can only read events, and `.defaultTap`,
# which can change or drop them before the app they were meant for ever sees
# them. Cheppu may only ever make the first kind, so that a keystroke meant for
# the app the user is typing in cannot be swallowed by the app watching for the
# Hotkey.
#
# Like the network and audio promises, this is structural rather than a policy
# (see docs/product-experience.md §1), so it is checked rather than reviewed.
set -euo pipefail

cd "$(dirname "$0")/.."

FOUND=$(grep -rnE --include='*.swift' '\.defaultTap|CGEventTapOptions\(' Sources || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: an event tap may only be created with .listenOnly, so that Cheppu cannot swallow a keystroke meant for another app (see above)" >&2
	exit 1
fi

# And every tap that does exist asks for it, rather than relying on the default
# of whatever `tapCreate` is called with next. Counted per file, so a second tap
# added later cannot ride on the first one's compliance.
while IFS= read -r file; do
	made=$(grep -c 'tapCreate(' "$file")
	listening=$(grep -c 'options: \.listenOnly' "$file")
	if [ "$listening" -lt "$made" ]; then
		echo "$file: $made event tap(s), $listening of them listen-only"
		echo "error: every event tap must ask for .listenOnly (see above)" >&2
		exit 1
	fi
done < <(grep -rlE --include='*.swift' 'tapCreate\(' Sources || true)

echo "The Hotkey never swallows a keystroke."
