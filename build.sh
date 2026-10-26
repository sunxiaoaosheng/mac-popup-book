#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/林间小屋.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/.build/cache"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos14.0 -module-cache-path "$ROOT/.build/cache" \
  "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/ForestBook" \
  -framework AppKit -framework SwiftUI -framework SceneKit -framework IOKit -framework AVFoundation
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
cp -R "$ROOT/Resources/Audio" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "已构建：$APP"
