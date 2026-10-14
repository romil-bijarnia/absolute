#!/usr/bin/env python3
"""Inventory the arm64e dyld cache and inspect bounded libsystem_kernel code.

No investigated trap is executed. Derived code carriers and disassembly remain
under research/local/shared-cache; the public projection contains facts/hashes.
"""
import argparse
from bisect import bisect_right
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import uuid

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "research/local/shared-cache"
CACHE = Path("/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld")
MAP = CACHE / "dyld_shared_cache_arm64e.map"
KERNEL = Path("/usr/lib/system/libsystem_kernel.dylib")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, data):
    if path.exists() and path.read_bytes() != data:
        previous = path.read_bytes()
        archive_directory = LOCAL / "public-history" if path.parent == ROOT / "research" else path.parent
        archive_directory.mkdir(parents=True, exist_ok=True)
        archive = archive_directory / (path.stem + ".previous-" + sha(previous)[:16] + path.suffix)
        if not archive.exists():
            archive.write_bytes(previous)
    path.write_bytes(data)


def save_json(path, value):
    save(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())


def capture(name, argv, reuse=False):
    path = LOCAL / name
    if not (reuse and path.exists() and path.stat().st_size):
        result = subprocess.run([str(x) for x in argv], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=180, check=False)
        save(path, result.stdout)
        save(path.with_suffix(path.suffix + ".stderr.log"), result.stderr)
        save_json(path.with_suffix(path.suffix + ".record.json"), {
            "command": [str(x) for x in argv], "exitCode": result.returncode,
            "sha256": sha(result.stdout), "bytes": len(result.stdout),
            "capturedAt": datetime.now(timezone.utc).isoformat(),
        })
        if result.returncode:
            raise RuntimeError(f"{name} failed; retained stdout and stderr explain the boundary")
    return path.read_text()


class CacheReader:
    """Read fixed cache mapping records; never load or extract entire images."""
    def __init__(self):
        self.mappings = []
        self.files = []
        self.handles = {}
        for path in sorted(CACHE.iterdir()):
            if not re.fullmatch(r"dyld_shared_cache_arm64e(?:\.\d+(?:\.\w+)?)?", path.name):
                continue
            size = path.stat().st_size
            handle = path.open("rb")
            self.handles[path] = handle
            prefix = handle.read(104)
            if not prefix.startswith(b"dyld_v1  arm64e"):
                raise ValueError(f"Unsupported cache magic in {path.name}")
            offset, count = struct.unpack_from("<II", prefix, 16)
            if count > 1024 or offset + count * 32 > size:
                raise ValueError("Cache mapping table outside bounded file")
            handle.seek(offset)
            raw = handle.read(count * 32)
            for index in range(count):
                address, length, file_offset, maximum, initial = struct.unpack_from("<QQQII", raw, index * 32)
                if file_offset + length > size:
                    raise ValueError("Cache mapping exceeds file size")
                self.mappings.append((address, address + length, path, file_offset))
            self.files.append({"name": path.name, "bytes": size,
                               "uuid": str(uuid.UUID(bytes=prefix[88:104])).upper(),
                               "mappingCount": count, "headerPrefixAndMappingsSha256": sha(prefix + raw)})
        self.mappings.sort()
        self.starts = [mapping[0] for mapping in self.mappings]

    def read(self, address, length):
        index = bisect_right(self.starts, address) - 1
        if index < 0:
            raise ValueError("Address precedes cache mappings")
        start, end, path, offset = self.mappings[index]
        if length < 0 or address + length > end:
            raise ValueError("Requested bytes cross a mapping boundary")
        handle = self.handles[path]
        handle.seek(offset + address - start)
        data = handle.read(length)
        if len(data) != length:
            raise ValueError("Short cache read")
        return data

    def close(self):
        for handle in self.handles.values():
            handle.close()


def source_version(value):
    parts = [value >> 40, (value >> 30) & 1023, (value >> 20) & 1023,
             (value >> 10) & 1023, value & 1023]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return ".".join(map(str, parts))


def inspect_header(reader, address):
    header = reader.read(address, 32)
    magic, cpu, subtype, file_type, count, size, flags, reserved = struct.unpack("<IIIIIIII", header)
    if magic != 0xfeedfacf or count > 4096 or size > 1024 * 1024:
        raise ValueError("Unsupported or unbounded Mach-O header")
    commands = reader.read(address + 32, size)
    offset = 0
    result = {"cpuType": cpu, "cpuSubtype": subtype, "fileType": file_type,
              "headerAddress": hex(address), "headerAndCommandsSha256": sha(header + commands)}
    for _ in range(count):
        command, length = struct.unpack_from("<II", commands, offset)
        if length < 8 or offset + length > len(commands):
            raise ValueError("Invalid Mach-O load command bounds")
        if command == 0x1b:
            result["uuid"] = str(uuid.UUID(bytes=commands[offset + 8:offset + 24])).upper()
        if command == 0x2a:
            result["sourceVersion"] = source_version(struct.unpack_from("<Q", commands, offset + 8)[0])
        offset += length
    if offset != size or "uuid" not in result:
        raise ValueError("Incomplete load command coverage or missing UUID")
    return result


def parse_map():
    images = {}
    current = None
    for line in MAP.read_text().splitlines():
        if line.startswith("/"):
            current = line
            images[current] = {}
        match = re.match(r"\s+__TEXT 0x([0-9A-Fa-f]+) -> 0x([0-9A-Fa-f]+)", line)
        if match and current:
            images[current]["address"] = int(match[1], 16)
    if any("address" not in image for image in images.values()):
        raise ValueError("Map image without a text address")
    return images


def parse_inventory(text):
    images = []
    current = None
    section = None
    for line in text.splitlines():
        match = re.match(r"^(/.*?) \[([^]]+)\]:$", line)
        if match:
            current = {"path": match[1], "architecture": match[2], "dependencies": []}
            images.append(current)
            section = None
            continue
        marker = re.match(r"\s+-(\w+):$", line)
        if marker:
            section = marker[1]
            continue
        if current is None:
            continue
        if section == "uuid" and line.strip():
            current["uuid"] = line.strip()
        elif section == "platform":
            fields = line.split()
            if len(fields) == 3 and re.fullmatch(r"\d+(?:\.\d+)*", fields[1]):
                current["platform"], current["minimumOS"], current["sdk"] = fields
        elif section == "linked_dylibs" and "/" in line:
            index = line.index("/")
            current["dependencies"].append({"path": line[index:].strip(), "attributes": line[:index].strip()})
    paths = [image["path"] for image in images]
    if len(paths) != len(set(paths)) or any(image["architecture"] != "arm64e" for image in images):
        raise ValueError("Ambiguous paths or architecture selection")
    return images


def selected_functions(text):
    names = ["_read", "_write", "___getpid", "_mach_msg2_trap",
             "__kernelrpc_mach_vm_allocate_trap", "__kernelrpc_mach_vm_deallocate_trap",
             "_cerror", "_cerror_nocancel", "_mach_msg2_internal", "_mach_vm_allocate", "_mach_vm_deallocate"]
    lines = text.splitlines()
    results = []
    for name in names:
        start = lines.index(name + ":") + 1
        end = start
        while end < len(lines) and not re.match(r"^[^\s].*:$", lines[end]):
            end += 1
        instructions = [line for line in lines[start:end] if re.match(r"^0x[0-9A-Fa-f]+\s", line)]
        first = int(instructions[0].split()[0], 16)
        last = int(instructions[-1].split()[0], 16)
        trap = None
        for index, line in enumerate(instructions[:-1]):
            match = re.search(r"mov\s+x16, #(-?0x[0-9a-f]+)", line)
            if match and "svc" in instructions[index + 1] and "#0x80" in instructions[index + 1]:
                trap = int(match[1], 0)
        results.append({"name": name, "fileImageOffset": first, "byteCount": last + 4 - first,
                        "instructionCount": len(instructions), "x16TrapSelector": trap,
                        "svcImmediate": 128 if trap is not None else None})
    return results


def arm64e_slice(data):
    magic, count = struct.unpack_from(">II", data)
    if magic != 0xcafebabe or count > 64:
        raise ValueError("Expected bounded 32-bit fat architecture table")
    for index in range(count):
        cpu, subtype, offset, size, alignment = struct.unpack_from(">IIIII", data, 8 + index * 20)
        if cpu == 0x100000c and subtype & 0xffffff == 2:
            if offset + size > len(data):
                raise ValueError("Fat slice outside file")
            selected = data[offset:offset + size]
            command_count = struct.unpack_from("<I", selected, 16)[0]
            command_offset = 32
            text_basis = None
            for _ in range(command_count):
                command, command_size = struct.unpack_from("<II", selected, command_offset)
                if command_size < 8 or command_offset + command_size > len(selected):
                    raise ValueError("Invalid standalone Mach-O command bounds")
                if command == 0x19 and selected[command_offset + 8:command_offset + 24].rstrip(b"\0") == b"__TEXT":
                    text_basis = (struct.unpack_from("<Q", selected, command_offset + 24)[0],
                                  struct.unpack_from("<Q", selected, command_offset + 40)[0])
                command_offset += command_size
            if text_basis != (0, 0):
                raise ValueError("Standalone text basis changed; review file-to-cache address mapping")
            return selected
    raise ValueError("No arm64e slice")


def carrier(code, address):
    # Minimal local MH_OBJECT preserves the observed virtual instruction address.
    # Its synthetic headers are only a carrier for otool, not an extracted dylib.
    name = lambda value: value.encode().ljust(16, b"\0")
    header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x100000c, 0x80000002, 1, 1, 152, 0, 0)
    segment = struct.pack("<II16sQQQQiiII", 0x19, 152, name("__TEXT"), address, len(code),
                          184, len(code), 5, 5, 1, 0)
    section = struct.pack("<16s16sQQIIIIIIII", name("__text"), name("__TEXT"), address,
                          len(code), 184, 2, 0, 0, 0x80000400, 0, 0, 0)
    return header + segment + section + code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    LOCAL.mkdir(parents=True, exist_ok=True)
    sdk = Path(subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True).strip())
    host = subprocess.check_output(["/usr/bin/sw_vers"], text=True).strip()
    kernel_file = KERNEL.read_bytes()
    identity = {"host": host, "mapSha256": sha(MAP.read_bytes()), "kernelFileSha256": sha(kernel_file)}
    identity_path = LOCAL / "identity.json"
    previous = json.loads(identity_path.read_text()) if identity_path.exists() else None
    reuse = not args.refresh and (previous is None or previous == identity)
    text = capture("all-images-arm64e.txt", ["/usr/bin/xcrun", "dyld_info", "-arch", "arm64e",
                    "-uuid", "-platform", "-linked_dylibs", "-all_dyld_cache"], reuse)
    images = parse_inventory(text)
    map_images = parse_map()
    by_path = {image["path"]: image for image in images}
    if set(map_images) != set(by_path):
        raise ValueError("dyld_info image paths do not match installed cache map")
    reader = CacheReader()
    try:
        for image in images:
            actual = inspect_header(reader, map_images[image["path"]]["address"])
            if actual["uuid"] != image["uuid"]:
                raise ValueError(f"Cache/file UUID mismatch: {image['path']}")
            if actual["cpuType"] != 0x100000c or actual["cpuSubtype"] & 0xffffff != 2:
                raise ValueError(f"Unexpected cached CPU type/subtype: {image['path']}")
            image["cacheHeader"] = actual
        edges = []
        for image in images:
            for dependency in image["dependencies"]:
                edge = {"from": image["path"], **dependency}
                target = dependency["path"]
                edge["resolution"] = "literal-cache-path" if target in by_path else "outside-catalog"
                if target not in by_path:
                    resolved = str(Path(target).resolve())
                    edge["resolvedPath"] = resolved
                    edge["ordinaryFilePresent"] = Path(target).exists()
                    if resolved in by_path:
                        edge["resolution"] = "filesystem-symlink-to-cache-path"
                edges.append(edge)
        complete = {"identity": identity, "cacheFiles": reader.files, "images": images, "edges": edges}
        save_json(LOCAL / "complete-inventory.json", complete)
        kernel_text = capture("libsystem-kernel-arm64e.txt", ["/usr/bin/xcrun", "dyld_info", "-arch", "arm64e",
                          "-uuid", "-platform", "-load_commands", "-exports", "-function_starts", "-disassemble", KERNEL], reuse)
        functions = selected_functions(kernel_text)
        getpid_aliases = {name: sorted({int(offset, 16) for offset in re.findall(
            r"^\s+(0x[0-9A-Fa-f]+)\s+" + re.escape(name) + r"\s*$", kernel_text, re.M)})
            for name in ["_getpid", "___getpid"]}
        getpid_start = next(f["fileImageOffset"] for f in functions if f["name"] == "___getpid")
        if any(offsets != [getpid_start] for offsets in getpid_aliases.values()):
            raise ValueError("getpid export alias identity changed")
        kernel = by_path[str(KERNEL)]
        slice_bytes = arm64e_slice(kernel_file)
        for function in functions:
            offset, length = function["fileImageOffset"], function["byteCount"]
            address = map_images[str(KERNEL)]["address"] + offset
            code = reader.read(address, length)
            original = slice_bytes[offset:offset + length]
            function["cacheAddress"] = hex(address)
            function["cachedCodeSha256"] = sha(code)
            function["diskCodeSha256"] = sha(original)
            function["cacheBytesEqualDisk"] = code == original
            function["changedInstructionOffsets"] = [index for index in range(0, length, 4)
                if code[index:index + 4] != original[index:index + 4]]
            # Trap selectors are decoded again from the actual cache instructions.
            if function["x16TrapSelector"] is not None:
                expected = function["x16TrapSelector"]
                found = False
                for index in range(4, length, 4):
                    prior, word = struct.unpack_from("<II", code, index - 4)
                    if word != 0xd4001001:
                        continue
                    rd = prior & 31
                    if rd != 16:
                        continue
                    if prior & 0xff800000 == 0xd2800000:  # MOVZ X16, imm16
                        value = ((prior >> 5) & 0xffff) << (((prior >> 21) & 3) * 16)
                    elif prior & 0xff800000 == 0x92800000:  # MOVN X16, imm16
                        value = ~(((prior >> 5) & 0xffff) << (((prior >> 21) & 3) * 16))
                    else:
                        continue
                    found = value == expected
                if not found:
                    raise ValueError(f"Cached trap instructions differ: {function['name']}")
                function["selectorVerifiedFromCacheBytes"] = True
            stem = function["name"].lstrip("_") + "-cache"
            object_path = LOCAL / (stem + ".o")
            save(object_path, carrier(code, address))
            disassembly = capture(stem + ".txt", ["/usr/bin/xcrun", "otool", "-arch", "arm64e", "-tvV", object_path])
            function["cacheDisassemblyFile"] = "research/local/shared-cache/" + stem + ".txt"
            function["cacheDisassemblySha256"] = sha(disassembly.encode())
        kernel_abi_path = ROOT / "research/kernel-abi-findings.json"
        kernel_abi_bytes = kernel_abi_path.read_bytes()
        kernel_abi = json.loads(kernel_abi_bytes)
        if kernel_abi["host"]["build"] not in host:
            raise ValueError("Kernel ABI report belongs to a different OS build")
        constants = {entry["name"]: entry["number"] for entry in kernel_abi["syscalls"]["entries"]}
        comparisons = []
        for api, symbol in [("read", "_read"), ("write", "_write"), ("getpid", "___getpid")]:
            observed = next(f["x16TrapSelector"] for f in functions if f["name"] == symbol)
            comparisons.append({"api": api, "functionLabel": symbol, "observedSelector": observed,
                                "sdkSyscallNumber": constants[api], "matches": observed == constants[api]})
        message_path = sdk / "usr/include/mach/message.h"
        message_text = message_path.read_text()
        macro_names = ["MACH_SEND_INTERRUPT", "MACH_RCV_INTERRUPT", "MACH_SEND_INTERRUPTED",
                       "MACH_RCV_INTERRUPTED", "MACH_SEND_INVALID_DEST"]
        mach_constants = {name: int(re.search(r"^#define\s+" + name + r"\s+(0x[0-9A-Fa-f]+)", message_text, re.M)[1], 16)
                          for name in macro_names}
        inventory = json.loads((ROOT / "research/system-inventory.json").read_text())
        binaries = json.loads((ROOT / inventory["local_capture"] / "binaries.json").read_text())
        gpu = [{"path": item["path"], "slices": [part for part in item["slices"] if part["cpu_type"] == 0x1000013]}
               for item in binaries if any(part["cpu_type"] == 0x1000013 for part in item["slices"])]
        representative = Path(gpu[0]["path"])
        gpu_headers = capture("gpu-representative-headers.txt", ["/usr/bin/xcrun", "otool", "-hv", representative], reuse)
        gpu_architectures = capture("gpu-representative-architectures.txt", ["/usr/bin/xcrun", "lipo", "-archs", representative], reuse)
        machine_path = sdk / "usr/include/mach/machine.h"
        loader_path = sdk / "usr/include/mach-o/loader.h"
        machine = machine_path.read_text()
        loader = loader_path.read_text()
        sdk_kernel_versions = sorted({version for collection in kernel_abi["libraries"] for library in collection.get("libraries", [])
                                      if str(KERNEL) in library.get("install_names", []) for version in library.get("versions", [])})
        incoming = Counter(edge["path"] for edge in edges)
        result = {"schema": 1, "capturedAt": datetime.now(timezone.utc).isoformat(), **identity,
                  "scriptSha256": sha(Path(__file__).read_bytes()),
                  "evidenceType": "static-cache-header-and-disassembly-observation",
                  "localInventory": "research/local/shared-cache/complete-inventory.json",
                  "localInventorySha256": sha((LOCAL / "complete-inventory.json").read_bytes()),
                  "rawInventorySha256": sha(text.encode()), "cacheFileCount": len(reader.files),
                  "imageCount": len(images), "cacheMapImageCount": len(map_images), "cacheImageUuidsVerified": len(images),
                  "dependencyEdgeCount": len(edges), "resolutionCounts": dict(Counter(edge["resolution"] for edge in edges)),
                  "dependencyAttributeCounts": dict(Counter(edge["attributes"] or "ordinary" for edge in edges)),
                  "platformCounts": dict(Counter(image.get("platform", "unknown") for image in images)),
                  "minimumOSCounts": dict(Counter(image.get("minimumOS", "unknown") for image in images)),
                  "topIncomingDependencies": [{"path": path, "count": count} for path, count in incoming.most_common(20)],
                  "outsideLiteralCatalogEdges": [edge for edge in edges if edge["resolution"] != "literal-cache-path"],
                  "kernelImage": {"path": str(KERNEL), "uuid": kernel["uuid"], "cacheHeader": kernel["cacheHeader"],
                      "sdk": kernel["sdk"], "minimumOS": kernel["minimumOS"], "sdkTbdVersions": sdk_kernel_versions,
                      "diskDisassemblySha256": sha(kernel_text.encode()), "selectedFunctions": functions,
                      "getpidExportAliasOffsets": getpid_aliases,
                      "bsdSelectorComparisons": comparisons, "machMessageConstants": mach_constants,
                      "machMessageHeaderSha256": sha(message_path.read_bytes()),
                      "kernelAbiEvidenceId": kernel_abi["evidence_id"], "kernelAbiReportSha256": sha(kernel_abi_bytes)},
                  "gpuExecutableRecords": {"inventoryEvidenceId": inventory["evidence_id"], "fileCount": len(gpu),
                      "sliceCount": sum(len(item["slices"]) for item in gpu), "cpuType": "0x01000013",
                      "cpuArchitectureBit": "CPU_ARCH_ABI64", "baseCpuType": 19,
                      "baseCpuName": None, "localHeaderSkipsBase19": bool(re.search(r"skip.*cpu_type_t\) 19", machine)),
                      "fileType": "MH_GPU_EXECUTE", "sdkHeaderFileTypeValue": int(re.search(r"#define\s+MH_GPU_EXECUTE\s+(0x[0-9a-f]+)", loader)[1], 16),
                      "representativePath": str(representative), "representativeHeaderOutputSha256": sha(gpu_headers.encode()),
                      "lipoArchitectureOutput": gpu_architectures.strip(), "lipoOutputSha256": sha(gpu_architectures.encode()),
                      "machineHeaderSha256": sha(machine_path.read_bytes()), "loaderHeaderSha256": sha(loader_path.read_bytes()),
                      "limits": ["The local machine.h skips base CPU type 19; otool prints its numeric type.",
                                 "GPU program file type is identified, but a named architecture or subtype-to-chip mapping is not established.",
                                 "These are slices within files, not 229 separately understood GPU programs."]},
                  "limits": ["Image/load counts are inventory completeness within this cache, not implementation coverage.",
                      "Only eleven selected libsystem_kernel functions were interpreted; the remaining disassembly is unreviewed.",
                      "No guessed trap or private syscall was executed; these are user-space entry conventions, not kernel-handler implementations.",
                      "Cached code can differ from standalone code through relocation/optimization; selected actual cache bytes and derived disassembly are retained locally.",
                      "Dependencies outside the catalog may be optional, aliased or supplied elsewhere; this inventory does not prove runtime failure.",
                      "SDK declarations and implementation source versions are recorded separately; matching selectors do not establish complete ABI compatibility."]}
        result["evidenceId"] = "absolute-shared-cache-sha256:" + sha(json.dumps(result, sort_keys=True).encode())
        save_json(ROOT / "research/shared-cache-findings.json", result)
        save_json(identity_path, identity)
        print(json.dumps({"images": len(images), "uuidMatches": len(images), "edges": len(edges),
                          "resolution": result["resolutionCounts"], "functions": len(functions),
                          "syscallComparisons": comparisons, "gpuSlices": result["gpuExecutableRecords"]["sliceCount"]}, indent=2))
    finally:
        reader.close()


if __name__ == "__main__":
    main()
