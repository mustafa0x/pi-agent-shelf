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
cp "Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

if [ -z "${CODE_SIGN_IDENTITY:-}" ]; then
    CODE_SIGN_IDENTITY=$(
        security find-identity -v -p codesigning \
            | awk -F '"' '/Developer ID Application/ { print $2; exit }'
    )
fi

if [ -z "$CODE_SIGN_IDENTITY" ]; then
    echo "No Developer ID Application signing identity found." >&2
    echo "Set CODE_SIGN_IDENTITY to a stable signing identity." >&2
    exit 1
fi

codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp=none \
    --entitlements Resources/PiAgentShelf.entitlements \
    --sign "$CODE_SIGN_IDENTITY" \
    --identifier com.mustafaj.PiAgentShelf \
    "$APP_DIR" >/dev/null
printf 'Built %s with %s\n' "$APP_DIR" "$CODE_SIGN_IDENTITY"
