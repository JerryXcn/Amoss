#!/bin/bash
set -euo pipefail
case "${ARCHS:-$(uname -m)}" in
  arm64) upstream_arch=aarch64 ;;
  x86_64) upstream_arch=x86_64 ;;
  *) echo "Build one architecture at a time." >&2; exit 1 ;;
esac
source_dir="$SRCROOT/vendor/scrcpy-macos-$upstream_arch-v5.0.1"
mirror_binary="$SRCROOT/build/mirror-client-${ARCHS:-$(uname -m)}/client/app/scrcpy"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
if [ ! -x "$mirror_binary" ] || [ ! -x "$source_dir/adb" ]; then
  echo "Run scripts/build.sh first to prepare the native mirror helper." >&2; exit 1
fi
mkdir -p "$destination/Tools" "$destination/Licenses"
for item in adb scrcpy-server disconnected.png LICENSE scrcpy.1; do
  cp "$source_dir/$item" "$destination/Tools/$item"
done
cp "$SRCROOT/build/MirrorIcon.iconset/icon_256x256@2x.png" "$destination/Tools/scrcpy.png"
helper="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/Amoss Mirror.app/Contents"
mkdir -p "$helper/MacOS" "$helper/Resources"
cp "$mirror_binary" "$helper/MacOS/scrcpy"
cp "$SRCROOT/Resources/Helper-Info.plist" "$helper/Info.plist"
cp "$SRCROOT/Resources/MirrorIcon.icns" "$helper/Resources/AppIcon.icns"
cp "$SRCROOT/Resources/AppIcon.icns" "$destination/AppIcon.icns"
for language in en zh-Hans; do
  cp -R "$SRCROOT/Sources/AmossCore/Resources/$language.lproj" "$destination/"
  cp -R "$SRCROOT/Sources/AmossCore/Resources/$language.lproj" "$helper/Resources/"
done
cp "$SRCROOT/Resources/ThirdPartyNotices.txt" "$destination/Licenses/ThirdPartyNotices.txt"
cp "$SRCROOT/LICENSE" "$destination/Licenses/Amoss-LICENSE.txt"
cp "$SRCROOT/NOTICE" "$destination/Licenses/Amoss-NOTICE.txt"
if [ -d "$SRCROOT/Resources/Licenses" ]; then
  cp -R "$SRCROOT/Resources/Licenses/." "$destination/Licenses/"
fi
mkdir -p "$helper/Resources/Licenses"
cp -R "$destination/Licenses/." "$helper/Resources/Licenses/"
# Remove the flat executable left by pre-helper development builds.
rm -f "$destination/Tools/scrcpy"
