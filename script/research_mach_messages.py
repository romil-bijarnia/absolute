#!/usr/bin/env python3
"""Capture a bounded Mach-message oracle independently of Absolute's IPC model."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "script/research_mach_messages.c"
LOCAL = ROOT / "research/local/mach-messages"
FIXTURE = ROOT / "Tests/AbsoluteMachTests/Fixtures/mach-message-reference.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def read_command(arguments):
    return subprocess.check_output(arguments, text=True, timeout=20).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repetitions", type=int, default=2, choices=range(1, 9))
    parser.add_argument("--capture-only", action="store_true", help="retain evidence without updating the public report or test fixture")
    arguments = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("the reference oracle must run on macOS")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = LOCAL / stamp
    output.mkdir(parents=True, exist_ok=False)
    source = output / SOURCE.name
    source.write_bytes(SOURCE.read_bytes())
    copied_script = output / Path(__file__).name
    copied_script.write_bytes(Path(__file__).read_bytes())
    sdk = Path(read_command(["xcrun", "--show-sdk-path"]))
    sdk_settings = json.loads((sdk / "SDKSettings.json").read_text())
    compiler = read_command(["xcrun", "clang", "--version"])
    binary = output / "mach-message-probe"
    command = ["xcrun", "clang", "-Wall", "-Wextra", "-Werror", "-O2", "-isysroot", str(sdk), str(source), "-o", str(binary)]
    compiled = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    (output / "compile.stdout.log").write_bytes(compiled.stdout)
    (output / "compile.stderr.log").write_bytes(compiled.stderr)
    if compiled.returncode:
        raise RuntimeError(f"Oracle compilation failed; diagnostic retained at {output}")
    references, records = [], []
    for index in range(1, arguments.repetitions + 1):
        completed = subprocess.run([str(binary), "--json"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        path = output / f"runtime-{index}.json"
        path.write_bytes(completed.stdout)
        (output / f"runtime-{index}.stderr.log").write_bytes(completed.stderr)
        value = json.loads(completed.stdout)
        records.append({"file": path.name, "sha256": sha(completed.stdout), "bytes": len(completed.stdout), "exit_code": completed.returncode})
        references.append(value)
    passed = all(record["exit_code"] == 0 and value["passed"] for record, value in zip(records, references))
    identical = all(value == references[0] for value in references)
    report = {
        "schema": 1,
        "evidence_type": "owned-process-runtime-reference",
        "provenance": {
            "capture": str(output.relative_to(ROOT)),
            "host": {"version": read_command(["sw_vers", "-productVersion"]), "build": read_command(["sw_vers", "-buildVersion"]), "kernel": read_command(["sysctl", "-n", "kern.version"])},
            "sdk": {"name": sdk_settings.get("CanonicalName"), "version": sdk_settings.get("Version"), "settings_sha256": sha((sdk / "SDKSettings.json").read_bytes())},
            "source": {"file": str(SOURCE.relative_to(ROOT)), "sha256": sha(source.read_bytes())},
            "script": {"file": "script/research_mach_messages.py", "sha256": sha(copied_script.read_bytes())},
            "binary": {"file": binary.name, "sha256": sha(binary.read_bytes())},
            "compiler": {"version": compiler, "command": [argument.replace(str(sdk), "<sdk>").replace(str(output), "<capture>") for argument in command]},
            "headers": [{"file": "usr/include/mach/" + name, "sha256": sha((sdk / "usr/include/mach" / name).read_bytes())}
                        for name in ["message.h", "port.h", "mach_port.h", "kern_return.h"]],
            "runs": records,
        },
        "repeatability": {"runs": arguments.repetitions, "identical": identical, "all_checks_passed": passed},
        "oracle": references[0],
        "limitations": [
            "All ports belong to a single fresh process. This does not establish cross-process transfer, notification, scheduling, or security policy behavior.",
            "Messages contain inline bytes only. Reply and voucher names are null; complex descriptors, out-of-line memory, port arrays and vouchers are not exercised.",
            "Every send and receive uses an explicit zero timeout. Blocking, interruption, concurrent destruction and priority inheritance are outside this contract.",
            "Receive storage is physically 256 bytes and is zero-initialized. Declared capacities are bounded independently. Unchanged zero fields on errors are not proof that the kernel clears arbitrary preexisting buffer contents.",
            "Normalized bytes substitute scenario-local role tokens in the three header port-name fields. Remaining observed header and body bytes are unmodified. These are not actual task port names.",
            "For sends shorter than a header, normalized_bytes records the complete initialized 24-byte header for inspection; send_size remains the actual argument passed to Mach.",
            "Receive normalized_storage_prefix_64_bytes is a snapshot of owned storage, not a claim that all 64 bytes were written by the kernel. Structured trailers are included only when their observed size and declared capacity establish their presence.",
            "Port-state fields are meaningful only when their associated query status succeeds. A null queue_count_after means no receive queue could be inspected for that name.",
            "The oracle is compiled from this repository's C source and calls installed Mach APIs. It does not import or execute Absolute's IPC implementation.",
            "The reference is for this host/kernel/SDK build and tested sizes/dispositions. It is not a complete Mach specification or evidence of native macOS application compatibility.",
        ],
    }
    report["evidence_id"] = "absolute-mach-messages-sha256:" + sha(encoded(report))
    serialized = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode()
    (output / "reference.json").write_bytes(serialized)
    (LOCAL / "latest.json").write_text(json.dumps({"directory": str(output.relative_to(ROOT)), "evidence_id": report["evidence_id"]}, indent=2) + "\n")
    if not passed or not identical:
        raise RuntimeError(f"Oracle checks or normalized repeatability failed; captures retained at {output}")
    if not arguments.capture_only:
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_bytes(serialized)
        (ROOT / "research/mach-message-findings.json").write_bytes(serialized)
    print(json.dumps({"evidence_id": report["evidence_id"], "capture": str(output.relative_to(ROOT)), "scenarios": references[0]["scenario_count"], "checks": references[0]["check_count"], "identical_runs": arguments.repetitions if identical else 0, "fixture": str(FIXTURE.relative_to(ROOT)) if not arguments.capture_only else None}, indent=2))


if __name__ == "__main__":
    main()
