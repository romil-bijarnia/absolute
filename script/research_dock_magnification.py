#!/usr/bin/env python3
"""Recover the Dock magnification ("fish") model from the installed Dock.app.

The installed Dock executable is copied beneath research/local/dock-magnification
and analysed statically with the project REA runtime and a caller-provided
Ghidra. Nothing is executed, attached to or modified; the running Dock is never
touched. Successful REA records are reused on later runs when the copied
binary's identity is unchanged. Requires the project Node/REA installation.
"""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "research/local/dock-magnification"
NODE = ROOT / "tools/node_modules/node/bin/node"
REA = ROOT / "tools/node_modules/rea-agents/scripts/rea.mjs"
TARGET = Path("/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock")
IMAGE_BASE = 0x100000000

# Procedures of build 26A5421a that carry the behaviour. Other builds need a new pass.
PROCEDURES = {
    "0x100011b54": "fish state: fishCenter from the pointer, fishSize, realScale and currentFish",
    "0x100011de8": "per-tile layout: both tile edges displaced through the sine profile",
    "0x1000128f0": "bar frame: bar edges displaced through the same profile plus distanceSides",
    "0x10007e930": "-[DockBar updateWithContext:showDockWindow:transaction:], the update loop",
    "0x1000502b4": "DockFloatAnimatedProperty time step: linear or cosine progress, then interpolate:",
}
CONSTANT_GETTERS = {
    "fSize": "0x10025324c",
    "fishSpeed": "0x100253240",
}
SEARCH_PATTERN = "fSize|fishSpeed|Fish|DockFloatAnimatedProperty"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def vfp_expand_imm_single(imm8):
    """ARM64 VFPExpandImm for a 32-bit float immediate."""
    sign = (imm8 >> 7) & 1
    b = (imm8 >> 6) & 1
    exponent = ((1 - b) << 7) | ((0b11111 if b else 0) << 2) | ((imm8 >> 4) & 3)
    fraction = (imm8 & 0xF) << 19
    return struct.unpack("<f", struct.pack("<I", (sign << 31) | (exponent << 23) | fraction))[0]


def read_word(data, address):
    return struct.unpack_from("<I", data, address - IMAGE_BASE)[0]


def decode_float_getter(data, address):
    """Decode a getter that returns a float literal in s0 from its first instruction."""
    word = read_word(data, address)
    if (word & 0xFFE01FE0) == 0x1E201000:  # FMOV (scalar, immediate), single precision
        return {"instruction": f"{word:08x}", "form": "fmov s0, #imm8", "value": vfp_expand_imm_single((word >> 13) & 0xFF)}
    if (word & 0xFF800000) == 0x52800000:  # MOVZ (32-bit)
        imm16 = (word >> 5) & 0xFFFF
        shift = ((word >> 21) & 3) * 16
        bits = imm16 << shift
        next_word = read_word(data, address + 4)
        if (next_word & 0xFFFFFC00) == 0x1E270000:  # FMOV s, w
            return {"instruction": f"{word:08x} {next_word:08x}", "form": "mov w, #bits; fmov s0, w", "value": struct.unpack("<f", struct.pack("<I", bits))[0]}
    raise RuntimeError(f"Unrecognised getter encoding at {hex(address)}: {word:08x}")


def rea_record(output, name, slice_sha):
    path = output / f"dock-{name}.json"
    if not path.exists():
        return None
    try:
        envelope = json.loads(path.read_text())
        evidence = envelope["data"]
        if envelope.get("ok") and evidence.get("evidence_id") and evidence["subject"]["digest"]["sha256"] == slice_sha:
            return evidence
    except (KeyError, TypeError, ValueError):
        pass
    return None


def run_rea(output, environment, sliced, name, command, *arguments):
    path = output / f"dock-{name}.json"
    args = [str(NODE), str(REA), command, str(sliced), *arguments,
            "--provider", "ghidra", "--snapshot", str(output / "dock-snapshot.json"), "--format", "json", "--full-output"]
    with path.open("w") as stdout, path.with_suffix(".stderr.log").open("w") as stderr:
        completed = subprocess.run(args, env=environment, stdout=stdout, stderr=stderr, timeout=1800)
    envelope = json.loads(path.read_text())
    if completed.returncode != 0 or not envelope.get("ok") or not envelope.get("data", {}).get("evidence_id"):
        raise RuntimeError(f"REA failed; full output retained at {path}")
    return envelope["data"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=ROOT / "research/dock-magnification-findings.json")
    parser.add_argument("--skip-rea", action="store_true", help="only rebuild the report from retained records")
    args = parser.parse_args()
    output = args.output
    output.mkdir(parents=True, exist_ok=True)

    source_sha = digest(TARGET)
    identity_path = output / "identity.json"
    if identity_path.exists() and json.loads(identity_path.read_text()).get("sha256") != source_sha:
        raise RuntimeError("Installed Dock changed; choose a new --output directory")
    sliced = output / "Dock.arm64e"
    if not sliced.exists():
        info = subprocess.run(["/usr/bin/lipo", str(TARGET), "-info"], capture_output=True, text=True, check=True).stdout
        if "Non-fat" in info:
            shutil.copyfile(TARGET, sliced)
        else:
            subprocess.run(["/usr/bin/lipo", str(TARGET), "-thin", "arm64e", "-output", str(sliced)], check=True)
    slice_sha = digest(sliced)
    host = subprocess.run(["/usr/bin/sw_vers"], capture_output=True, text=True, check=True).stdout.strip()
    save(identity_path, {"schema": 1, "target": str(TARGET), "sha256": source_sha, "bytes": TARGET.stat().st_size,
                         "copy": str(sliced), "copySha256": slice_sha, "host": host, "recordedAt": now()})

    environment = dict(os.environ)
    environment.setdefault("GHIDRA_INSTALL_DIR", "/opt/homebrew/opt/ghidra/libexec")
    environment.setdefault("JAVA_HOME", "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")

    def record(name, command, *arguments):
        evidence = rea_record(output, name, slice_sha)
        if evidence is None:
            if args.skip_rea:
                raise RuntimeError(f"No retained record for {name}; run without --skip-rea")
            evidence = run_rea(output, environment, sliced, name, command, *arguments)
        return evidence

    overview = record("overview", "inspect")
    procedures = {}
    for address, role in PROCEDURES.items():
        evidence = record(f"fn-{address[2:]}", "function", address)
        result = evidence["normalized_result"]
        procedures[address] = {
            "role": role,
            "ghidraName": result["procedure"].get("name"),
            "bodyBytes": result["procedure"].get("body", {}).get("total_bytes"),
            "callers": [c.get("name") or c.get("address") for c in result.get("callers", [])],
            "evidenceId": evidence["evidence_id"],
        }
    search = record("search-fish", "search", "--kind", "procedures", "--mode", "regex", "--pattern", SEARCH_PATTERN)
    named = {m["value"]: m["address"] for m in search["normalized_result"] if isinstance(m, dict) and "value" in m}

    data = sliced.read_bytes()
    constants = {}
    for name, address in CONSTANT_GETTERS.items():
        found = named.get(f"DockBar::{name}")
        if found and found != address:
            raise RuntimeError(f"Ghidra places DockBar::{name} at {found}, expected {address}")
        decoded = decode_float_getter(data, int(address, 16))
        constants[name] = {"getter": f"-[DockBar {name}]", "address": address, **decoded}
    pi_address = 0x1003086d0
    constants["pi"] = {"address": hex(pi_address), "value": struct.unpack_from("<d", data, pi_address - IMAGE_BASE)[0],
                       "note": "double literal used by the fish-state normaliser; the per-tile profile uses the float literal at 0x1003086e8"}

    report = {
        "schema": 1,
        "recordedAt": now(),
        "host": host,
        "scope": "Static recovery of Dock magnification geometry and ramp timing from the installed Dock executable. No process was executed, attached to or modified.",
        "target": {"path": str(TARGET), "sourceSha256": source_sha, "sourceBytes": TARGET.stat().st_size,
                   "copySha256": slice_sha, "architecture": "arm64e", "derivation": "byte copy of the thin arm64e executable"},
        "providers": {"rea": "6.4.0", "ghidra": "12.1.3", "overviewEvidenceId": overview["evidence_id"],
                      "procedureCount": overview["normalized_result"].get("procedure_count"), "searchEvidenceId": search["evidence_id"]},
        "procedures": procedures,
        "namedProcedures": {k: v for k, v in sorted(named.items()) if k.startswith("DockBar::") or k.startswith("DockFloatAnimatedProperty::")},
        "constants": constants,
        "model": {
            "fishSize": "fSize * tileSize",
            "realScale": "fish * (largeSize - tileSize) / 2 / sin(pi * tileSize / (4 * fishSize))",
            "currentFish": "fish * (largeSize - tileSize)",
            "profile": "S(d) = -1 if d <= -fishSize; 1 if d >= fishSize; sin(pi * d / (2 * fishSize)) otherwise",
            "displacement": "D(x) = x + realScale * S(x - fishCenter)",
            "tileExtent": "[D(position), D(position + width)] along the bar; size across the bar = D(centre + tileSize/2) - D(centre - tileSize/2)",
            "barExtent": "[D(barLeft) - distanceSides, D(barRight) + distanceSides]",
            "inactive": "realScale = currentFish = 0 when magnification is off or largeSize <= tileSize",
            "rampDurationMilliseconds": "floor(fishSpeed * ln(|sizeChange| / 2 + 1) + 1); moveSpeed while dragging",
            "rampProgress": "linear in time; DockFloatAnimatedProperty applies 0.5 - 0.5 cos(pi t) only when an easing function is attached, and no code attaches one",
        },
        "implementation": {"source": "Sources/AbsoluteCore/DockMagnification.swift", "tests": "Tests/AbsoluteCoreTests/DockMagnificationTests.swift"},
        "limitations": [
            "Static analysis only; the running Dock was not observed, so pointer sampling, frame timing and rendering were not measured.",
            "Dock arithmetic is single precision; the model uses double precision and the tests allow 0.01 pt of difference.",
            "Addresses are specific to build 26A5421a and must be rediscovered for another build.",
            "The externalFishTile and dragging paths are recorded but not modelled.",
        ],
    }
    save(args.report, report)
    print(f"wrote {args.report}")
    for name, value in constants.items():
        print(f"  {name} = {value['value']}")


if __name__ == "__main__":
    main()
