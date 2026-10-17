#!/bin/bash
set -euo pipefail
if [ "$(uname -s)" != Darwin ]; then echo "Amoss builds require macOS." >&2; exit 1; fi
python3 - <<'PY'
import sys
if sys.version_info < (3, 12):
    raise SystemExit("Python 3.12+ is required. Install it and put it before Apple's Python in PATH.")
PY
for tool in xcodebuild xcrun swiftc cmake make curl shasum iconutil codesign; do
  command -v "$tool" >/dev/null || { echo "Missing developer tool: $tool" >&2; exit 1; }
done
xcode_major=$(xcodebuild -version | awk '/^Xcode / {split($2,v,"."); print v[1]}')
if [ "${xcode_major:-0}" -lt 26 ]; then
  echo "Select full Xcode 26 or newer with xcode-select; Command Line Tools alone are insufficient." >&2; exit 1
fi
python3 - <<'PY'
import re, subprocess
text = subprocess.check_output(['cmake', '--version'], text=True)
version = tuple(map(int, re.search(r'version (\d+)\.(\d+)', text).groups()))
if version < (3, 20):
    raise SystemExit('CMake 3.20+ is required.')
PY
echo "Build environment verified: Xcode 26+, Python 3.12+, CMake 3.20+."
