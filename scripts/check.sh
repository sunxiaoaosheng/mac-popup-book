#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/format.sh --check
python3 scripts/check-boundaries.py
python3 scripts/check-localization.py
bash scripts/test.sh
bash scripts/build.sh
