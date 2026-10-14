#!/usr/bin/env python3
"""Package the native Fedora sources with a verified, explicit file manifest."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import re
import subprocess
import tarfile
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parent.parent
FILES = (
    "Package.swift",
    "LICENSE",
    "script/install_fedora.sh",
    "script/check_fedora.sh",
    "script/check_core.sh",
    "script/package_fedora.py",
)
DIRECTORIES = ("Sources", "Tests", "linux/Sources", "linux/fedora")
MAX_FILE_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_paths() -> list[Path]:
    paths = {ROOT / name for name in (*FILES, "linux/Package.swift")}
    for name in DIRECTORIES:
        directory = ROOT / name
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError(f"Missing source directory: {name}")
        for path in directory.rglob("*"):
            if path.is_symlink():
                raise ValueError(f"Package sources must not contain symlinks: {path.relative_to(ROOT)}")
            if path.is_file() and not any(part.startswith(".") or part == "__pycache__"
                                          for part in path.relative_to(directory).parts):
                paths.add(path)
    for path in paths:
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing regular source file: {path.relative_to(ROOT)}")
    return sorted(paths)


def git_revision() -> str | None:
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else None


def add_file(archive: tarfile.TarFile, name: str, data: bytes, mode: int) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = mode
    info.mtime = 0
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    archive.addfile(info, io.BytesIO(data))


def verify(path: Path) -> dict:
    contents = {}
    total = 0
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            if (not member.isfile() or name.is_absolute() or ".." in name.parts
                    or len(name.parts) < 2 or member.name in contents):
                raise ValueError(f"Unexpected archive entry: {member.name}")
            if member.size > MAX_FILE_BYTES:
                raise ValueError(f"Source file exceeds package limit: {member.name}")
            total += member.size
            if total > MAX_ARCHIVE_BYTES:
                raise ValueError("Source archive exceeds package limit")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"Unreadable archive entry: {member.name}")
            contents[member.name] = (stream.read(), member.mode)
    manifests = [name for name in contents if name.endswith("/ABSOLUTE-RELEASE.json")]
    if len(manifests) != 1:
        raise ValueError("Expected one release manifest")
    manifest_name = manifests[0]
    manifest = json.loads(contents[manifest_name][0])
    prefix = manifest_name.removesuffix("/ABSOLUTE-RELEASE.json")
    expected = {f"{prefix}/{name}" for name in manifest["files"]} | {manifest_name}
    if set(contents) != expected:
        raise ValueError("Archive membership differs from release manifest")
    for name, record in manifest["files"].items():
        data, mode = contents[f"{prefix}/{name}"]
        if (digest(data) != record["sha256"] or len(data) != record["bytes"]
                or mode != record["mode"]):
            raise ValueError(f"Manifest mismatch: {name}")
    return {"archive": str(path), "sha256": digest(path.read_bytes()),
            "source_files": len(manifest["files"]), "source_bytes": total,
            "release_status": manifest["release_status"], "verified": True}


def package(version: str, destination: Path) -> dict:
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version):
        raise ValueError("Use a version such as 0.4.0-dev")
    payload = {}
    for path in source_paths():
        data = path.read_bytes()
        if len(data) > MAX_FILE_BYTES:
            raise ValueError(f"Source file exceeds package limit: {path.relative_to(ROOT)}")
        payload[path.relative_to(ROOT).as_posix()] = (data, 0o755 if path.stat().st_mode & 0o111 else 0o644)
    manifest = {
        "schema": 1,
        "name": "Absolute Fedora",
        "version": version,
        "artifact": "native installation source package",
        "target": "Existing Fedora Asahi KDE installation on the physical Apple Silicon Mac",
        "release_status": "native-validation-pending",
        "source_commit": git_revision(),
        "source_identity": "The file hashes identify the packaged working tree, including uncommitted changes.",
        "validation_boundary": "Archive integrity is verified here. Native build, desktop rendering and hardware acceptance must run in Fedora.",
        "files": {name: {"sha256": digest(data), "bytes": len(data), "mode": mode}
                  for name, (data, mode) in payload.items()},
    }
    prefix = f"absolute-fedora-{version}"
    destination.mkdir(parents=True, exist_ok=True)
    archive_path = destination / f"{prefix}-source.tar.gz"
    temporary = destination / f".{archive_path.name}.tmp"
    try:
        with temporary.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                    for name, (data, mode) in payload.items():
                        add_file(archive, f"{prefix}/{name}", data, mode)
                    add_file(archive, f"{prefix}/ABSOLUTE-RELEASE.json",
                             (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode(), 0o644)
        result = verify(temporary)
        temporary.replace(archive_path)
    finally:
        temporary.unlink(missing_ok=True)
    result["archive"] = str(archive_path)
    (destination / f"{archive_path.name}.sha256").write_text(
        result["sha256"] + "  " + archive_path.name + "\n")
    (destination / "ABSOLUTE-RELEASE.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="0.4.0-dev")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/fedora")
    parser.add_argument("--verify", type=Path, help="Verify an existing source package without extracting it")
    args = parser.parse_args()
    try:
        result = verify(args.verify) if args.verify else package(args.version, args.output)
    except (OSError, ValueError, KeyError, tarfile.TarError) as error:
        parser.exit(1, f"package_fedora: {error}\n")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
