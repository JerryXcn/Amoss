#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
amoss_arch="${1:-$(uname -m)}"
amoss_output="${AMOSS_OUTPUT_DIR:-dist}"
bash scripts/check-environment.sh
python3 scripts/check-localizations.py
bash scripts/fetch-tools.sh "$amoss_arch"
bash scripts/build-mirror.sh "$amoss_arch"
python3 scripts/generate-project.py
mkdir -p build/module-cache
swift -module-cache-path build/module-cache scripts/make-icon.swift "$PWD"
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
iconutil -c icns build/MirrorIcon.iconset -o Resources/MirrorIcon.icns
xcodebuild -project Amoss.xcodeproj -scheme Amoss -configuration Release \
  -derivedDataPath build/Xcode ARCHS="$amoss_arch" ONLY_ACTIVE_ARCH=NO \
  "OTHER_SWIFT_FLAGS=\$(inherited) -file-prefix-map $PWD=/amoss -debug-prefix-map $PWD=/amoss" \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p "$amoss_output"
if [ -d "$amoss_output/Amoss.app" ]; then rm -rf "$amoss_output/Amoss.app"; fi
ditto build/Xcode/Build/Products/Release/Amoss.app "$amoss_output/Amoss.app"
strip -S "$amoss_output/Amoss.app/Contents/MacOS/Amoss"
python3 scripts/release-metadata.py record "$amoss_output/Amoss.app" "$amoss_arch"
identity="${AMOSS_SIGNING_IDENTITY:--}"
sign_options=(--force --sign "$identity" --options runtime)
if [ "$identity" = "-" ]; then sign_options+=(--timestamp=none); else sign_options+=(--timestamp); fi
codesign "${sign_options[@]}" "$amoss_output/Amoss.app/Contents/Resources/Tools/adb"
codesign "${sign_options[@]}" "$amoss_output/Amoss.app/Contents/Helpers/Amoss Mirror.app"
codesign "${sign_options[@]}" "$amoss_output/Amoss.app"
codesign --verify --deep --strict "$amoss_output/Amoss.app"
bash scripts/verify-bundle.sh "$amoss_output/Amoss.app"
echo "Built: $amoss_output/Amoss.app"
