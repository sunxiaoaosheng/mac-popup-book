#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SHARED=(Package.swift Modules Apps/BookHost Tests Tools/BookIntegrationCheck Templates)
ALL=("${SHARED[@]}" Scenes Tools/IsolationProbe Experiments)
FILES=("${ALL[@]}")
if [[ "${2:-}" == shared ]]; then FILES=("${SHARED[@]}"); fi
ACTION=format
if [[ "${1:-}" == "--check" ]]; then ACTION=lint; fi
if [[ "$ACTION" == lint ]]; then
  swift format lint --strict --recursive "${FILES[@]}"
else
  swift format format --in-place --recursive "${FILES[@]}"
fi
