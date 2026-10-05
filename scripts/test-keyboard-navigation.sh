#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
binary=$(mktemp "${TMPDIR:-/tmp}/pi-agent-shelf-keyboard.XXXXXX")
trap 'rm -f "$binary"' EXIT

xcrun swiftc -parse-as-library \
    Sources/PiAgentShelf/Models.swift \
    Sources/PiAgentShelf/ProcessRunner.swift \
    Sources/PiAgentShelf/GhosttyClient.swift \
    Sources/PiAgentShelf/FastModeStatus.swift \
    Sources/PiAgentShelf/AgentScanner.swift \
    Sources/PiAgentShelf/AgentStore.swift \
    Sources/PiAgentShelf/ShelfView.swift \
    Tests/KeyboardNavigationCheck.swift \
    -o "$binary"

"$binary"
