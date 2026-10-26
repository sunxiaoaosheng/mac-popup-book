#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -d "$ROOT/build/林间小屋.app" ]]; then bash "$ROOT/scripts/build.sh"; fi
open "$ROOT/build/林间小屋.app"
