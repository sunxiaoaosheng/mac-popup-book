#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift run --package-path "$ROOT/Scenes/forest-cabin" CompanionCheck "${1:-30}" "$ROOT/build/checks/companion" "${2:-60}"
