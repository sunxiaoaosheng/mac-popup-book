#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift run CompanionCheck "${1:-30}" "$ROOT/build/checks/companion" "${2:-60}"
