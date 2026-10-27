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
for RESOURCE in "$BIN"/MacPopupBook_*.bundle; do
    [ -d "$RESOURCE" ] || continue
    cp -R "$RESOURCE" "$APP/Contents/Resources/"
done
cp -R Apps/ForestCabin/Resources/en.lproj Apps/ForestCabin/Resources/zh-Hans.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
python3 scripts/write-build-receipt.py
echo "已构建：$APP"
