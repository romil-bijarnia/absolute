#!/usr/bin/env python3
"""Read-only inventory of declared macOS system roots, without following symlinks."""
import argparse
import collections
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import sys
from xml.parsers.expat import ExpatError

PROJECT = Path(__file__).resolve().parent.parent
ROOTS = [
    "/System/Applications", "/System/Library", "/System/DriverKit",
    "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
    "/usr/standalone", "/bin", "/sbin", "/Library/Apple/System/Library",
]
BUNDLE_KINDS = {
    ".app": "application", ".framework": "framework", ".kext": "kernel-extension",
    ".dext": "driver-extension", ".xpc": "xpc-service", ".appex": "app-extension",
    ".bundle": "bundle", ".plugin": "plugin", ".prefPane": "preference-pane",
    ".saver": "screen-saver", ".qlgenerator": "quicklook-generator",
    ".component": "component", ".systemextension": "system-extension",
}
CPU_NAMES = {7: "i386", 0x1000007: "x86_64", 12: "arm", 0x100000C: "arm64"}
FILE_TYPES = {
    1: "object", 2: "execute", 3: "fvmlib", 4: "core", 5: "preload",
    6: "dylib", 7: "dylinker", 8: "bundle", 9: "dylib-stub", 10: "dsym",
    11: "kext-bundle", 12: "fileset", 13: "gpu-execute", 14: "gpu-dylib",
}
THIN = {
    b"\xfe\xed\xfa\xce": (">", 28), b"\xce\xfa\xed\xfe": ("<", 28),
    b"\xfe\xed\xfa\xcf": (">", 32), b"\xcf\xfa\xed\xfe": ("<", 32),
}
FAT = {
    b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
    b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True),
}


def encoded(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def cpu_name(cpu, subtype):
    if cpu == 0x100000C and (subtype & 0xFFFFFF) == 2:
        return "arm64e"
    return CPU_NAMES.get(cpu, hex(cpu))


def macho_header(source, offset, size):
    """Validate enough structure to distinguish a Mach-O from a magic collision."""
    if offset < 0 or size < 28:
        return None
    source.seek(offset)
    header = source.read(min(size, 32))
    shape = THIN.get(header[:4])
    if not shape or len(header) < shape[1]:
        return None
    endian, header_size = shape
    cpu, subtype, kind, ncmds, sizeofcmds, flags = struct.unpack(
        endian + "IIIIII", header[4:28]
    )
    if sizeofcmds > size - header_size or ncmds > sizeofcmds // 8:
        return None
    return {
        "architecture": cpu_name(cpu, subtype), "cpu_type": cpu,
        "cpu_subtype": subtype, "file_type": FILE_TYPES.get(kind, str(kind)),
        "load_command_count": ncmds, "load_command_bytes": sizeofcmds,
        "flags": flags, "slice_offset": offset, "slice_bytes": size,
    }


def identify_macho(path, size):
    with open(path, "rb") as source:
        magic = source.read(8)
        if magic[:4] in THIN:
            item = macho_header(source, 0, size)
            return {"container": "thin", "slices": [item]} if item else None
        shape = FAT.get(magic[:4])
        if not shape or len(magic) != 8:
            return None
        endian, wide = shape
        count = struct.unpack(endian + "I", magic[4:])[0]
        width = 32 if wide else 20
        if not 0 < count <= 64 or 8 + count * width > size:
            return None
        slices = []
        for index in range(count):
            source.seek(8 + index * width)
            fields = struct.unpack(endian + ("IIQQII" if wide else "IIIII"), source.read(width))
            cpu, subtype, offset, length = fields[:4]
            if offset < 8 + count * width or length > size - offset:
                return None
            item = macho_header(source, offset, length)
            if not item or item["cpu_type"] != cpu or item["cpu_subtype"] != subtype:
                return None
            slices.append(item)
        return {"container": "universal64" if wide else "universal", "slices": slices}


def read_plist(path):
    if path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("plist exceeds the 16 MiB inventory bound")
    data = path.read_bytes()
    try:
        value = plistlib.loads(data)
    except (ValueError, plistlib.InvalidFileException, ExpatError) as original:
        if sys.platform != "darwin":
            raise ValueError(str(original)) from original
        normalized = subprocess.run(
            ["/usr/bin/plutil", "-convert", "binary1", "-o", "-", str(path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5,
        )
        if normalized.returncode or len(normalized.stdout) > 16 * 1024 * 1024:
            raise ValueError(str(original)) from original
        value = plistlib.loads(normalized.stdout)
    if not isinstance(value, dict):
        raise ValueError("top-level plist is not a dictionary")
    return value, hashlib.sha256(data).hexdigest()


def describe_bundle(path, kind, errors):
    record = {"path": str(path), "kind": kind}
    candidates = [
        path / "Contents/Info.plist", path / "Resources/Info.plist",
        path / "Versions/Current/Resources/Info.plist", path / "Info.plist",
    ]
    for candidate in candidates:
        if not candidate.is_file():
            continue
        try:
            data, digest = read_plist(candidate)
            record.update({
                "info_plist": str(candidate), "info_plist_sha256": digest,
                "identifier": data.get("CFBundleIdentifier"),
                "executable": data.get("CFBundleExecutable"),
                "version": str(data.get("CFBundleVersion", "")),
            })
            personalities = data.get("IOKitPersonalities", {})
            if isinstance(personalities, dict):
                record["driver_personalities"] = [
                    {"name": name, **{
                        key: body[key] for key in [
                            "IOClass", "IOProviderClass", "IOUserClass",
                            "IOUserServerName", "IONameMatch", "IOMatchCategory",
                        ] if key in body and isinstance(body[key], (str, int, bool, list))
                    }}
                    for name, body in sorted(personalities.items())
                    if isinstance(body, dict)
                ]
            return record
        except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, subprocess.TimeoutExpired) as error:
            errors.append({"path": str(candidate), "operation": "bundle-plist", "error": str(error)})
    return record


def describe_launch_job(path):
    value, digest = read_plist(path)
    services = value.get("MachServices", {})
    arguments = value.get("ProgramArguments", [])
    program = value.get("Program") or (arguments[0] if arguments else None)
    return {
        "path": str(path), "sha256": digest, "label": value.get("Label"),
        "program": program, "program_arguments": arguments,
        "mach_services": sorted(services) if isinstance(services, dict) else [],
        "socket_names": sorted(value.get("Sockets", {})),
        "run_at_load": value.get("RunAtLoad"),
        "keep_alive": value.get("KeepAlive"),
        "disabled": value.get("Disabled"),
        "process_type": value.get("ProcessType"),
        "session_type": value.get("LimitLoadToSessionType"),
        "launch_events": sorted(value.get("LaunchEvents", {})),
    }


def capture(roots, directory):
    errors, bundles, binaries, jobs, root_reports = [], [], [], [], []
    architecture_counts = collections.Counter()
    kind_counts = collections.Counter()
    with (directory / "paths.jsonl").open("w", encoding="utf-8") as index:
        for root_name in roots:
            root = Path(root_name)
            counts = collections.Counter()
            byte_count = 0
            if not root.is_dir():
                root_reports.append({"root": root_name, "present": False, "counts": {}})
                continue
            pending = [root]
            while pending:
                parent = pending.pop()
                try:
                    with os.scandir(parent) as scan:
                        entries = sorted(scan, key=lambda entry: entry.name)
                except OSError as error:
                    errors.append({"path": str(parent), "operation": "scan", "error": str(error)})
                    continue
                for entry in entries:
                    try:
                        info = entry.stat(follow_symlinks=False)
                        record = {"path": entry.path, "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode)}
                        if stat.S_ISLNK(info.st_mode):
                            record.update(kind="symlink", target=os.readlink(entry.path))
                        elif stat.S_ISDIR(info.st_mode):
                            record["kind"] = "directory"
                            pending.append(Path(entry.path))
                            bundle_kind = BUNDLE_KINDS.get(Path(entry.name).suffix)
                            if bundle_kind:
                                bundles.append(describe_bundle(Path(entry.path), bundle_kind, errors))
                        elif stat.S_ISREG(info.st_mode):
                            record["kind"] = "file"
                            byte_count += info.st_size
                            try:
                                native = identify_macho(entry.path, info.st_size)
                                if native:
                                    binaries.append({"path": entry.path, "bytes": info.st_size, **native})
                                    record["mach_o"] = True
                                    for item in native["slices"]:
                                        architecture_counts[item["architecture"]] += 1
                                        kind_counts[item["file_type"]] += 1
                            except OSError as error:
                                errors.append({"path": entry.path, "operation": "read-header", "error": str(error)})
                            if parent in [
                                Path("/System/Library/LaunchAgents"),
                                Path("/System/Library/LaunchDaemons"),
                            ] and entry.name.endswith(".plist"):
                                try:
                                    jobs.append(describe_launch_job(Path(entry.path)))
                                except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, TypeError, subprocess.TimeoutExpired) as error:
                                    errors.append({"path": entry.path, "operation": "launch-plist", "error": str(error)})
                        else:
                            record["kind"] = "other"
                        counts[record["kind"]] += 1
                        index.write(encoded(record) + "\n")
                    except OSError as error:
                        errors.append({"path": entry.path, "operation": "stat", "error": str(error)})
            root_reports.append({"root": root_name, "present": True, "counts": dict(counts), "file_bytes": byte_count})
            print(f"{root_name}: {counts['file']} files, {counts['symlink']} symlinks", flush=True)
    for name, value in [
        ("bundles.json", bundles), ("binaries.json", binaries),
        ("launch-jobs.json", jobs), ("errors.json", errors),
    ]:
        (directory / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    return {
        "roots": root_reports,
        "file_count": sum(item["counts"].get("file", 0) for item in root_reports),
        "path_count": sum(sum(item["counts"].values()) for item in root_reports),
        "bundle_count": len(bundles),
        "bundle_kinds": dict(sorted(collections.Counter(item["kind"] for item in bundles).items())),
        "native_file_count": len(binaries),
        "native_slice_architectures": dict(sorted(architecture_counts.items())),
        "native_slice_file_types": dict(sorted(kind_counts.items())),
        "launch_job_count": len(jobs),
        "declared_mach_service_count": sum(len(item["mach_services"]) for item in jobs),
        "driver_personality_count": sum(len(item.get("driver_personalities", [])) for item in bundles),
        "error_count": len(errors),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", action="append", help="Override roots for a bounded capture; repeatable.")
    parser.add_argument("--output", type=Path, default=PROJECT / "research/local/system-catalog")
    args = parser.parse_args()
    if sys.platform != "darwin" and not args.root:
        parser.error("default system inventory must run on macOS")
    roots = args.root or ROOTS
    roots = sorted({str(Path(root).resolve()) for root in roots})
    for index, root in enumerate(roots):
        if any(Path(root).is_relative_to(Path(parent)) for parent in roots[:index]):
            parser.error("inventory roots must not overlap")
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    destination = args.output / stamp
    destination.mkdir(parents=True, exist_ok=False)
    host = {}
    if sys.platform == "darwin":
        for field, option in [("product", "-productName"), ("version", "-productVersion"), ("build", "-buildVersion")]:
            host[field] = subprocess.check_output(["/usr/bin/sw_vers", option], text=True).strip()
    summary = capture(roots, destination)
    manifest = {
        "schema": 1, "operation": "inventory-system-roots", "evidence_type": "static-observation",
        "started": started, "finished": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": host, "script_sha256": sha256_file(__file__), **summary,
        "limitations": [
            "This inventories selected readable filesystem roots, not all macOS code or running behavior.",
            "Directory symlinks are recorded and not traversed; explicit bundle metadata paths can resolve symlinks.",
            "Shared-cache images, compressed kernel collections, encrypted payloads and chip ROM require separate analysis.",
            "Native header detection is structural inventory, not disassembly or a complete Mach-O validation.",
            "Bundle roles and driver match declarations do not prove runtime activation.",
            "Mach service names are plist declarations, not observed live endpoints or decoded protocols.",
            "File byte totals count path occurrences, not unique physical storage or unique code.",
        ],
        "records": [
            {"file": path.name, "bytes": path.stat().st_size, "sha256": sha256_file(path)}
            for path in sorted(destination.iterdir()) if path.is_file()
        ],
    }
    manifest["evidence_id"] = "absolute-inventory-sha256:" + hashlib.sha256(encoded(manifest).encode()).hexdigest()
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "latest.json").write_text(json.dumps({"directory": str(destination), "evidence_id": manifest["evidence_id"]}, indent=2) + "\n")
    public = {key: value for key, value in manifest.items() if key not in {"records", "started", "finished"}}
    public["local_capture"] = str(destination.relative_to(PROJECT)) if destination.is_relative_to(PROJECT) else None
    if not args.root:
        (PROJECT / "research/system-inventory.json").write_text(json.dumps(public, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"capture": str(destination), **{key: summary[key] for key in [
        "file_count", "bundle_count", "native_file_count", "launch_job_count",
        "declared_mach_service_count", "driver_personality_count", "error_count",
    ]}}, indent=2))


if __name__ == "__main__":
    main()
