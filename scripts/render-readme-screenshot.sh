#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
binary=$(mktemp "${TMPDIR:-/tmp}/pi-agent-shelf-screenshot.XXXXXX")
trap 'rm -f "$binary"' EXIT

cd "$repo_dir"
xcrun swiftc -parse-as-library \
    Sources/PiAgentShelf/Models.swift \
    Sources/PiAgentShelf/ProcessRunner.swift \
    Sources/PiAgentShelf/GhosttyClient.swift \
    Sources/PiAgentShelf/FastModeStatus.swift \
    Sources/PiAgentShelf/AgentScanner.swift \
    Sources/PiAgentShelf/AgentStore.swift \
    Sources/PiAgentShelf/ShelfView.swift \
    scripts/render-readme-screenshot.swift \
    -o "$binary"

"$binary" "${1:-docs/pi-agent-shelf.png}"
