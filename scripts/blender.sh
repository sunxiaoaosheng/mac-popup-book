#!/bin/bash
set -euo pipefail
if [[ -n "${BLENDER_BIN:-}" ]]; then
    BLENDER_EXEC="$BLENDER_BIN"
elif [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    BLENDER_EXEC=/Applications/Blender.app/Contents/MacOS/Blender
else
    BLENDER_EXEC="$(command -v blender || true)"
fi
if [[ -z "$BLENDER_EXEC" || ! -x "$BLENDER_EXEC" ]]; then
    echo "未找到Blender；可通过BLENDER_BIN指定已有程序。正常应用构建不需要此工具。" >&2
    exit 2
fi
exec "$BLENDER_EXEC" "$@"
