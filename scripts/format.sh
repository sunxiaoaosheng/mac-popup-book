#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ACTION=format
if [[ "${1:-}" == "--check" ]]; then ACTION=lint; fi
if [[ "$ACTION" == lint ]]; then
  swift format lint --strict --recursive Package.swift Modules Apps/BookHost Tests Scenes Templates Tools/IsolationProbe Experiments
else
  swift format format --in-place --recursive Package.swift Modules Apps/BookHost Tests Scenes Templates Tools/IsolationProbe Experiments
fi
