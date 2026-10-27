#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/format.sh --check
python3 scripts/check-boundaries.py
python3 scripts/check-localization.py
bash scripts/test.sh
python3 - <<'PY'
import json,subprocess
for page in json.load(open('Book/published-pages.json'))['pages']:
    subprocess.run(['python3','scripts/page.py','check',page],check=True)
PY
bash scripts/build.sh
