#!/bin/bash
# The core is headless: it decides, and the app target performs. If the core can
# reach an OS framework it can do I/O, and the core suite stops being runnable
# with no permissions, no Engine, no network and no audio device.
set -euo pipefail

cd "$(dirname "$0")/.."

FORBIDDEN='AppKit|SwiftUI|Cocoa|AVFoundation|CoreML|CoreAudio|CoreGraphics|ApplicationServices|Carbon|IOKit'

# Catches `import AppKit`, `@_exported import AppKit` and `import class AppKit.NSImage`.
KIND='class|struct|enum|protocol|typealias|func|var|let'

if grep -rnE "^[[:space:]]*(@[a-zA-Z_]+ )?import (($KIND) )?($FORBIDDEN)\b" Sources/CheppuCore Tests/CheppuCoreTests; then
	echo "error: the core must not import an OS framework (see the imports above)" >&2
	exit 1
fi

echo "Core is headless."
