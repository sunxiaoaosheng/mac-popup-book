#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
python3 -m unittest discover -s Tests/AudioPipelineTests
