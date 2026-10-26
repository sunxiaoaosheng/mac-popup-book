#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run RenderCheck build/checks/render
swift run WindowCheck
