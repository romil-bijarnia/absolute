#!/usr/bin/env python3
"""Inspect bounded kernel-origin Mach message code without executing it.

The installed kernel and its prior REA metadata must have the reviewed digest.
Private derived carriers, bytes, and disassembly stay under research/local.
Public output contains identities, scalar observations, and explicit limits.
"""
import argparse
from bisect import bisect_left
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import uuid


ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "research/local/mach-kernel"
REPORT = ROOT / "research/mach-kernel-findings.json"
KERNEL = Path("/System/Library/Kernels/kernel.release.t6031")
REA_METADATA = ROOT / "research/local/boot-firmware/kernel.release.t6031.rea-macho.json"
REVIEWED_SHA256 = "ca7d17c39aa7a68ef280f3aa84e9d57a7c6be8630fa13d5a891e75db0fb9ae5e"
SEND_SYMBOL = "_mach_msg_send_from_kernel_proper"
SEND_ADDRESS = 0xfffffe0007364938
CALLEES = {
    0xfffffe0007335f40: "message-copy-stage",
    0xfffffe000733618c: "header-and-disposition-stage",
    0xfffffe0007331ff0: "early-cleanup-stage",
    0xfffffe00073366bc: "send-dispatch-stage",
    0xfffffe00073322bc: "late-cleanup-stage",
}
PRIVATE_NAME_QUERIES = [
    "_mach_msg2_trap", "_mach_msg_trap", "_mach_msg_overwrite_trap",
    "_ipc_kmsg_get", "_ipc_kmsg_copyin", "_ipc_kmsg_send", "_ipc_mqueue_send",
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def relative(path):
    return str(path.relative_to(ROOT))


def save(path, data, check=False):
    if check:
        if not path.exists() or path.read_bytes() != data:
            raise ValueError("Missing or changed retained evidence: " + relative(path))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() != data:
        previous = path.read_bytes()
        directory = LOCAL / "public-history" if path == REPORT else path.parent
        directory.mkdir(parents=True, exist_ok=True)
        archive = directory / (path.stem + ".previous-" + sha(previous)[:16] + path.suffix)
        if not archive.exists():
            archive.write_bytes(previous)
    path.write_bytes(data)


def capture(name, argv, check=False):
    path = LOCAL / name
    record_path = path.with_suffix(path.suffix + ".record.json")
    if check:
        record = json.loads(record_path.read_text())
        raw = path.read_bytes()
        error = path.with_suffix(path.suffix + ".stderr.log").read_bytes()
        if (record["command"] != argv or record["exitCode"] != 0
                or record["sha256"] != sha(raw) or record["bytes"] != len(raw)
                or record["stderrSha256"] != sha(error)):
            raise ValueError("Capture provenance changed: " + name)
        return raw
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=30, check=False)
    save(path, result.stdout)
    save(path.with_suffix(path.suffix + ".stderr.log"), result.stderr)
    save(record_path, json_bytes({
        "command": argv, "exitCode": result.returncode,
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "sha256": sha(result.stdout), "bytes": len(result.stdout),
        "stderrSha256": sha(result.stderr),
    }))
    if result.returncode:
        raise RuntimeError("Command failed; retained capture: " + name)
    return result.stdout


def signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def source_version(value):
    parts = [value >> 40, (value >> 30) & 1023, (value >> 20) & 1023,
             (value >> 10) & 1023, value & 1023]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return ".".join(map(str, parts))


class KernelImage:
    def __init__(self, data):
        self.data = data
        header = struct.unpack_from("<IIIIIIII", data)
        if header[0] != 0xfeedfacf or header[1] != 0x100000c or header[2] & 0xffffff != 2:
            raise ValueError("Expected the reviewed arm64e Mach-O")
        count, command_size = header[4:6]
        if count > 4096 or 32 + command_size > len(data):
            raise ValueError("Invalid Mach-O load-command bounds")
        self.segments, self.sections = [], []
        self.uuid, self.source_version, starts, symtab = None, None, None, None
        offset = 32
        for _ in range(count):
            command, size = struct.unpack_from("<II", data, offset)
            if size < 8 or offset + size > 32 + command_size:
                raise ValueError("Invalid Mach-O load-command length")
            if command == 0x19:
                fields = struct.unpack_from("<II16sQQQQiiII", data, offset)
                name = fields[2].rstrip(b"\0").decode()
                address, memory_size, file_offset, file_size = fields[3:7]
                section_count = fields[9]
                if size != 72 + section_count * 80 or file_offset + file_size > len(data):
                    raise ValueError("Invalid file-backed segment bounds")
                self.segments.append({"name": name, "address": address,
                    "memorySize": memory_size, "fileOffset": file_offset, "fileSize": file_size})
                for index in range(section_count):
                    section = struct.unpack_from("<16s16sQQIIIIIIII", data, offset + 72 + index * 80)
                    self.sections.append({"name": section[0].rstrip(b"\0").decode(),
                        "segment": section[1].rstrip(b"\0").decode(),
                        "address": section[2], "size": section[3], "fileOffset": section[4]})
            elif command == 0x1b:
                self.uuid = str(uuid.UUID(bytes=data[offset + 8:offset + 24])).upper()
            elif command == 0x2a:
                self.source_version = source_version(struct.unpack_from("<Q", data, offset + 8)[0])
            elif command == 0x26:
                starts = struct.unpack_from("<II", data, offset + 8)
            elif command == 0x2:
                symtab = struct.unpack_from("<IIII", data, offset + 8)
            offset += size
        if offset != 32 + command_size or not all([self.uuid, self.source_version, starts, symtab]):
            raise ValueError("Incomplete required Mach-O metadata")
        self.header_sha256 = sha(data[:offset])
        base = next(segment["address"] for segment in self.segments if segment["name"] == "__TEXT")
        start_offset, start_size = starts
        if start_offset + start_size > len(data):
            raise ValueError("Function-start table exceeds the file")
        raw_starts = data[start_offset:start_offset + start_size]
        self.starts, address, value, shift, terminated = [], base, 0, 0, False
        for index, byte in enumerate(raw_starts):
            value |= (byte & 127) << shift
            if byte & 128:
                shift += 7
                if shift >= 64:
                    raise ValueError("Unbounded function-start ULEB128")
                continue
            if not value:
                if any(raw_starts[index + 1:]):
                    raise ValueError("Nonzero data after function-start terminator")
                terminated = True
                break
            address += value
            self.starts.append(address)
            value, shift = 0, 0
        if not terminated or self.starts != sorted(set(self.starts)):
            raise ValueError("Incomplete function-start decoding")
        self.start_table = {"fileOffset": start_offset, "byteCount": start_size,
                            "sha256": sha(raw_starts), "entryCount": len(self.starts)}
        sym_offset, sym_count, str_offset, str_size = symtab
        if sym_offset + sym_count * 16 > len(data) or str_offset + str_size > len(data):
            raise ValueError("Symbol-table bounds exceed the file")
        strings = data[str_offset:str_offset + str_size]
        self.symbols = []
        for index in range(sym_count):
            string_index, kind, section, description, value = struct.unpack_from(
                "<IBBHQ", data, sym_offset + index * 16)
            end = strings.find(b"\0", string_index)
            if string_index >= len(strings) or end < 0:
                raise ValueError("Symbol name exceeds the string table")
            self.symbols.append({"name": strings[string_index:end].decode(),
                "address": value, "type": kind, "section": section,
                "external": bool(kind & 1), "description": description})
        self.symbol_table = {"fileOffset": sym_offset, "entryCount": sym_count,
            "entriesSha256": sha(data[sym_offset:sym_offset + sym_count * 16]),
            "stringsFileOffset": str_offset, "stringsByteCount": str_size,
            "stringsSha256": sha(strings)}

    def read(self, address, length):
        matches = [segment for segment in self.segments
                   if segment["address"] <= address
                   and address + length <= segment["address"] + segment["fileSize"]]
        if length < 1 or len(matches) != 1:
            raise ValueError("Ambiguous or non-file-backed address range")
        segment = matches[0]
        offset = segment["fileOffset"] + address - segment["address"]
        return self.data[offset:offset + length], offset, segment["name"]

    def span(self, address):
        index = bisect_left(self.starts, address)
        if index >= len(self.starts) - 1 or self.starts[index] != address:
            raise ValueError("Selected address is not a bounded function start")
        end = self.starts[index + 1]
        if end - address > 4096 or (end - address) % 4:
            raise ValueError("Selected function-start span exceeds the bounded review")
        code, offset, segment = self.read(address, end - address)
        sections = [section for section in self.sections
                    if section["segment"] == segment and section["address"] <= address
                    and end <= section["address"] + section["size"]]
        if len(sections) != 1 or segment != "__TEXT_EXEC" or sections[0]["name"] != "__text":
            raise ValueError("Selected span is not contained in the expected code section")
        if offset != sections[0]["fileOffset"] + address - sections[0]["address"]:
            raise ValueError("Segment and section file-offset mappings disagree")
        return code, {"address": hex(address), "endExclusive": hex(end),
            "fileOffset": offset, "byteCount": len(code), "segment": segment,
            "section": sections[0]["name"], "codeSha256": sha(code),
            "boundarySource": "LC_FUNCTION_STARTS next entry; half-open range"}

    def names_at(self, address):
        return sorted(symbol["name"] for symbol in self.symbols if symbol["address"] == address)


def carrier(code, address):
    # An inert MH_OBJECT carrier preserves instruction addresses for otool.
    # Its headers are synthetic and it is never loaded as a runnable image.
    name = lambda value: value.encode().ljust(16, b"\0")
    header = struct.pack("<IIIIIIII", 0xfeedfacf, 0x100000c, 0x80000002, 1, 1, 152, 0, 0)
    segment = struct.pack("<II16sQQQQiiII", 0x19, 152, name("__TEXT"), address,
                          len(code), 184, len(code), 5, 5, 1, 0)
    section = struct.pack("<16s16sQQIIIIIIII", name("__text"), name("__TEXT"),
                          address, len(code), 184, 2, 0, 0, 0x80000400, 0, 0, 0)
    return header + segment + section + code


def direct_edges(code, address, image):
    result = []
    for offset in range(0, len(code), 4):
        word = struct.unpack_from("<I", code, offset)[0]
        if word & 0x7c000000 != 0x14000000:
            continue
        source = address + offset
        target = source + (signed(word & 0x3ffffff, 26) << 2)
        is_call = bool(word & 0x80000000)
        if not is_call and address <= target < address + len(code):
            continue
        result.append({"source": hex(source), "target": hex(target),
            "kind": "direct-call" if is_call else "external-unconditional-branch",
            "exactTargetSymbols": image.names_at(target),
            "targetIsFunctionStart": target in image.starts})
    return result


def table_address(image):
    address = 0xfffffe0007336290
    code, _, _ = image.read(address, 8)
    page, addition = struct.unpack("<II", code)
    if page & 0x9f000000 != 0x90000000 or addition & 0xffc00000 != 0x91000000:
        raise ValueError("Disposition-table address producer changed")
    register = page & 31
    if addition & 31 != register or (addition >> 5) & 31 != register:
        raise ValueError("Disposition-table register relationship changed")
    immediate = ((page >> 29) & 3) | (((page >> 5) & 0x7ffff) << 2)
    return (address & ~0xfff) + (signed(immediate, 21) << 12) + ((addition >> 10) & 0xfff)


def macro(text, name):
    match = re.search(r"^#define\s+" + re.escape(name) + r"\s+(0x[0-9a-fA-F]+|[0-9]+)(?:[uUlL]+)?\b", text, re.M)
    if not match:
        raise ValueError("Missing scalar SDK declaration: " + name)
    return int(match[1], 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify retained captures and the public projection without rewriting them")
    args = parser.parse_args()
    if not args.check:
        LOCAL.mkdir(parents=True, exist_ok=True)
    data = KERNEL.read_bytes()
    if sha(data) != REVIEWED_SHA256:
        raise ValueError("Installed kernel changed; renewed static interpretation is required")
    image = KernelImage(data)
    rea_bytes = REA_METADATA.read_bytes()
    rea = json.loads(rea_bytes)
    if (not rea.get("ok") or rea["data"]["subject"]["digest"]["sha256"] != sha(data)
            or rea["data"]["subject"]["local_path"] != str(KERNEL)
            or rea["data"]["normalized_result"]["uuid"] != image.uuid):
        raise ValueError("Prior REA metadata is not bound to this kernel")
    symbols_path = LOCAL / "kernel-symbols.txt"
    symbols_raw = symbols_path.read_bytes()
    nm_pairs = set()
    for line in symbols_raw.decode().splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{16})\s+.+?\s+(\S+)", line)
        if not match:
            raise ValueError("Unparsed retained nm row")
        nm_pairs.add((int(match[1], 16), match[2]))
    binary_pairs = {(symbol["address"], symbol["name"]) for symbol in image.symbols}
    if nm_pairs != binary_pairs:
        raise ValueError("Retained nm symbol/address pairs disagree with the current LC_SYMTAB")
    if SEND_SYMBOL not in image.names_at(SEND_ADDRESS):
        raise ValueError("Reviewed public entry changed")
    all_names = {symbol["name"] for symbol in image.symbols}
    negative = {name: name in all_names for name in PRIVATE_NAME_QUERIES}
    if any(negative.values()):
        raise ValueError("Private-name search boundary changed")

    sdk = Path(subprocess.check_output(["/usr/bin/xcrun", "--show-sdk-path"], text=True).strip())
    header_dir = sdk / "System/Library/Frameworks/Kernel.framework/Headers"
    message_path, mig_path = header_dir / "mach/message.h", header_dir / "kern/ipc_mig.h"
    message_text, mig_text = message_path.read_text(), mig_path.read_text()
    save(LOCAL / "sdk-mach-message.h", message_path.read_bytes(), args.check)
    save(LOCAL / "sdk-ipc-mig.h", mig_path.read_bytes(), args.check)
    layout = re.search(r"xnu_static_assert_struct_size_kernel_user\(mach_msg_header_t,\s*(\d+),\s*(\d+)\)", message_text)
    if not layout or tuple(map(int, layout.groups())) != (32, 24):
        raise ValueError("Kernel/user header declarations changed")
    if not re.search(r"mach_msg_send_from_kernel_proper\(\s*mach_msg_header_t\s*\*msg,\s*mach_msg_size_t\s*send_size\)", mig_text):
        raise ValueError("Kernel send API declaration changed")
    constants = {name: macro(message_text, name) for name in [
        "MACH_SEND_INVALID_DEST", "MACH_SEND_NO_BUFFER", "MACH_SEND_TOO_LARGE",
        "MACH_MSGH_BITS_COMPLEX", "MACH_SEND_MSG", "MACH_SEND_ALWAYS", "MACH_SEND_NOIMPORTANCE",
        "MACH_MSG_TYPE_MOVE_RECEIVE", "MACH_MSG_TYPE_MOVE_SEND", "MACH_MSG_TYPE_MOVE_SEND_ONCE",
        "MACH_MSG_TYPE_COPY_SEND", "MACH_MSG_TYPE_MAKE_SEND", "MACH_MSG_TYPE_MAKE_SEND_ONCE",
    ]}
    if [constants[name] for name in ["MACH_SEND_INVALID_DEST", "MACH_SEND_NO_BUFFER", "MACH_SEND_TOO_LARGE"]] != [0x10000003, 0x1000000d, 0x1000000e]:
        raise ValueError("SDK error-code interpretation changed")

    functions = []
    for address, role in [(SEND_ADDRESS, "exported-kernel-send-wrapper"), *CALLEES.items()]:
        code, record = image.span(address)
        stem = "send-wrapper" if address == SEND_ADDRESS else "callee-" + format(address, "x")
        object_path = LOCAL / (stem + ".o")
        object_bytes = carrier(code, address)
        save(object_path, object_bytes, args.check)
        disassembly = capture(stem + ".txt", ["/usr/bin/xcrun", "otool", "-arch", "arm64e", "-tvV", str(object_path)], args.check)
        lines = disassembly.decode().splitlines()
        decoded = [int(match[1], 16) for line in lines
                   if (match := re.match(r"^([0-9a-fA-F]{16})\s", line))]
        if decoded != list(range(address, address + len(code), 4)):
            raise ValueError("Disassembly does not cover precisely the selected span")
        edges = direct_edges(code, address, image)
        if address == SEND_ADDRESS and {int(edge["target"], 16) for edge in edges} != set(CALLEES):
            raise ValueError("Reviewed immediate callee set changed")
        record.update({"exactSymbols": image.names_at(address), "inferredRole": role,
            "privateRoleIsInferred": address != SEND_ADDRESS,
            "instructionSlots": len(code) // 4, "directEdges": edges,
            "localCarrier": relative(object_path), "carrierSha256": sha(object_bytes),
            "localDisassembly": relative(LOCAL / (stem + ".txt")),
            "disassemblySha256": sha(disassembly),
            "interpretationCoverage": "Selected control/data paths; not a complete semantic reconstruction"})
        functions.append(record)

    address = table_address(image)
    table, table_offset, table_segment = image.read(address, 24)
    values = list(struct.unpack("<6I", table))
    if address != 0xfffffe0007008ab0 or values != [16, 17, 18, 17, 17, 18]:
        raise ValueError("Reviewed disposition table changed")
    save(LOCAL / "disposition-table.bin", table, args.check)
    table_record = {"address": hex(address), "fileOffset": table_offset,
        "byteCount": 24, "segment": table_segment, "sha256": sha(table),
        "localBytes": relative(LOCAL / "disposition-table.bin"),
        "inputCodes": [16, 17, 18, 19, 20, 21], "outputCodes": values,
        "addressProducer": "0xfffffe0007336290", "entryWidthBytes": 4}
    host_raw = capture("host-sw-vers.txt", ["/usr/bin/sw_vers"], args.check)
    host = dict(line.split(":", 1) for line in host_raw.decode().splitlines())
    host = {key: value.strip() for key, value in host.items()}
    captured_at = json.loads(REPORT.read_text())["capturedAt"] if args.check else datetime.now(timezone.utc).isoformat()
    selected = {int(function["address"], 16) for function in functions}
    unreviewed = sorted({int(edge["target"], 16) for function in functions for edge in function["directEdges"]
                         if int(edge["target"], 16) not in selected})
    report = {
        "schema": 1, "capturedAt": captured_at,
        "evidenceType": "static-kernel-binary-and-sdk-observation",
        "status": "partial", "scriptSha256": sha(Path(__file__).read_bytes()),
        "host": host,
        "kernel": {"path": str(KERNEL), "sha256": sha(data), "bytes": len(data),
            "uuid": image.uuid, "sourceVersion": image.source_version,
            "headerAndCommandsSha256": image.header_sha256,
            "addressSpace": "Unslid link-time virtual addresses; installed file, not live kernel memory",
            "reaMetadata": {"file": relative(REA_METADATA), "sha256": sha(rea_bytes),
                "evidenceId": rea["data"]["evidence_id"], "operation": rea["data"]["operation"]},
            "functionStartTable": image.start_table, "symbolTable": image.symbol_table},
        "sdk": {"path": str(sdk), "headers": [
            {"path": str(message_path), "sha256": sha(message_path.read_bytes()),
             "localCapture": relative(LOCAL / "sdk-mach-message.h")},
            {"path": str(mig_path), "sha256": sha(mig_path.read_bytes()),
             "localCapture": relative(LOCAL / "sdk-ipc-mig.h")}],
            "kernelHeaderBytes": 32, "userHeaderBytes": 24,
            "kernelSendArgumentNames": ["msg", "send_size"], "constants": constants,
            "limit": "SDK declarations are independent evidence; no source-version equivalence is asserted"},
        "symbolSearch": {"capture": relative(symbols_path), "sha256": sha(symbols_raw),
            "symbolAddressPairsVerifiedAgainstBinary": len(nm_pairs),
            "pattern": "mach_msg|ipc_kmsg|ipc_mqueue",
            "matches": [{"name": symbol["name"], "address": hex(symbol["address"])} for symbol in image.symbols
                        if re.search(r"mach_msg|ipc_kmsg|ipc_mqueue", symbol["name"])],
            "exactNamePresent": negative,
            "limit": "Absent names in this retained symbol table do not establish absent code or an identified user trap"},
        "functions": functions, "dispositionTable": table_record,
        "coverage": {"functionStartSpansDisassembled": len(functions),
            "selectedCodeBytes": sum(function["byteCount"] for function in functions),
            "selectedInstructionSlots": sum(function["instructionSlots"] for function in functions),
            "scalarDataBytesInspected": len(table),
            "unreviewedDirectEdgeTargetCount": len(unreviewed),
            "unreviewedDirectEdgeTargets": [hex(target) for target in unreviewed],
            "canonicalReaFunctionDossiersAdded": 0,
            "kernelBytesExecuted": False, "liveKernelAttached": False},
        "findings": [
            {"id": "KMSG-001", "kind": "artifact-observation-and-sdk-declaration",
             "claim": "The exported kernel-origin send API and its immediate callees have a different header representation from the user API: the local SDK specifies 32 kernel bytes and 24 user bytes.",
             "locations": ["0xfffffe0007364938", "0xfffffe0007335f80"],
             "limit": "Kernel-origin results cannot substitute for user mach_msg2 trap behavior."},
            {"id": "KMSG-002", "kind": "static-control-flow-inference",
             "claim": "The wrapper has ordered copy, header/disposition, and dispatch stages. It returns a nonzero first-stage status directly, invokes an early cleanup after second-stage failure, and a different cleanup after dispatch failure.",
             "locations": ["0xfffffe0007364964", "0xfffffe0007364974", "0xfffffe0007364984", "0xfffffe00073649a8", "0xfffffe00073649bc"],
             "limit": "Stage labels describe inferred roles, not recovered private names or complete ownership semantics."},
            {"id": "KMSG-003", "kind": "static-control-flow-inference",
             "claim": "For a non-complex kernel header, the first stage compares the supplied size against 32 and returns 0x1000000e when it is smaller. A null result from the buffer-producing callee returns 0x1000000d. The local SDK names these MACH_SEND_TOO_LARGE and MACH_SEND_NO_BUFFER.",
             "locations": ["0xfffffe0007335f70", "0xfffffe0007335f98", "0xfffffe0007335fec"],
             "limit": "This is a trusted kernel-origin path; no malformed input was executed and no userspace size-validation rule follows."},
            {"id": "KMSG-004", "kind": "static-control-flow-inference",
             "claim": "The second stage returns 0x10000003 before port-processing calls when its 64-bit destination value is zero or all ones. The local SDK names this MACH_SEND_INVALID_DEST.",
             "locations": ["0xfffffe00073361ec", "0xfffffe0007336210", "0xfffffe000733621c"],
             "limit": "This checks internal pointer sentinel values, not the user's task-local port-name validity."},
            {"id": "KMSG-005", "kind": "static-data-and-control-flow-inference",
             "claim": "A six-entry table maps disposition codes 16 through 21 to 16, 17, 18, 17, 17, 18. The header-processing stage uses it for the remote, local, and voucher bit fields; COPY_SEND and MAKE_SEND normalize to the internal send code, and MAKE_SEND_ONCE to the internal send-once code.",
             "locations": ["0xfffffe0007008ab0", "0xfffffe000733628c", "0xfffffe00073362cc", "0xfffffe0007336304"],
             "limit": "Normalization alone does not establish that a right is valid, which reference counts change, or how a user receive header is rewritten."},
            {"id": "KMSG-006", "kind": "static-instruction-inference",
             "claim": "The wrapper supplies option value 0x2000050001 to the first stage. Before dispatch a thread-state bit can remove 0x40000. The low flags correspond in the SDK to MACH_SEND_MSG, MACH_SEND_ALWAYS, and MACH_SEND_NOIMPORTANCE.",
             "locations": ["0xfffffe000736494c", "0xfffffe0007364990"],
             "limit": "The high option bit remains unnamed here, and downstream option changes prevent inferring complete queue or timeout behavior."},
        ],
        "limits": [
            "Only six selected function-start spans and one 24-byte table were inspected; no complete kernel, Mach subsystem, or user trap implementation was recovered.",
            "LC_FUNCTION_STARTS gives next-entry extraction bounds, not a proof of complete logical function bodies, cold fragments, or exhaustive function coverage.",
            "Private callees have no exact symbol names in this retained table. Inferred role labels do not identify original source functions.",
            "Direct-edge inventory omits conditional cross-function edges, indirect calls, and transitive callees; unreviewed targets remain unresolved.",
            "The reported instructions come from the installed file at unslid addresses; live patches, relocated memory, scheduling, rights ownership, and runtime results were not observed.",
            "No kernel code was executed or attached, no protected process was attached, and no installed OS component was changed.",
            "Prior REA Mach-O metadata is reused by exact digest. New bounded disassembly is from Apple otool and is not a canonical REA function dossier.",
            "Apple binaries, derived carriers, raw disassembly, and captured SDK headers remain machine-local; public output contains original explanations and identities.",
        ],
    }
    report["evidenceId"] = "absolute-mach-kernel-sha256:" + sha(json.dumps(report, sort_keys=True).encode())
    save(REPORT, json_bytes(report), args.check)
    print(json.dumps({"status": "verified" if args.check else "captured",
        "evidenceId": report["evidenceId"], "kernelSourceVersion": image.source_version,
        "spans": len(functions), "codeBytes": report["coverage"]["selectedCodeBytes"],
        "report": relative(REPORT)}, indent=2))


if __name__ == "__main__":
    main()
