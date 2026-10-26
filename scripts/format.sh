#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--check" ]]; then
  swift format lint --strict --recursive Package.swift Modules Characters Apps Tests Tools
else
  swift format format --in-place --recursive Package.swift Modules Characters Apps Tests Tools
fi
