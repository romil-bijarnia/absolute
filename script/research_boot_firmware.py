#!/usr/bin/env python3
"""Read installed boot artifacts; never flash, execute, or change system files.

Public output includes static product/build metadata and image payload identities.
Personalized IMG4 manifests, local policies, keys, live device trees, and volume
identifiers are deliberately outside the capture boundary.
"""

import argparse
from collections import Counter
import ctypes
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import subprocess


PROJECT = Path(__file__).resolve().parents[1]
LOCAL = PROJECT / "research/local/boot-firmware"
MAX_PAYLOAD = 256 * 1024 * 1024
VOLUME_ID = re.compile(r"^[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$")
HEX_COMPONENT = re.compile(r"^[0-9A-Fa-f]{64,128}$")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def safe_path(path):
    return "/".join("<volume>" if VOLUME_ID.fullmatch(part) else
                    "<boot-object-set>" if HEX_COMPONENT.fullmatch(part) else part
                    for part in str(path).split("/"))


def evidence_id(value, kind):
    return "absolute-boot-" + kind + "-" + digest(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode())[:20]


def tlv(stream, offset, boundary):
    """Read one bounded DER TLV header without reading its value."""
    if offset + 2 > boundary:
        raise ValueError("truncated DER header")
    stream.seek(offset)
    prefix = stream.read(2)
    tag, size = prefix
    if tag & 0x1f == 0x1f:
        raise ValueError("high-tag-number DER is outside selected header parser")
    header = 2
    if size & 0x80:
        count = size & 0x7f
        if count < 1 or count > 8 or offset + 2 + count > boundary:
            raise ValueError("invalid DER length")
        length_bytes = stream.read(count)
        if len(length_bytes) != count or length_bytes[0] == 0:
            raise ValueError("invalid DER length encoding")
        size = int.from_bytes(length_bytes, "big")
        header += count
    start = offset + header
    if start + size > boundary:
        raise ValueError("DER value extends beyond parent")
    return tag, start, size, start + size


def image_payload(path):
    """Read IM4P's four public fields; skip every later manifest/keybag field."""
    with path.open("rb") as stream:
        limit = path.stat().st_size
        tag, body, _, end = tlv(stream, 0, limit)
        if tag != 0x30:
            raise ValueError("not a DER sequence")
        tag, first, size, next_field = tlv(stream, body, end)
        stream.seek(first)
        name = stream.read(size) if size <= 8 else b""
        container = name.decode("ascii", "replace")
        if name == b"IMG4":
            tag, body, _, end = tlv(stream, next_field, end)
            if tag != 0x30:
                raise ValueError("IMG4 payload is not a sequence")
        elif name != b"IM4P":
            raise ValueError("not IM4P or IMG4")
        values = []
        cursor = body
        for index in range(4):
            tag, start, size, cursor = tlv(stream, cursor, end)
            if index < 3:
                if tag != 0x16 or size > 4096:
                    raise ValueError("unexpected IM4P public field")
                stream.seek(start)
                values.append(stream.read(size).decode("ascii", "strict"))
            else:
                if tag != 0x04 or size > MAX_PAYLOAD:
                    raise ValueError("unsupported IM4P payload")
                stream.seek(start)
                payload = stream.read(size)
        if values[0] != "IM4P":
            raise ValueError("missing IM4P marker")
    metadata = {"container": container, "imageType": values[1],
                "description": values[2], "payloadOffset": start,
                "payloadBytes": len(payload), "payloadSha256": digest(payload),
                "compression": "lzfse" if payload[:4] in
                (b"bvx1", b"bvx2", b"bvxn", b"bvx-") else "unrecognized-or-none"}
    return metadata, payload


def decompress(payload):
    library = ctypes.CDLL("/usr/lib/libcompression.dylib")
    decode = library.compression_decode_buffer
    decode.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p,
                       ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    decode.restype = ctypes.c_size_t
    source = ctypes.create_string_buffer(payload)
    capacity = max(1024 * 1024, len(payload) * 4)
    while capacity <= MAX_PAYLOAD:
        target = ctypes.create_string_buffer(capacity)
        count = decode(target, capacity, source, len(payload), None, 0x801)
        if 0 < count < capacity:
            return target.raw[:count]
        capacity *= 2
    raise ValueError("LZFSE decode failed or exceeded 256 MiB limit")


def macho_layout(data):
    if data[:4] != b"\xcf\xfa\xed\xfe":
        return None
    if len(data) < 32:
        raise ValueError("truncated Mach-O header")
    _, cpu, subtype, kind, ncmds, cmdbytes, flags, _ = struct.unpack_from("<8I", data)
    if 32 + cmdbytes > len(data) or ncmds > 100000:
        raise ValueError("invalid Mach-O commands")
    out = {"format": "Mach-O 64-bit little-endian", "cpuType": hex(cpu),
           "cpuSubtype": hex(subtype), "architecture":
           "arm64e" if cpu == 0x100000c and subtype & 0xffffff == 2 else
           "arm64" if cpu == 0x100000c else "unknown",
           "fileType": kind, "loadCommands": ncmds, "flags": hex(flags),
           "segments": [], "filesetEntries": []}
    cursor = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or cursor + size > 32 + cmdbytes:
            raise ValueError("invalid Mach-O command size")
        if cmd == 0x19 and size >= 72:
            name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, _ = \
                struct.unpack_from("<16sQQQQIIII", data, cursor + 8)
            out["segments"].append({"name": name.split(b"\0")[0].decode("ascii", "replace"),
                                    "virtualAddress": hex(vmaddr), "virtualBytes": vmsize,
                                    "fileOffset": fileoff, "fileBytes": filesize,
                                    "sections": nsects, "initialProtection": initprot})
        elif cmd == 0x80000035 and size >= 32:
            vmaddr, fileoff, name_offset, _ = struct.unpack_from("<QQII", data, cursor + 8)
            if not 32 <= name_offset < size:
                raise ValueError("invalid fileset name offset")
            name = data[cursor + name_offset:cursor + size].split(b"\0")[0].decode("ascii", "replace")
            out["filesetEntries"].append({"identifier": name, "fileOffset": fileoff,
                                          "virtualAddress": hex(vmaddr)})
        elif cmd == 2 and size >= 24:
            _, nsyms, _, strsize = struct.unpack_from("<IIII", data, cursor + 8)
            out["symbolCount"] = nsyms
            out["stringTableBytes"] = strsize
        cursor += size
    return out


def device_tree(data):
    """Parse the shipped ADT template; export only public interface properties."""
    nodes, property_count = [], 0
    wanted = re.compile(r"(?:arm-io|agx|dcp|dart|aop|ane|ans|nvme|pmp|sio|sep|aic|uart|i2c|spi|gpio|pmgr|smc|usb|pcie|isp|ave|mtp|spmi)", re.I)

    def visit(offset, parent, depth):
        nonlocal property_count
        if depth > 64 or offset + 8 > len(data) or len(nodes) > 10000:
            raise ValueError("invalid ADT node boundary")
        props, children = struct.unpack_from("<II", data, offset)
        if props > 4096 or children > 4096:
            raise ValueError("invalid ADT node counts")
        offset += 8
        values = {}
        for _ in range(props):
            if offset + 36 > len(data):
                raise ValueError("truncated ADT property header")
            name = data[offset:offset + 32].split(b"\0")[0].decode("ascii", "replace")
            size = struct.unpack_from("<I", data, offset + 32)[0] & 0x7fffffff
            offset += 36
            if offset + size > len(data):
                raise ValueError("truncated ADT property value")
            values[name] = data[offset:offset + size]
            offset += (size + 3) & ~3
        property_count += props
        name = values.get("name", b"unnamed").split(b"\0")[0].decode("ascii", "replace")
        path = parent.rstrip("/") + "/" + name
        node = {"path": path, "propertyCount": props, "children": children}
        if wanted.search(name):
            node["properties"] = sorted(values)
            for key in ["compatible", "device_type"]:
                if key in values:
                    node[key] = [v.decode("ascii", "replace") for v in values[key].split(b"\0") if v]
            for key in ["reg", "interrupts"]:
                if key in values:
                    node[key + "Bytes"] = len(values[key])
        nodes.append(node)
        for _ in range(children):
            offset = visit(offset, path, depth + 1)
        return offset

    consumed = visit(0, "", 0)
    return {"nodes": len(nodes), "properties": property_count, "consumedBytes": consumed,
            "trailingBytes": len(data) - consumed, "interfaces":
            [node for node in nodes if "properties" in node],
            "scope": "Static shipped template; live boot properties and values were not captured."}


def regular_files(root):
    for base, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(name for name in dirs if not name.startswith(".") and
                         not (Path(base) / name).is_symlink())
        for name in sorted(names):
            path = Path(base) / name
            if not name.startswith(".") and path.is_file() and not path.is_symlink():
                yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rea", action="store_true", help="Also inspect three selected native files with the installed REA CLI")
    args = parser.parse_args()
    LOCAL.mkdir(parents=True, exist_ok=True)
    artifacts, manifests, errors = [], [], []
    decoded_for_rea = []
    for root in [Path("/System/Library/Kernels"), Path("/usr/standalone")]:
        for path in regular_files(root):
            item = {"path": safe_path(path), "scope": str(root), "bytes": path.stat().st_size,
                    "sha256": sha_file(path)}
            if root.name == "Kernels":
                item["layout"] = macho_layout(path.read_bytes())
            artifacts.append(item)
    for volume in sorted(Path("/System/Volumes/Preboot").iterdir()):
        if not VOLUME_ID.fullmatch(volume.name):
            continue
        for variant in ["restore", "restore-staged"]:
            base = volume / variant
            manifest = base / "BuildManifest.plist"
            if manifest.is_file():
                value = plistlib.loads(manifest.read_bytes())
                manifests.append({"path": safe_path(manifest), "sha256": sha_file(manifest),
                                  "productVersion": value.get("ProductVersion"),
                                  "productBuildVersion": value.get("ProductBuildVersion"),
                                  "identities": [{"deviceClass": item.get("Info", {}).get("DeviceClass"),
                                                  "variant": item.get("Info", {}).get("Variant"),
                                                  "components": {key: component.get("Info", {}).get("Path")
                                                                 for key, component in item.get("Manifest", {}).items()
                                                                 if isinstance(component, dict)}}
                                                 for item in value.get("BuildIdentities", [])]})
            selected = sorted((base / "Firmware").rglob("*.im4p")) if base.exists() else []
            selected += sorted(base.glob("kernelcache.*"))
            for path in selected:
                if path.is_symlink():
                    continue
                item = {"path": safe_path(path), "scope": "Preboot/" + variant,
                        "bytes": path.stat().st_size, "sha256": sha_file(path)}
                try:
                    metadata, payload = image_payload(path)
                    item["image"] = metadata
                    if metadata["compression"] == "lzfse":
                        decoded = decompress(payload)
                        item["decoded"] = {"bytes": len(decoded), "sha256": digest(decoded),
                                           "layout": macho_layout(decoded)}
                        if metadata["imageType"] == "dtre":
                            item["decoded"]["deviceTree"] = device_tree(decoded)
                        if variant == "restore" and metadata["imageType"] in ["sptm", "trxm"]:
                            out = LOCAL / (path.stem + ".decoded.bin")
                            out.write_bytes(decoded)
                            decoded_for_rea.append(out)
                    else:
                        item["payloadLayout"] = macho_layout(payload)
                except (ValueError, OSError, UnicodeError, struct.error) as error:
                    item["inspectionError"] = str(error)
                    errors.append({"path": safe_path(path), "error": str(error)})
                artifacts.append(item)
        # Inspect only the public IM4P portion, never signed manifests or policy.
        boot_dir = volume / "boot"
        if boot_dir.is_dir():
            for path in sorted(boot_dir.rglob("*")):
                if not path.is_file() or path.is_symlink() or not (path.suffix == ".img4" or path.name == "kernelcache"):
                    continue
                item = {"path": safe_path(path), "scope": "Preboot/boot",
                        "bytes": path.stat().st_size,
                        "wholeContainerHash": "omitted: container may include personalized manifest"}
                try:
                    metadata, _ = image_payload(path)
                    item["image"] = metadata
                except (ValueError, OSError, UnicodeError, struct.error) as error:
                    item["inspectionError"] = str(error)
                    errors.append({"path": safe_path(path), "error": str(error)})
                artifacts.append(item)
    for item in artifacts:
        item["evidenceId"] = evidence_id(item, "artifact")
    for item in manifests:
        item["evidenceId"] = evidence_id(item, "manifest")
    matches = []
    for boot in (item for item in artifacts if item["scope"] == "Preboot/boot"):
        for candidate in (item for item in artifacts if item["scope"] == "Preboot/restore"):
            identity = boot.get("image", {}).get("payloadSha256")
            if identity and identity == candidate.get("image", {}).get("payloadSha256"):
                matches.append({"bootEvidenceId": boot["evidenceId"],
                                "restoreEvidenceId": candidate["evidenceId"],
                                "payloadSha256": identity})
    rea = []
    if args.rea:
        node = PROJECT / "tools/node_modules/node/bin/node"
        cli = PROJECT / "tools/node_modules/rea-agents/scripts/rea.mjs"
        targets = [Path("/System/Library/Kernels/kernel.release.t6031")] + decoded_for_rea
        for path in targets:
            output = LOCAL / (path.name + ".rea-macho.json")
            previous = json.loads(output.read_text()) if output.exists() else {}
            saved = previous.get("data", {})
            if saved.get("evidence_id") and saved.get("subject", {}).get("digest", {}).get("sha256") == sha_file(path):
                envelope = previous
                result_bytes, exit_code = output.read_bytes(), 0
            else:
                result = subprocess.run([str(node), str(cli), "inspect-macho", str(path),
                                         "--format", "json", "--full-output"],
                                        capture_output=True, timeout=180)
                output.write_bytes(result.stdout)
                if result.stderr:
                    output.with_suffix(".stderr.log").write_bytes(result.stderr)
                result_bytes, exit_code = result.stdout, result.returncode
                envelope = json.loads(result_bytes)
            data = envelope.get("data", {})
            rea.append({"operation": "inspect_macho", "targetName": path.name,
                        "evidenceId": data.get("evidence_id"), "exitCode": exit_code,
                        "record": str(output.relative_to(PROJECT / "research")),
                        "recordSha256": digest(result_bytes),
                        "error": data.get("error") or data.get("code")})
    host = subprocess.run(["/usr/bin/sw_vers"], capture_output=True, text=True, check=True).stdout
    findings = {"schema": 1, "capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "evidenceType": "static-artifact-observation", "host": host.strip(),
                "scope": "Installed kernel files, standalone firmware/support inventory, model-specific restore IM4P payloads and public boot IMG4 payloads.",
                "counts": dict(Counter(item["scope"] for item in artifacts)),
                "artifacts": artifacts, "buildManifests": manifests, "bootToRestorePayloadMatches": matches,
                "rea": rea, "errors": errors,
                "limitations": ["No device or firmware code was executed; no MMIO, flash, boot policy or system component was modified.",
                                "File presence and names do not establish that a firmware image was loaded or that its protocol is understood.",
                                "Personalized signatures, device identifiers, keys, LocalPolicy, live device-tree values and diagnostics are not captured.",
                                "Firmware payloads with unrecognized compression remain opaque; SEP is not decrypted or interpreted.",
                                "This is static format and interface discovery, not complete reverse engineering or hardware support."]}
    findings["evidenceId"] = evidence_id(findings, "capture")
    output = json.dumps(findings, indent=2) + "\n"
    prior = LOCAL / "capture.json"
    if prior.exists():
        prior_hash = digest(prior.read_bytes())[:20]
        (LOCAL / ("capture-" + prior_hash + ".json")).write_bytes(prior.read_bytes())
    (LOCAL / "capture.json").write_text(output)
    public = json.loads(output)
    public["completeRecord"] = {"path": "local/boot-firmware/capture.json", "sha256": digest(output.encode())}
    for item in public["artifacts"]:
        layouts = [item.get("layout"), item.get("payloadLayout"), item.get("decoded", {}).get("layout")]
        for layout in layouts:
            if layout:
                layout["segmentNames"] = [segment["name"] for segment in layout.pop("segments")]
                entries = layout.pop("filesetEntries")
                layout["filesetEntryCount"] = len(entries)
                if entries:
                    layout["selectedFilesetEntries"] = [entry["identifier"] for entry in entries if
                        re.search(r"(?:kernel$|AGXG15C|AppleDCP|AppleSPTM|AppleSEP|AppleT6031|AppleANS|RTBuddy|AppleAOP|AppleARMWatchdogTimer|AppleS5L8960X)", entry["identifier"])]
        dt = item.get("decoded", {}).get("deviceTree")
        if dt:
            dt["interfaceNodeCount"] = len(dt["interfaces"])
            selected = [node for node in dt.pop("interfaces") if node["path"].rsplit("/", 1)[-1] in
                        ["arm-io", "aic", "uart0", "pmgr", "ans", "dcp", "aop", "pmp", "sio",
                         "sep", "smc", "sgx", "gfx-asc", "mtp", "ane0", "dart-dcp", "dart-ans"]]
            for node in selected:
                node.pop("properties")
            dt["selectedInterfaces"] = selected
    (PROJECT / "research/boot-firmware-findings.json").write_text(json.dumps(public, indent=2) + "\n")
    print(json.dumps({"evidenceId": findings["evidenceId"], "counts": findings["counts"],
                      "rea": rea, "errors": errors}, indent=2))


if __name__ == "__main__":
    main()
