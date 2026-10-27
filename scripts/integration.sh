#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Default: background-only helpers, no windows, no focus changes, no user preferences or saves.
python3 scripts/book-build.py --background-check --pages contract-red,contract-blue
"$PWD/build/后台验收-integration.app/Contents/MacOS/BookIntegrationCheck"
python3 scripts/book-build.py --background-check --pages forest-cabin
"$PWD/build/后台验收-forest-cabin.app/Contents/MacOS/BookIntegrationCheck" --capture-dir "$PWD/build/checks/forest-isolated"
