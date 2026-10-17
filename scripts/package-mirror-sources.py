#!/usr/bin/env python3
"""Package corresponding sources with licenses and reproducible archive metadata."""
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from build_support import ROOT, dependencies, digest, source_archive, verify, version

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
manifest = []
for item in dependencies()['sources']:
    source = ROOT / 'vendor/source-archives' / item['archive']
    verify(source, item['sha256'])
    shutil.copyfile(source, destination / item['archive'])
    manifest.append({key: item[key] for key in ('component', 'archive', 'source', 'sha256')})
entries = [(ROOT / 'Integrations/Scrcpy', 'amoss-mirror/Integrations/Scrcpy'),
           (ROOT / 'Sources/AmossCore/MirrorWindowLayout.swift', 'amoss-mirror/Sources/AmossCore/MirrorWindowLayout.swift'),
           (ROOT / 'Sources/AmossCore/Localization.swift', 'amoss-mirror/Sources/AmossCore/Localization.swift'),
           (ROOT / 'Sources/AmossCore/Resources', 'amoss-mirror/Sources/AmossCore/Resources')]
for name in ('LICENSE', 'NOTICE', 'Resources/Info.plist', 'Resources/ThirdPartyNotices.txt', 'Resources/Licenses'):
    entries.append((ROOT / name, 'amoss-mirror/' + name))
for name in ('build-mirror.sh', 'build-mirror-deps.sh', 'prepare-mirror-source.py', 'helper-build-requirements.txt',
             'fetch-sources.py', 'test-mirror.sh', 'check-environment.sh', 'dependencies.json', 'build_support.py'):
    entries.append((ROOT / 'scripts' / name, 'amoss-mirror/scripts/' + name))
archive = destination / 'scrcpy-5.0.1-amoss-sources.tar.gz'
# Recreate the modified tree from the verified archive. A copied app bundle or
# an old local build directory must never silently supply stale derived sources.
with tempfile.TemporaryDirectory(prefix='amoss-corresponding-') as temporary:
    workspace = Path(temporary)
    (workspace / 'scripts').mkdir()
    shutil.copyfile(ROOT / 'scripts/prepare-mirror-source.py', workspace / 'scripts/prepare-mirror-source.py')
    shutil.copytree(ROOT / 'Integrations/Scrcpy', workspace / 'Integrations/Scrcpy')
    upstream = workspace / 'build/mirror-sources'
    upstream.mkdir(parents=True)
    item = next(item for item in dependencies()['sources'] if item['component'] == 'scrcpy')
    with tarfile.open(destination / item['archive']) as source:
        source.extractall(upstream, filter='data')
    subprocess.run([sys.executable, str(workspace / 'scripts/prepare-mirror-source.py')],
                   check=True, stdout=subprocess.DEVNULL)
    source_archive(archive, entries + [(workspace / 'build/mirror-client-src', 'amoss-mirror/scrcpy')])
manifest.append({'component': 'scrcpy with Amoss native toolbar', 'archive': archive.name,
                 'source': 'Amoss integration and complete modified client, included here', 'sha256': digest(archive)})
(destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(destination / 'README.txt').write_text(f'''Amoss {version()[0]} corresponding sources

Upstream source archives are unmodified; manifest.json records pinned SHA-256 values.
scrcpy-5.0.1-amoss-sources.tar.gz includes the complete modified client, Amoss
native UI and control sources, build scripts, LICENSE and NOTICE. Modified
upstream files carry notices; scrcpy/AMOSS-MODIFICATIONS.txt lists the changes.
FFmpeg (LGPL-2.1-or-later), SDL (zlib) and dav1d (BSD-2-Clause) are statically
linked. libusb sources are retained from the upstream release; AOA/OTG is disabled.
The official ADB and Android server binaries are unchanged apart from signing.

Rebuild on a matching-architecture Mac with Xcode 26+, Python 3.12+, CMake 3.20+:
  tar -xzf scrcpy-5.0.1-amoss-sources.tar.gz
  mkdir -p amoss-mirror/vendor/source-archives
  cp ffmpeg-*.tar.xz SDL-*.tar.gz dav1d-*.tar.xz libusb-*.tar.gz scrcpy-v*-source.tar.gz amoss-mirror/vendor/source-archives/
  cd amoss-mirror
  bash scripts/build-mirror.sh
  bash scripts/test-mirror.sh

Pinned Python build tools still require network access on first use. Output:
build/mirror-client-<architecture>/client/app/scrcpy. No build tools are required
by installed users. The sources permit rebuilding and relinking with a modified
LGPL library: after the first build, edit build/mirror-sources/ffmpeg-9.0.2,
remove build/mirror-deps/<architecture> and rerun scripts/build-mirror.sh.
This rebuilds every static dependency; retained extracted sources are intentional.
Replace the executable inside a COPY of Amoss Mirror.app, then ad-hoc sign that
helper and its enclosing Amoss.app for local testing. Developer ID is not needed
for this local rebuild. Keep originals and corresponding sources for distribution.
''')
print('Packaged corresponding sources, licenses and checksum manifest.')
