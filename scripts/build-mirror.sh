#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
amoss_arch="${1:-$(uname -m)}"
bash scripts/build-mirror-deps.sh "$amoss_arch"
python3 scripts/prepare-mirror-source.py
export PATH="$root/build/helper-tools/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=15.0
prefix="$root/build/mirror-deps/$amoss_arch"
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
unset PKG_CONFIG_PATH
output="$root/build/mirror-client-$amoss_arch"
mkdir -p "$output" "$root/build/module-cache"
swiftc -parse-as-library -emit-library -static -O -whole-module-optimization \
  -swift-version 6 -target "$amoss_arch-apple-macos15.0" \
  -file-prefix-map "$root=/amoss" -debug-prefix-map "$root=/amoss" \
  -module-name AmossMirrorToolbar -module-cache-path "$root/build/module-cache" \
  Integrations/Scrcpy/MirrorToolbar.swift Integrations/Scrcpy/MirrorWindow.swift \
  Sources/AmossCore/MirrorWindowLayout.swift Sources/AmossCore/Localization.swift \
  -o "$output/libAmossMirrorToolbar.a"
swift_lib="$(dirname "$(xcrun --find swiftc)")/../lib/swift/macosx"
c_args=$(python3 -c 'import json,sys; print(json.dumps(["-I"+sys.argv[1]+"/include", "-ffile-prefix-map="+sys.argv[2]+"=/amoss", "-fdebug-prefix-map="+sys.argv[2]+"=/amoss"]))' "$prefix" "$root")
meson setup "$output/client" "$root/build/mirror-client-src" \
  --reconfigure --buildtype=release -Dcompile_server=false -Dportable=true -Dstatic=true \
  -Dusb=false -Dvaapi=false -Dv4l2=false \
  -Dc_args="$c_args" \
  -Dc_link_args="['$output/libAmossMirrorToolbar.a', '-L$prefix/lib', '-L$swift_lib', '-L/usr/lib/swift', '-Wl,-rpath,/usr/lib/swift']"
ninja -C "$output/client"
# Remove local object-file paths from the linker symbol table before signing.
strip -S "$output/client/app/scrcpy"
echo "Built native mirror toolbar: $output/client/app/scrcpy"
