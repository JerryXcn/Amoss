"""Shared download, provenance and source-archive helpers. Python 3.12+."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent


def dependencies():
    return json.loads((ROOT / "scripts/dependencies.json").read_text())


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify(path, expected):
    if digest(path) != expected:
        raise RuntimeError(f"SHA-256 mismatch: {Path(path).name}; refusing to use this file")


def download(item, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / item["archive"]
    if target.exists():
        verify(target, item["sha256"])
        return target
    partial = target.with_name(target.name + ".partial")
    try:
        subprocess.run(["curl", "--fail", "--location", "--retry", "2", "--connect-timeout", "30",
                        "--proto", "=https", "--proto-redir", "=https", "--silent", "--show-error",
                        "--output", str(partial), item["source"]], check=True)
        verify(partial, item["sha256"])
        partial.replace(target)
    finally:
        partial.unlink(missing_ok=True)
    return target


def version(root=ROOT):
    info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    return info["CFBundleShortVersionString"], info["CFBundleVersion"]


def files_under(path):
    return sorted(p for p in path.rglob("*") if p.is_file()
                  and not any(part in {"__pycache__", ".DS_Store", "xcuserdata"} for part in p.parts)
                  and p.suffix not in {".pyc", ".xcuserstate"})


def build_fingerprint(root=ROOT):
    paths = [root / name for name in ("LICENSE", "NOTICE", "Package.swift")]
    for name in ("Sources", "Integrations", "Resources", "scripts"):
        paths.extend(files_under(root / name))
    hashes = {str(p.relative_to(root)): digest(p) for p in sorted(paths)}
    return hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()


def source_archive(destination, entries):
    """Stable metadata and ordering; no local account, timestamps or gzip filename."""
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))

    def normalize(info):
        if any(p in {".DS_Store", "__pycache__", "xcuserdata"} for p in Path(info.name).parts):
            return None
        if info.issym() or info.islnk():
            raise RuntimeError(f"Unexpected link in source package: {info.name}")
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = epoch
        info.pax_headers = {}
        info.mode = 0o755 if info.isdir() or info.mode & 0o111 else 0o644
        return info

    with Path(destination).open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for source, name in sorted(entries, key=lambda item: item[1]):
                    archive.add(source, arcname=name, filter=normalize)
