#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR=".build/Pi Agent Shelf.app"
CONTENTS="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/PiAgentShelf" "$CONTENTS/MacOS/PiAgentShelf"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

codesign --force --deep --sign - --identifier com.mustafaj.PiAgentShelf "$APP_DIR" >/dev/null
printf 'Built %s\n' "$APP_DIR"
