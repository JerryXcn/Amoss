#!/bin/bash
set -euo pipefail
app="${1:-dist/Amoss.app}"
for item in Contents/MacOS/Amoss Contents/Resources/Tools/adb 'Contents/Helpers/Amoss Mirror.app/Contents/MacOS/scrcpy'; do
  test -x "$app/$item"
  dependencies=$(otool -L "$app/$item" | tail -n +2 | awk '/compatibility version/ {print $1}')
  while IFS= read -r dependency; do
    case "$dependency" in
      /usr/lib/*|/System/Library/*|@rpath/libswift*) ;;
      *) echo "Unexpected external dependency: $dependency in $item" >&2; exit 1 ;;
    esac
  done <<< "$dependencies"
done
test -s "$app/Contents/Resources/Tools/scrcpy-server"
test -s "$app/Contents/Resources/Tools/LICENSE"
test -s "$app/Contents/Resources/AppIcon.icns"
for license in Amoss-LICENSE.txt Amoss-NOTICE.txt ThirdPartyNotices.txt ADB-NOTICE.txt scrcpy-LICENSE.txt FFmpeg-COPYING.LGPLv2.1.txt SDL-LICENSE.txt.txt dav1d-COPYING.txt; do
  test -s "$app/Contents/Resources/Licenses/$license"
  test -s "$app/Contents/Helpers/Amoss Mirror.app/Contents/Resources/Licenses/$license"
done
python3 - "$app" <<'PY'
import json, plistlib, sys
from pathlib import Path
app = Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
helper = plistlib.loads((app / 'Contents/Helpers/Amoss Mirror.app/Contents/Info.plist').read_bytes())
metadata = json.loads((app / 'Contents/Resources/build-manifest.json').read_text())
assert (info['CFBundleShortVersionString'], info['CFBundleVersion']) == (metadata['version'], metadata['build'])
assert (helper['CFBundleShortVersionString'], helper['CFBundleVersion']) == (metadata['version'], metadata['build'])
for relative in ('Contents/MacOS/Amoss', 'Contents/Helpers/Amoss Mirror.app/Contents/MacOS/scrcpy'):
    if b'/Users/' in (app / relative).read_bytes():
        raise SystemExit('Local home path embedded in release executable: ' + relative)
PY
for language in en zh-Hans; do
  test -s "$app/Contents/Resources/$language.lproj/Localizable.strings"
  test -s "$app/Contents/Helpers/Amoss Mirror.app/Contents/Resources/$language.lproj/Localizable.strings"
done
env -i HOME="$HOME" PATH=/usr/bin:/bin "$app/Contents/Resources/Tools/adb" version
env -i HOME="$HOME" PATH=/usr/bin:/bin "$app/Contents/Helpers/Amoss Mirror.app/Contents/MacOS/scrcpy" --version
codesign --verify --deep --strict "$app"
echo "Bundle verified: no Homebrew or non-system dylib dependencies."
