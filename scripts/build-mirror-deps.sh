#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-environment.sh
root="$PWD"
amoss_arch="${1:-$(uname -m)}"
if [ "$amoss_arch" != "$(uname -m)" ]; then
  echo "Build the mirror helper on a Mac matching the target architecture." >&2
  exit 1
fi
prefix="$root/build/mirror-deps/$amoss_arch"
sources="$root/build/mirror-sources"
mkdir -p "$prefix" "$sources"
# Keep extracted sources (including intentional LGPL edits), but never reuse
# static objects from another recipe, checkout, dependency set or toolchain.
native_stamp=$(python3 - "$root" "$amoss_arch" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
root = Path(sys.argv[1])
state = {'root': str(root.resolve()), 'arch': sys.argv[2]}
for name in ('build-mirror-deps.sh', 'dependencies.json', 'helper-build-requirements.txt'):
    state[name] = hashlib.sha256((root / 'scripts' / name).read_bytes()).hexdigest()
for command in (['xcodebuild', '-version'], ['cmake', '--version'], ['xcrun', 'clang', '--version']):
    state[' '.join(command)] = subprocess.check_output(command, text=True)
print(hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest())
PY
)
if [ -d "$prefix/lib" ] && { [ ! -f "$prefix/.build-inputs-sha256" ] || [ "$(cat "$prefix/.build-inputs-sha256")" != "$native_stamp" ]; }; then
  echo "Native dependency inputs changed; rebuilding generated static-library cache."
  rm -rf "$prefix"
  mkdir -p "$prefix"
fi
requirements_stamp=$(shasum -a 256 scripts/helper-build-requirements.txt | awk '{print $1}')
if [ ! -x build/helper-tools/bin/meson ]; then
  python3 -m venv build/helper-tools
fi
if [ ! -f build/helper-tools/.requirements-sha256 ] || [ "$(cat build/helper-tools/.requirements-sha256)" != "$requirements_stamp" ]; then
  build/helper-tools/bin/python -m pip install -r scripts/helper-build-requirements.txt
  echo "$requirements_stamp" > build/helper-tools/.requirements-sha256
fi
export PATH="$root/build/helper-tools/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=15.0
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
unset PKG_CONFIG_PATH
jobs=$(getconf _NPROCESSORS_ONLN)
mapping=$(printf '%q' "-ffile-prefix-map=$root=/amoss")
debug_mapping=$(printf '%q' "-fdebug-prefix-map=$root=/amoss")
export CFLAGS="-O2 $mapping $debug_mapping"
python3 scripts/fetch-sources.py
python3 - "$sources" <<'PY'
import hashlib, json, sys, tarfile
from pathlib import Path
base = Path('vendor/source-archives')
target = Path(sys.argv[1])
for item in json.loads((base / 'manifest.json').read_text()):
    source = base / item['archive']
    if hashlib.sha256(source.read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit(f"Checksum mismatch: {source}")
    with tarfile.open(source) as archive:
        top = archive.getnames()[0].split('/')[0]
        if not (target / top).exists():
            archive.extractall(target, filter='data')
PY

if [ ! -f "$prefix/lib/libSDL3.a" ]; then
  cmake -S "$sources/SDL-release-3.4.18" -B "$prefix/build-sdl" -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES="$amoss_arch" \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF
  cmake --build "$prefix/build-sdl" -j "$jobs"
  cmake --install "$prefix/build-sdl"
fi
if [ ! -f "$prefix/lib/libdav1d.a" ]; then
  meson setup "$prefix/build-dav1d" "$sources/dav1d-1.5.4" \
    --prefix="$prefix" --libdir=lib --buildtype=release \
    --default-library=static -Denable_tests=false -Denable_tools=false
  ninja -C "$prefix/build-dav1d" -j "$jobs"
  ninja -C "$prefix/build-dav1d" install
fi
if [ ! -f "$prefix/lib/libavcodec.a" ]; then
  mkdir -p "$prefix/build-ffmpeg"
  (
    cd "$prefix/build-ffmpeg"
    "$sources/ffmpeg-9.0.2/configure" --prefix="$prefix" \
      --pkg-config-flags=--static --extra-cflags="$CFLAGS -fPIC" \
      --disable-shared --enable-static --disable-autodetect \
      --disable-programs --disable-doc --disable-swscale --disable-avfilter \
      --disable-avdevice --disable-network --disable-everything \
      --disable-vulkan --disable-vdpau --disable-vaapi \
      --enable-swresample --enable-libdav1d --enable-zlib \
      --enable-decoder=h264,hevc,av1,vp8,vp9,libdav1d,pcm_s16le,opus,aac,flac,png \
      --enable-protocol=file --enable-demuxer=image2 --enable-parser=png \
      --enable-muxer=matroska,mp4,opus,flac,wav --enable-videotoolbox \
      --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox,av1_videotoolbox,vp9_videotoolbox
    # configure embeds its invocation into the executable; normalize only that
    # generated display string, not the install paths used by make.
    python3 - "$root" <<'PY'
from pathlib import Path
import sys
path = Path('config.h')
path.write_text(path.read_text().replace(sys.argv[1], '/amoss'))
PY
    make -j "$jobs"
    make install
  )
fi
echo "$native_stamp" > "$prefix/.build-inputs-sha256"
echo "Static mirror dependencies ready: $prefix"
