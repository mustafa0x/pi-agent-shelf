#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
working_dir=$(mktemp -d)
trap 'rm -rf "$working_dir"' EXIT
iconset="$working_dir/AppIcon.iconset"
mkdir -p "$iconset"

# Keep the official logo unchanged on a white macOS-style tile.
magick -background none Resources/PiLogo.svg -resize 1024x1024 "$working_dir/logo.png"
magick -size 1024x1024 xc:none -fill white -stroke none \
    -draw 'roundrectangle 96,96 928,928 184,184' \
    "$working_dir/logo.png" -compose over -composite Resources/AppIcon.png

for size in 16 32 128 256 512; do
    magick Resources/AppIcon.png -resize "${size}x${size}" "$iconset/icon_${size}x${size}.png"
    doubled=$((size * 2))
    magick Resources/AppIcon.png -resize "${doubled}x${doubled}" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns

# The menu bar uses the colored logo alone, with no white tile or outer padding.
magick -background none Resources/PiLogo.svg -trim +repage -resize 36x36 -depth 8 Resources/MenuBarIcon@2x.png
magick Resources/MenuBarIcon@2x.png -resize 18x18 Resources/MenuBarIcon.png
