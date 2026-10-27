#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
ASSET_WORK="$(mktemp -d "$ROOT/build/cat-candidate.XXXXXX")"
ASSET_BACKUP=""
on_error() {
    local status=$?
    if [[ -n "$ASSET_BACKUP" && -d "$ASSET_BACKUP" && ! -e "$ROOT/build/cat-candidate" ]]; then
        mv "$ASSET_BACKUP" "$ROOT/build/cat-candidate"
    fi
    echo "检查失败，候选与证据保留于：$ASSET_WORK" >&2
    exit "$status"
}
trap on_error ERR
bash scripts/blender.sh --background --factory-startup --disable-autoexec --python-exit-code 1 --python "$ROOT/Tools/AssetPipeline/cat_candidate.py" -- "$ASSET_WORK"
bash scripts/blender.sh --background --factory-startup --disable-autoexec "$ASSET_WORK/ForestCatCandidate.blend" --python-exit-code 1 --python "$ROOT/Tools/AssetPipeline/verify_cat_source.py" -- "$ASSET_WORK"
for task_clip in CatIdle CatWalk CatSit CatTurn; do
    swift run AssetCheck "$ASSET_WORK/$task_clip.usdz" "$ASSET_WORK/scenekit-$task_clip" > "$ASSET_WORK/$task_clip-import.log" 2>&1
done
swift run PlaybackCheck "$ASSET_WORK" > "$ASSET_WORK/playback-check.log" 2>&1
swift run CandidateSceneCheck "$ASSET_WORK" > "$ASSET_WORK/book-preview.log" 2>&1
if [[ -d "$ROOT/build/cat-candidate" ]]; then
    ASSET_STAMP="$(date +%Y%m%d%H%M%S)"
    ASSET_BACKUP="$ROOT/build/cat-candidate.previous-$ASSET_STAMP"
    mv "$ROOT/build/cat-candidate" "$ASSET_BACKUP"
fi
mv "$ASSET_WORK" "$ROOT/build/cat-candidate"
echo "候选生成与检查通过：$ROOT/build/cat-candidate；默认应用纸猫未替换。"
