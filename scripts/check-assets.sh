#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build/asset-preflight
bash scripts/blender.sh --background --factory-startup --disable-autoexec --python-exit-code 1 --python "$ROOT/Experiments/VolumeCat/Tools/AssetPipeline/rig_probe.py" -- "$ROOT/build/asset-preflight"
swift run --package-path "$ROOT/Experiments/VolumeCat" AssetCheck "$ROOT/build/asset-preflight/rig-probe.usdz" "$ROOT/build/asset-preflight/render"
