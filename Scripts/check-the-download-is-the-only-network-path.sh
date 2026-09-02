#!/bin/bash
# Cheppu reaches the network exactly once, to fetch the Engine, and never again.
# That is a structural promise rather than a policy (see docs/product-experience.md
# §10), so it is checked rather than reviewed: everything that can open a
# connection has to live in the one file whose whole job is the Engine Download.
#
# This covers Cheppu's own code. FluidAudio has a download path of its own, which
# `ParakeetEngine` shuts off with `ModelHub.offlineMode` and the Parakeet Engine
# suite asserts is off.
set -euo pipefail

cd "$(dirname "$0")/.."

ALLOWED="Sources/CheppuEngine/EngineDownload.swift"

FORBIDDEN='URLSession|URLRequest|URLConnection|URLDownload|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFSocket|CFStream|getaddrinfo|import Network'

# `URLSessionConfiguration` is settings and opens nothing on its own, so it is
# allowed to travel to whoever holds the Engine. Blanking it before the search
# keeps the file and line of every real match.
FOUND=$(
	grep -rn --include='*.swift' '' Sources |
		sed 's/URLSessionConfiguration//g' |
		grep -E "$FORBIDDEN" |
		grep -v "^$ALLOWED:" || true
)

if [ -n "$FOUND" ]; then
	echo "$FOUND"
	echo "error: the Engine Download in $ALLOWED is the only place Cheppu may reach the network (see above)" >&2
	exit 1
fi

echo "The Engine Download is the only network path."
