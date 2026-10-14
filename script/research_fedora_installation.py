#!/usr/bin/env python3
"""Inspect installed Fedora system metadata without mounting or writing its disk.

Install dissect.btrfs==1.10 into a local research virtual environment, then run:
  sudo -n research/local/fedora-inspect-venv/bin/python -B \
    script/research_fedora_installation.py --device /dev/disk0s6 \
    > research/local/fedora-installation-findings.json

Only system metadata is read. No guest executables are run. The device is opened
with mode 'rb'; the RPM database is queried from a copy in memory. Output goes
to stdout so the caller chooses a local evidence destination.
"""

from __future__ import annotations

import argparse
from collections import deque
import datetime
import hashlib
import importlib.metadata
import json
from pathlib import Path
import re
import sqlite3
import struct

from dissect.btrfs import Btrfs


RPM_DATABASE = "/usr/lib/sysimage/rpm/rpmdb.sqlite"
MAX_DATABASE_BYTES = 256 * 1024 * 1024
MAX_TEXT_BYTES = 128 * 1024
TAGS = {
    1000: "name", 1001: "version", 1002: "release", 1003: "epoch",
    1014: "license", 1022: "architecture", 1044: "source_rpm",
}
PACKAGE_PATTERN = re.compile(
    r"^(?:asahi(?:-|$)|kernel-16k(?:-|$)|m1n1$|uboot-asahi$|"
    r"plasma-(?:desktop|workspace|integration|breeze|systemsettings|login)(?:-|$)|"
    r"kwin(?:-|$)|kde-settings(?:-|$)|kcm-plasmalogin$|sddm(?:-|$)|"
    r"breeze-(?:gtk|icon|cursor)(?:-|$)|qt6-qtbase(?:-|$)|"
    r"mesa-(?:dri-drivers|vulkan-drivers)$|gtk4(?:-|$)|glib2(?:-|$)|"
    r"swift(?:-|$)|clang(?:-|$)|gcc(?:-|$)|cmake$|make$|ninja-build$|"
    r"pkgconf(?:-|$)|git(?:-|$)|firefox$|dolphin$|konsole$)"
)
BUILD_PACKAGES = (
    "swift-lang", "swift", "gtk4-devel", "glib2-devel", "clang", "gcc",
    "gcc-c++", "cmake", "make", "ninja-build", "pkgconf-pkg-config", "git-core",
)
SYSTEM_TEXT_FILES = (
    "/usr/lib/os-release",
    "/etc/fedora-release",
    "/usr/share/wayland-sessions/plasma.desktop",
    "/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/metadata.json",
    "/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/contents/defaults",
    "/usr/share/plasma/look-and-feel/org.fedoraproject.fedora.desktop/contents/layouts/org.kde.plasma.desktop-layout.js",
    "/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/defaults",
    "/usr/share/plasma/shells/org.kde.plasma.desktop/contents/defaults",
    "/usr/lib/systemd/system/plasmalogin.service",
    "/etc/plasmalogin.conf",
    "/etc/xdg/kdeglobals",
    "/etc/xdg/kwinrc",
    "/usr/share/licenses/kde-settings/COPYING",
)
SYSTEM_DIRECTORIES = (
    "/usr/share/wayland-sessions", "/usr/share/xsessions",
    "/usr/share/plasma/look-and-feel", "/usr/share/plasma/desktoptheme",
    "/usr/share/licenses/plasma-desktop/LICENSES",
    "/usr/share/licenses/plasma-workspace-common/LICENSES",
    "/usr/share/licenses/plasma-breeze",
)
TOOL_FILES = (
    "/usr/bin/swift", "/usr/local/bin/swift", "/opt/swift/usr/bin/swift",
    "/usr/bin/clang", "/usr/bin/gcc", "/usr/bin/make", "/usr/bin/cmake",
    "/usr/lib64/pkgconfig/gtk4.pc", "/usr/lib64/pkgconfig/glib-2.0.pc",
    "/usr/bin/plasma-apply-lookandfeel", "/usr/bin/kreadconfig6",
    "/usr/bin/kwriteconfig6", "/usr/bin/qdbus6", "/usr/lib64/qt6/bin/qdbus",
)
DESKTOP_IDS = (
    "org.mozilla.firefox.desktop", "org.kde.dolphin.desktop",
    "org.kde.konsole.desktop", "systemsettings.desktop", "kdesystemsettings.desktop",
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sanitize(text: str) -> str:
    text = re.sub(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", "<UUID>", text)
    return re.sub(r"(?<![A-Za-z0-9])[0-9a-fA-F]{32}(?![A-Za-z0-9])", "<ID>", text)


class SystemFiles:
    """Resolve selected system paths, including relative symlinks, in one subvolume."""

    def __init__(self, root):
        self.root = root

    def get(self, path: str):
        pending = deque(path.strip("/").split("/"))
        resolved: list[str] = []
        links = 0
        node = self.root.root
        while pending:
            part = pending.popleft()
            if part in ("", "."):
                continue
            if part == "..":
                if resolved:
                    resolved.pop()
                continue
            candidate = "/" + "/".join(resolved + [part])
            if candidate == "/home" or candidate == "/root":
                raise ValueError("System metadata must not resolve into a user home")
            node = self.root.get(candidate)
            if node.is_symlink():
                links += 1
                if links > 16:
                    raise ValueError("Symlink depth limit exceeded")
                target = node.link
                if target.startswith("/"):
                    resolved = []
                pending.extendleft(reversed(target.split("/")))
            else:
                resolved.append(part)
        return node

    def read(self, path: str, limit: int = MAX_TEXT_BYTES) -> bytes:
        node = self.get(path)
        if node.is_dir() or node.size > limit:
            raise ValueError(f"Unexpected file type or size at {path}")
        data = node.open().read(limit + 1)
        if len(data) != node.size:
            raise ValueError(f"Incomplete bounded file read at {path}")
        return data

    def metadata(self, path: str) -> dict:
        try:
            node = self.get(path)
            return {"path": path, "present": True, "bytes": node.size}
        except FileNotFoundError:
            return {"path": path, "present": False}

    def text(self, path: str) -> dict:
        result = self.metadata(path)
        if result["present"]:
            data = self.read(path)
            result.update(sha256=digest(data), content=sanitize(data.decode("utf-8")))
        return result

    def directory(self, path: str) -> dict:
        try:
            entries = []
            for name, node in self.get(path).iterdir():
                if name in (".", ".."):
                    continue
                if len(entries) >= 512:
                    raise ValueError(f"Directory entry limit exceeded at {path}")
                entries.append({"name": name, "bytes": node.size,
                                "type": "directory" if node.is_dir() else "symlink" if node.is_symlink() else "file"})
            return {"path": path, "present": True, "entries": entries}
        except FileNotFoundError:
            return {"path": path, "present": False}


def rpm_header(blob: bytes) -> dict:
    """Read bounded descriptive tags from an installed RPM header (without its magic)."""
    if len(blob) < 8:
        raise ValueError("Truncated RPM header")
    count, size = struct.unpack_from(">II", blob)
    base = 8 + 16 * count
    if count > 65536 or base + size != len(blob):
        raise ValueError("Invalid RPM header index/data bounds")
    result = {}
    for index in range(count):
        tag, kind, offset, length = struct.unpack_from(">IIiI", blob, 8 + 16 * index)
        if tag not in TAGS:
            continue
        if not 0 <= offset < size:
            raise ValueError("RPM tag points outside its data store")
        start = base + offset
        if kind == 6 and length == 1:
            end = blob.find(b"\0", start)
            if end < start:
                raise ValueError("Unterminated RPM string")
            result[TAGS[tag]] = blob[start:end].decode("utf-8")
        elif kind == 4 and length == 1 and start + 4 <= len(blob):
            result[TAGS[tag]] = struct.unpack_from(">I", blob, start)[0]
        else:
            raise ValueError("Unexpected descriptive RPM tag type")
    # Installed public-key records use RPM headers but have no architecture tag.
    for required in ("name", "version", "release"):
        if required not in result:
            raise ValueError(f"RPM header lacks {required}")
    return result


def packages(files: SystemFiles) -> dict:
    wal = files.metadata(RPM_DATABASE + "-wal")
    if wal.get("bytes", 0):
        raise ValueError("RPM WAL is nonempty; refusing an incomplete package snapshot")
    original = files.read(RPM_DATABASE, MAX_DATABASE_BYTES)
    if not original.startswith(b"SQLite format 3\0"):
        raise ValueError("Unexpected RPM database format")
    # SQLite documents this adjustment for deserialize() of a WAL-mode database.
    # It is applied only to a copy in memory, after requiring an absent/empty WAL.
    memory_copy = original[:18] + b"\x01\x01" + original[20:]
    database = sqlite3.connect(":memory:")
    try:
        database.deserialize(memory_copy)
        database.execute("PRAGMA query_only=ON")
        integrity = database.execute("PRAGMA quick_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError("RPM SQLite quick_check failed")
        total = database.execute("SELECT count(*) FROM Packages").fetchone()[0]
        rows = database.execute("SELECT Name.key, Packages.blob FROM Name JOIN Packages USING(hnum)")
        selected, names, parsed, without_architecture = [], set(), 0, 0
        for name, blob in rows:
            item = rpm_header(blob)
            if item["name"] != name:
                raise ValueError("RPM Name index does not match its package header")
            parsed += 1
            without_architecture += "architecture" not in item
            names.add(name)
            if PACKAGE_PATTERN.search(name):
                selected.append(item)
        if parsed != total:
            raise ValueError("RPM package/header index coverage differs")
        return {
            "path": RPM_DATABASE, "bytes": len(original), "sha256": digest(original),
            "wal_bytes": wal.get("bytes", 0), "sqlite_quick_check": integrity,
            "header_count": total, "validated_headers": parsed,
            "headers_without_architecture": without_architecture,
            "selected": sorted(selected, key=lambda item: item["name"]),
            "build_package_presence": {name: name in names for name in BUILD_PACKAGES},
            "interpretation": "Static installed-package records; package binaries have not been executed or verified against RPM digests.",
        }
    finally:
        database.close()


def desktop_entries(files: SystemFiles) -> list[dict]:
    results = []
    for desktop_id in DESKTOP_IDS:
        path = "/usr/share/applications/" + desktop_id
        result = files.metadata(path)
        if result["present"]:
            data = files.read(path)
            fields = {}
            section = ""
            for line in data.decode("utf-8").splitlines():
                if line.startswith("["):
                    section = line
                elif section == "[Desktop Entry]" and "=" in line:
                    key, value = line.split("=", 1)
                    if key in ("Name", "Exec", "TryExec", "Icon", "NoDisplay"):
                        fields[key] = value
            result.update(sha256=digest(data), fields=fields)
        results.append(result)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="/dev/disk0s6", help="Btrfs partition or image; opened only in rb mode")
    args = parser.parse_args()
    with open(args.device, "rb") as device:
        filesystem = Btrfs(device)
        root = filesystem.find_subvolume("root")
        if root is None:
            raise ValueError("Expected system subvolume named root was not found")
        files = SystemFiles(root)
        report = {
            "schema": 1,
            "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "evidence_type": "static-installed-system-metadata",
            "device": str(Path(args.device)), "subvolume": "root",
            "filesystem": {"type": "Btrfs", "sector_bytes": filesystem.sector_size,
                           "node_bytes": filesystem.node_size},
            "tools": {name: importlib.metadata.version(name) for name in
                      ("dissect.btrfs", "dissect.cstruct", "dissect.util")},
            "script_sha256": digest(Path(__file__).read_bytes()),
            "system_files": [files.text(path) for path in SYSTEM_TEXT_FILES],
            "system_directories": [files.directory(path) for path in SYSTEM_DIRECTORIES],
            "tool_files": [files.metadata(path) for path in TOOL_FILES],
            "desktop_entries": desktop_entries(files),
            "rpm": packages(files),
            "display_manager_link": root.get("/etc/systemd/system/display-manager.service").link,
            "references": [
                "https://github.com/fox-it/dissect.btrfs",
                "https://docs.dissect.tools/en/stable/api/dissect/btrfs/btrfs/index.html",
                "https://rpm.org/docs/latest/manual/tags",
                "https://rpm.org/docs/4.20.x/manual/format_header.html",
                "https://www.sqlite.org/c3ref/deserialize.html",
            ],
            "limits": [
                "Input opened rb; no mounts, repairs, partition changes, or guest executables.",
                "No user-home files, private keys, credentials, browser profiles, or personal documents were inspected.",
                "RPM SQLite header bytes 18 and 19 adjusted only in the in-memory copy; the original device and database bytes were unchanged.",
                "Package inventory and configured system defaults do not establish current runtime behavior, hardware support, or active user settings.",
                "Missing build packages and checked system paths do not rule out a separately installed toolchain in an uninspected location.",
                "This is not a filesystem integrity check or package signature verification.",
            ],
        }
    canonical = json.dumps(report, sort_keys=True, separators=(",", ":")).encode()
    report["evidence_id"] = "absolute-fedora-installation-" + digest(canonical)[:20]
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
