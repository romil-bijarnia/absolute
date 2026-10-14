#!/usr/bin/env python3
"""Capture SDK ABI declarations and bounded behavior of kernel objects we own."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parent.parent


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, *, timeout=60):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)


def relevant(item):
    targets = item.get("targets")
    return targets is None or "arm64e-macos" in targets


def summarize_library(library):
    exports = {}
    for group in library.get("exported_symbols", []):
        if not relevant(group):
            continue
        for category in ("data", "text"):
            for kind, names in group.get(category, {}).items():
                if isinstance(names, list):
                    exports.setdefault(category + "." + kind, set()).update(names)
    names = sorted({name for values in exports.values() for name in values})
    return {
        "install_names": [item["name"] for item in library.get("install_names", []) if relevant(item)],
        "targets": [item["target"] for item in library.get("target_info", [])],
        "versions": [item["version"] for item in library.get("current_versions", []) if relevant(item)],
        "symbol_count": len(names),
        "symbol_categories": {key: len(values) for key, values in sorted(exports.items())},
        "symbol_names_sha256": hashlib.sha256(("\n".join(names) + "\n").encode()).hexdigest(),
        "reexports": sorted({name for item in library.get("reexported_libraries", [])
                            if relevant(item) for name in item["names"]}),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("the reference capture must run on macOS")
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = PROJECT / "research/local/kernel-abi" / timestamp
    output.mkdir(parents=True, exist_ok=False)
    sdk = Path(run(["xcrun", "--show-sdk-path"]).stdout.decode().strip())
    settings = json.loads((sdk / "SDKSettings.json").read_text())
    host = {name: run(["sw_vers", option]).stdout.decode().strip()
            for name, option in [("version", "-productVersion"), ("build", "-buildVersion")]}
    kernel = run(["sysctl", "-n", "kern.version"]).stdout.decode().strip()
    macro_command = [
        "xcrun", "clang", "-dM", "-E", "-x", "c", "-D__APPLE_API_PRIVATE=1",
        "-isysroot", str(sdk), "-include", "sys/syscall.h", "/dev/null",
    ]
    macro_result = run(macro_command)
    (output / "syscall-macros.txt").write_bytes(macro_result.stdout)
    all_values = [
        {"name": name, "number": int(value)}
        for name, value in re.findall(r"^#define\s+SYS_(\w+)\s+(\d+)\s*$",
                                     macro_result.stdout.decode(), re.MULTILINE)
    ]
    syscall_limit = next((item["number"] for item in all_values if item["name"] == "MAXSYSCALL"), None)
    syscalls = sorted([item for item in all_values if item["name"] not in {"MAXSYSCALL", "NUMSYSCALLS"}],
                      key=lambda item: (item["number"], item["name"]))
    (output / "syscalls.json").write_text(json.dumps(syscalls, indent=2) + "\n")
    declarations = []
    for relative in ["usr/lib/libSystem.tbd", "usr/lib/libobjc.tbd",
                     "usr/lib/libc++.tbd", "usr/lib/libc++abi.tbd"]:
        source = sdk / relative
        if not source.is_file():
            declarations.append({"source": relative, "available": False})
            continue
        destination = output / (source.stem + ".arm64e.json")
        run(["xcrun", "llvm-readtapi", "-extract", "--arch=arm64e", "--filetype=tbd-v5",
             str(source), "-o", str(destination)])
        tree = json.loads(destination.read_text())
        libraries = [tree["main_library"], *tree.get("libraries", [])]
        declarations.append({
            "source": relative, "available": True, "sha256": digest(source),
            "converted_sha256": digest(destination),
            "libraries": [summarize_library(library) for library in libraries],
        })
    source = PROJECT / "script/research_kernel_probe.c"
    runtime = None
    if not args.static_only:
        binary = output / "kernel-probe"
        run(["xcrun", "clang", "-Wall", "-Wextra", "-Werror", "-O2",
             str(source), "-o", str(binary)])
        completed = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        (output / "runtime.json").write_bytes(completed.stdout)
        (output / "runtime.stderr.log").write_bytes(completed.stderr)
        runtime = {
            "source_sha256": digest(source), "binary_sha256": digest(binary),
            "exit_code": completed.returncode,
            "result": json.loads(completed.stdout),
            "scope": "Fresh owned process: Mach ports/messages, virtual memory, semaphores, pipe/kqueue, monotonic time.",
        }
    summary = {
        "schema": 1, "host": host, "kernel_version": kernel,
        "sdk": {"name": settings.get("CanonicalName"), "version": settings.get("Version"),
                "settings_sha256": digest(sdk / "SDKSettings.json")},
        "script_sha256": digest(__file__),
        "local_capture": str(output.relative_to(PROJECT)),
        "syscalls": {
            "evidence_type": "preprocessed-sdk-declarations",
            "header": "usr/include/sys/syscall.h",
            "header_sha256": digest(sdk / "usr/include/sys/syscall.h"),
            "macro_output_sha256": digest(output / "syscall-macros.txt"),
            "declared_name_count": len(syscalls),
            "distinct_number_count": len({item["number"] for item in syscalls}),
            "maximum_defined_number": max(item["number"] for item in syscalls),
            "maximum_syscall_constant": syscall_limit,
            "entries": syscalls,
        },
        "libraries": declarations,
        "runtime": runtime,
        "limitations": [
            "SDK declarations describe a build interface; they do not prove installed implementation or behavior.",
            "TBD v4 to v5 conversion preserves symbol declarations but cannot recover function-versus-data classification.",
            "The macro table is not proof that every number has an implemented or available kernel handler.",
            "Runtime checks exercise only this owned process and the specific operations recorded.",
            "No kernel implementation, scheduler, cross-process IPC, exception delivery or syscall emulator is reconstructed here.",
        ],
    }
    identity = json.dumps(summary, sort_keys=True, separators=(",", ":")).encode()
    summary["evidence_id"] = "absolute-kernel-abi-sha256:" + hashlib.sha256(identity).hexdigest()
    (output / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    (PROJECT / "research/kernel-abi-findings.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "evidence_id": summary["evidence_id"], "sdk": summary["sdk"]["name"],
        "syscall_names": len(syscalls),
        "library_declarations": sum(len(item.get("libraries", [])) for item in declarations),
        "runtime_checks": runtime["result"]["check_count"] if runtime else None,
        "runtime_passed": runtime["result"]["passed"] if runtime else None,
    }, indent=2))
    if runtime and (runtime["exit_code"] or not runtime["result"]["passed"]):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
