#!/usr/bin/env python3
"""Analyze entry routines of the locally decoded SPTM and TXM firmware images."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "research/local/boot-firmware"
NODE = ROOT / "tools/node_modules/node/bin/node"
REA = ROOT / "tools/node_modules/rea-agents/scripts/rea.mjs"
IMAGES = ["sptm.t6031.release.decoded.bin", "txm.macosx.release.decoded.bin"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def retain(path, data):
    if path.is_file():
        previous = path.read_bytes()
        if previous != data:
            archive = path.with_name(path.stem + ".previous-" + sha(previous)[:16] + path.suffix)
            if not archive.exists():
                archive.write_bytes(previous)
    path.write_bytes(data)


def analyze_function(binary, identity, address, role):
    stem = binary.name
    destination = LOCAL / (stem + "." + role + "-function.json")
    reuse = False
    if destination.is_file():
        data = json.loads(destination.read_text()).get("data", {})
        reuse = (data.get("subject", {}).get("digest", {}).get("sha256") == identity
                 and bool(data.get("evidence_id"))
                 and data.get("normalized_result", {}).get("procedure", {}).get("address") == address)
    if not reuse:
        environment = os.environ.copy()
        environment.setdefault("GHIDRA_INSTALL_DIR", "/opt/homebrew/opt/ghidra/libexec")
        environment.setdefault("JAVA_HOME", "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
        arguments = [
            str(NODE), str(REA), "function", str(binary), address, "--provider", "ghidra",
            "--snapshot", str(LOCAL / (stem + ".snapshot.json")), "--format", "json", "--full-output",
        ]
        result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=environment, timeout=240)
        retain(destination, result.stdout)
        destination.with_suffix(".stderr.log").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError(stem + ": native analysis failed; inspect the retained diagnostic")
    envelope = json.loads(destination.read_text())
    data = envelope.get("data", {})
    if not data.get("evidence_id") or data.get("error"):
        raise RuntimeError(stem + ": canonical function evidence is unavailable")
    result = data["normalized_result"]
    print(stem + ": " + data["evidence_id"], flush=True)
    return {
        "role": role, "evidence_id": data["evidence_id"],
        "evidence_sha256": sha(destination.read_bytes()),
        "procedure": {key: result["procedure"][key] for key in ["name", "address", "classification", "body"]},
        "callees": [{"name": item["name"], "address": item["address"]} for item in result["callees"]],
        "provider_limitations": data.get("limitations", []),
    }


def inspect(stem):
    binary = LOCAL / stem
    if not binary.is_file():
        raise RuntimeError("Run script/research_boot_firmware.py --rea first.")
    identity = sha(binary.read_bytes())
    commands = subprocess.run(["xcrun", "otool", "-l", str(binary)],
                              check=True, stdout=subprocess.PIPE, timeout=30).stdout
    retain(LOCAL / (stem + ".load-commands.txt"), commands)
    match = re.search(rb"\bpc\s+(0x[0-9a-fA-F]+)", commands)
    if not match:
        raise RuntimeError(stem + ": no thread-state PC; review the image before selecting code")
    entry = match.group(1).decode()
    function = analyze_function(binary, identity, entry, "entry")
    functions = [function]
    target = function["procedure"]["classification"].get("thunk_target")
    if target and target != entry:
        functions.append(analyze_function(binary, identity, target, "entry-target"))
    return {"image": stem, "sha256": identity, "entry_address": entry,
            "load_commands_sha256": sha(commands), "functions": functions}


def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        records = list(executor.map(inspect, IMAGES))
    report = {
        "schema": 1, "evidence_type": "static-native-function-analysis",
        "scope": "LC_UNIXTHREAD entry routine in each decoded image, plus one direct SPTM entry thunk target.",
        "images": records,
        "limitations": [
            "The firmware images were not executed.",
            "Recovered disassembly and pseudocode are analysis artifacts, not original source.",
            "Entry analysis does not establish complete SPTM/TXM policy or boot behavior.",
        ],
    }
    (ROOT / "research/boot-monitor-findings.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
