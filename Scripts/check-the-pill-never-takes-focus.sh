#!/bin/bash
# The Pill appears over the app the user is typing in and never becomes part of
# it. A dictation app that took the keyboard — even for the instant it took to
# show a panel — would put the user's next word into Cheppu instead of into
# their email, which is the one failure `docs/product-experience.md` §1 says
# they never come back from. So, like the network, the audio and the keystroke
# promises, this is structural rather than a policy and is checked rather than
# reviewed.
set -euo pipefail

cd "$(dirname "$0")/.."

PILL="Sources/CheppuFeedback"
PANEL="$PILL/PillPanel.swift"

# Every way AppKit offers of taking focus or bringing an app forward. None of
# them has any business in the target that draws the Pill.
FORBIDDEN='makeKeyAndOrderFront|makeKeyWindow|makeKey\(\)|makeFirstResponder|becomeFirstResponder|orderFront\(|NSApp|NSApplication|activate\('

FOUND=$(grep -rnE --include='*.swift' "$FORBIDDEN" "$PILL" || true)
if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the Pill must be shown without ever taking focus or activating Cheppu (see above)" >&2
	exit 1
fi

# And it is a panel that could not take focus even if something asked it to:
# without both of these, ordering a borderless panel front makes it key.
for REQUIRED in '\.nonactivatingPanel' 'canBecomeKey: Bool \{ false \}'; do
	if ! grep -qE "$REQUIRED" "$PANEL"; then
		echo "$PANEL is missing $REQUIRED"
		echo "error: the Pill's panel must be non-activating and must refuse to become key" >&2
		exit 1
	fi
done

echo "The Pill never takes focus."
