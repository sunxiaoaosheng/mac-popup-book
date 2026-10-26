#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p .build/cache artifacts
bash test.sh
FRAMEWORKS=(-framework AppKit -framework SceneKit -framework IOKit -framework AVFoundation)
xcrun swiftc -swift-version 5 -O -module-cache-path .build/cache Sources/BookState.swift Sources/PaperScene.swift Tools/RenderCheck.swift -framework Metal "${FRAMEWORKS[@]}" -o .build/render-check
.build/render-check artifacts
xcrun swiftc -swift-version 5 -O -module-cache-path .build/cache Sources/BookState.swift Sources/LidInput.swift Sources/PaperScene.swift Sources/BookAudio.swift Sources/BookModel.swift Tools/LifecycleCheck.swift "${FRAMEWORKS[@]}" -o .build/lifecycle-check
.build/lifecycle-check

xcrun swiftc -swift-version 5 -O -module-cache-path .build/cache Sources/BookState.swift Sources/LidInput.swift Sources/PaperScene.swift Sources/BookAudio.swift Sources/BookModel.swift Sources/SceneView.swift Tools/WindowCheck.swift -framework SwiftUI "${FRAMEWORKS[@]}" -o .build/window-check
.build/window-check
