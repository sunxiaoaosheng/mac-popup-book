#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product ForestBook
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/build/林间小屋.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ForestBook" "$APP/Contents/MacOS/ForestBook"
cp Apps/ForestCabin/Resources/Info.plist "$APP/Contents/Info.plist"
cp Apps/ForestCabin/Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Apps/ForestCabin/Resources/Audio "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "已构建：$APP"
