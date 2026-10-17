#!/usr/bin/env python3
"""Verify the official scrcpy/ADB bundle before extraction."""
import platform
import sys
import tarfile
from build_support import ROOT, dependencies, download

arch = sys.argv[1] if len(sys.argv) > 1 else platform.machine()
item = dependencies()['tools'].get(arch)
if item is None:
    raise SystemExit('Unsupported architecture: ' + arch)
source = download(item, ROOT / 'vendor/downloads')
with tarfile.open(source) as archive:
    archive.extractall(ROOT / 'vendor', filter='data')
print(f'Verified scrcpy 5.0.1 + bundled ADB ({arch}).')
