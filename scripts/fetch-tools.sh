#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/fetch-tools.py "${1:-$(uname -m)}"
