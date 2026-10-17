#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
amoss_arch="${1:-$(uname -m)}"
amoss_app="${2:-dist/Amoss.app}"
test -d "$amoss_app"
python3 scripts/release-metadata.py check "$amoss_app" "$amoss_arch"
amoss_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$amoss_app/Contents/Info.plist")
bash scripts/verify-bundle.sh "$amoss_app"
mkdir -p build dist
stage=$(mktemp -d "$PWD/build/dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$amoss_app" "$stage/Amoss.app"
ln -s /Applications "$stage/Applications"
cp Resources/Install.txt "$stage/Installation.txt"
cp LICENSE NOTICE "$stage/"
python3 scripts/package-mirror-sources.py "$stage/Third-party sources"
cp "$amoss_app/Contents/Resources/build-manifest.json" "$stage/Third-party sources/build-manifest.json"
hdiutil create -volname Amoss -srcfolder "$stage" -ov -format UDZO \
  "dist/Amoss-$amoss_version-$amoss_arch.dmg"
hdiutil verify "dist/Amoss-$amoss_version-$amoss_arch.dmg"
(
  cd dist
  shasum -a 256 "Amoss-$amoss_version-$amoss_arch.dmg" > "Amoss-$amoss_version-$amoss_arch.dmg.sha256"
  shasum -a 256 -c "Amoss-$amoss_version-$amoss_arch.dmg.sha256"
)
echo "Packaged: $PWD/dist/Amoss-$amoss_version-$amoss_arch.dmg"
