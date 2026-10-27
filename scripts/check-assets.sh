#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/asset-preflight
bash scripts/blender.sh --background --factory-startup --disable-autoexec --python-exit-code 1 --python "$ROOT/Tools/AssetPipeline/rig_probe.py" -- "$ROOT/build/asset-preflight"
swift run AssetCheck "$ROOT/build/asset-preflight/rig-probe.usdz" "$ROOT/build/asset-preflight/render"
