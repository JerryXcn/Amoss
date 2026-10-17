#!/usr/bin/env python3
"""Fetch and verify every pinned source archive before extracting licenses."""
import json
from pathlib import Path
import shutil
import tarfile
from build_support import ROOT, dependencies, download

archives = ROOT / 'vendor/source-archives'
licenses = ROOT / 'Resources/Licenses'
licenses.mkdir(parents=True, exist_ok=True)
manifest = []
for item in dependencies()['sources']:
    # Reuse the earlier download only after the same pinned checksum validation.
    legacy = ROOT / 'vendor/downloads' / item['archive']
    if not (archives / item['archive']).exists() and legacy.exists():
        archives.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(legacy, archives / item['archive'])
    source = download(item, archives)
    found = set()
    with tarfile.open(source) as archive:
        for member in archive.getmembers():
            path = Path(member.name)
            if len(path.parts) == 2 and path.name in item['licenses'] and member.isfile():
                (licenses / item['licenses'][path.name]).write_bytes(archive.extractfile(member).read())
                found.add(path.name)
    if found != set(item['licenses']):
        raise RuntimeError(f"Missing license in {item['archive']}")
    manifest.append({key: item[key] for key in ('component', 'archive', 'source', 'sha256')})
    print('Verified sources and licenses: ' + item['component'], flush=True)
(archives / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(archives / 'README.txt').write_text('Pinned upstream source archives for Amoss. See manifest.json for SHA-256 checksums.\n'
    'Amoss modifies the scrcpy client; its integration and full modified source are supplied separately.\n'
    'ADB and the Android server are upstream release binaries. Preserve all accompanying licenses.\n')
