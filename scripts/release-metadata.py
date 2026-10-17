#!/usr/bin/env python3
"""Bind a built application to its source inputs; reject stale packaging."""
import json
import plistlib
import sys
from pathlib import Path
from build_support import ROOT, build_fingerprint, version

mode, path = sys.argv[1:3]
app = Path(path)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
helper = plistlib.loads((app / 'Contents/Helpers/Amoss Mirror.app/Contents/Info.plist').read_bytes())
expected_version, expected_build = version()
for value in (info, helper):
    if (value['CFBundleShortVersionString'], value['CFBundleVersion']) != (expected_version, expected_build):
        raise SystemExit('Application/helper version does not match source. Rebuild before packaging.')
metadata_path = app / 'Contents/Resources/build-manifest.json'
if mode == 'record':
    metadata = {'version': expected_version, 'build': expected_build, 'architecture': sys.argv[3],
                'source_sha256': build_fingerprint()}
    metadata_path.write_text(json.dumps(metadata, indent=2) + '\n')
elif mode == 'check':
    metadata = json.loads(metadata_path.read_text())
    if metadata['source_sha256'] != build_fingerprint():
        raise SystemExit('Source inputs changed since this application was built. Rebuild before packaging.')
    if len(sys.argv) > 3 and metadata['architecture'] != sys.argv[3]:
        raise SystemExit('Packaging architecture does not match the built application.')
else:
    raise SystemExit('Expected record or check')
print('Release source/version match verified: ' + expected_version)
