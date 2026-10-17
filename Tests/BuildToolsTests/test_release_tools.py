import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from build_support import build_fingerprint, digest, download, source_archive, version


class ReleaseToolsTests(unittest.TestCase):
    def test_corrupt_cached_archive_is_rejected_without_download(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.tar.gz'
            path.write_bytes(b'changed contents')
            item = {'archive': path.name, 'sha256': '0' * 64, 'source': 'https://example.invalid/source'}
            with patch('build_support.subprocess.run') as run:
                with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
                    download(item, directory)
                run.assert_not_called()

    def test_bad_download_never_becomes_a_cache_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            item = {'archive': 'source.tar.gz', 'sha256': '0' * 64, 'source': 'https://example.invalid/source'}
            def fetch(command, **kwargs):
                Path(command[command.index('--output') + 1]).write_bytes(b'truncated download')
            with patch('build_support.subprocess.run', side_effect=fetch):
                with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
                    download(item, directory)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_source_archive_is_repeatable_and_has_no_account_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            script = base / 'script.sh'
            script.write_text('#!/bin/sh\nexit 0\n')
            script.chmod(0o755)
            for name in ('a.tar.gz', 'b.tar.gz'):
                source_archive(base / name, [(script, 'source/script.sh')])
            self.assertEqual(digest(base / 'a.tar.gz'), digest(base / 'b.tar.gz'))
            with tarfile.open(base / 'a.tar.gz') as archive:
                member = archive.getmembers()[0]
                self.assertEqual((member.uid, member.gid, member.uname, member.gname), (0, 0, '', ''))
                self.assertEqual(member.mode, 0o755)
                self.assertEqual(archive.extractfile(member).read(), script.read_bytes())

    def test_source_fingerprint_changes_on_content_but_not_cache_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('LICENSE', 'NOTICE', 'Package.swift'):
                (root / name).write_text('original')
            for name in ('Sources', 'Integrations', 'Resources', 'scripts'):
                (root / name).mkdir()
            before = build_fingerprint(root)
            (root / 'scripts/__pycache__').mkdir()
            (root / 'scripts/__pycache__/cache.pyc').write_bytes(b'cache')
            self.assertEqual(before, build_fingerprint(root))
            (root / 'Sources/file.swift').write_text('changed input')
            self.assertNotEqual(before, build_fingerprint(root))

    def test_packaging_rejects_wrong_architecture_and_changed_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Amoss.app'
            current_version, build = version()
            info = {'CFBundleShortVersionString': current_version, 'CFBundleVersion': build}
            for name in ('Contents/Info.plist', 'Contents/Helpers/Amoss Mirror.app/Contents/Info.plist'):
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps(info))
            resources = app / 'Contents/Resources'
            resources.mkdir()
            command = [sys.executable, str(ROOT / 'scripts/release-metadata.py')]
            subprocess.run(command + ['record', str(app), 'arm64'], check=True, capture_output=True)
            subprocess.run(command + ['check', str(app), 'arm64'], check=True, capture_output=True)
            result = subprocess.run(command + ['check', str(app), 'x86_64'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            metadata_path = resources / 'build-manifest.json'
            metadata = json.loads(metadata_path.read_text())
            metadata['source_sha256'] = 'stale-source'
            metadata_path.write_text(json.dumps(metadata))
            result = subprocess.run(command + ['check', str(app), 'arm64'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_packaging_rejects_old_application_version(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'Amoss.app'
            for name in ('Contents/Info.plist', 'Contents/Helpers/Amoss Mirror.app/Contents/Info.plist'):
                path = app / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.0.0', 'CFBundleVersion': '0'}))
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/release-metadata.py'), 'check', str(app), 'arm64'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b'version does not match', result.stderr)
