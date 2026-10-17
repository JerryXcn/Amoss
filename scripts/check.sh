#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-localizations.py
python3 -m unittest discover -s Tests/BuildToolsTests -v
for script in scripts/*.sh; do bash -n "$script"; done
mkdir -p build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/module-cache" \
swift test --disable-sandbox --scratch-path build/swift --cache-path build/swift-cache
