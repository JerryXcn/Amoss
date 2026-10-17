#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
amoss_arch="${1:-$(uname -m)}"
export PATH="$root/build/helper-tools/bin:$PATH"
export PKG_CONFIG_LIBDIR="$root/build/mirror-deps/$amoss_arch/lib/pkgconfig"
unset PKG_CONFIG_PATH
client="$root/build/mirror-client-src/app"
flags=( $(pkg-config --cflags --libs --static sdl3 libavutil) )
clang -std=c11 -D_DARWIN_C_SOURCE -D_POSIX_C_SOURCE=200809L \
  -mmacosx-version-min=15.0 -I"$client/src" \
  -I"$root/build/mirror-client-$amoss_arch/client/app" -IIntegrations/Scrcpy \
  Integrations/Scrcpy/test_controls.c Integrations/Scrcpy/amoss_controls.c \
  "$client/src/control_msg.c" "$client/src/util/str.c" \
  "$client/src/util/strbuf.c" "$client/src/util/log.c" \
  "$client/src/util/term.c" "$client/src/compat.c" \
  "${flags[@]}" -o build/test-mirror-controls
build/test-mirror-controls
