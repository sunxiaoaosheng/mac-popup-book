#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/.build/cache" "$ROOT/Sources/BookState.swift" "$ROOT/Sources/LidInput.swift" "$ROOT/Tests/main.swift" -framework IOKit -o "$ROOT/.build/checks"
"$ROOT/.build/checks" "$@"
