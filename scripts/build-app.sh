#!/bin/bash
# Builds app/build/Noodle.app (release, ad-hoc signed). Prints the bundle path.
# Env: CONFIG=debug|release (default release), OUT=<dir> (default app/build)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/app"
CONFIG="${CONFIG:-release}"
OUT="${OUT:-$PKG/build}"
APP="$OUT/Noodle.app"

swift build -c "$CONFIG" --package-path "$PKG" >&2
BIN="$(swift build -c "$CONFIG" --package-path "$PKG" --show-bin-path)/ClaudePosture"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudePosture"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
rsync -a --exclude '.DS_Store' "$PKG/Resources/" "$APP/Contents/Resources/"

plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP" >&2
echo "$APP"
