#!/usr/bin/env python3
"""Build the research coverage index from retained public evidence summaries."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
RESEARCH = ROOT / "research"
INPUTS = {
    "scope": "scope.json",
    "inventory": "system-inventory.json",
    "firmware": "boot-firmware-findings.json",
    "monitors": "boot-monitor-findings.json",
    "kernel": "kernel-abi-findings.json",
    "graphics": "graphics-findings.json",
    "native": "native-code-findings.json",
    "cache": "shared-cache-findings.json",
    "implementation": "implementation-verification.json",
    "mach_messages": "mach-message-findings.json",
    "mach_kernel": "mach-kernel-findings.json",
    "mach_compatibility": "mach-compatibility.json",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def generate():
    data, inputs = {}, []
    for key, name in INPUTS.items():
        raw = (RESEARCH / name).read_bytes()
        data[key] = json.loads(raw)
        inputs.append({"file": name, "sha256": sha(raw)})
    scope, inventory = data["scope"], data["inventory"]
    for subsystem in scope["subsystems"]:
        for name in subsystem["reports"]:
            if not (RESEARCH / name).is_file():
                raise ValueError("Missing subsystem report: " + name)
    verification = data["implementation"]
    source_paths = {
        str(path.relative_to(ROOT))
        for directory in ["Sources", "Tests", "linux/Sources"]
        for path in (ROOT / directory).rglob("*")
        if path.is_file() and path.suffix in {".swift", ".c", ".h", ".m", ".mm", ".cc", ".cpp", ".hpp", ".modulemap", ".json"}
    }
    source_paths.update({
        "Package.swift", "linux/Package.swift", "script/check_core.sh",
        "script/check_linux.sh", "script/check_linux_desktop.py",
        "script/build_and_run.sh", "script/run_linux.sh",
        "linux/container/Containerfile", "linux/container/start-desktop.sh",
    })
    if source_paths != set(verification["source_files_sha256"]):
        raise ValueError("Implementation source membership changed; refresh verification")
    for name, expected in verification["source_files_sha256"].items():
        if sha((ROOT / name).read_bytes()) != expected:
            raise ValueError("Implementation verification is stale for " + name)
    kernel_result = data["kernel"]["runtime"]["result"]
    if (not kernel_result["passed"] or not all(kernel_result["checks"].values())
            or kernel_result["check_count"] != len(kernel_result["checks"])):
        raise ValueError("Kernel reference checks did not all pass")
    graphics_probes = [
        value for value in data["graphics"]["runtimeProbe"].values()
        if isinstance(value, dict) and "status" in value
    ]
    if not graphics_probes or any(item["status"] != "passed" for item in graphics_probes):
        raise ValueError("Graphics reference checks did not all pass")
    for platform in ("macos", "linux"):
        for name in ("cli", "desktop", "restart"):
            record = verification[platform].get(name)
            if record and (not record["passed"] or not all(record["checks"].values())
                           or record["check_count"] != len(record["checks"])):
                raise ValueError("Invalid implementation verification: " + platform + "/" + name)
    if any(item["status"] == "complete" for item in scope["subsystems"]):
        raise ValueError("A new subsystem completion claim needs explicit contract-level validation")
    reference = data["mach_messages"]
    oracle = reference["oracle"]
    fixture = ROOT / "Tests/AbsoluteMachTests/Fixtures/mach-message-reference.json"
    if fixture.read_bytes() != (RESEARCH / INPUTS["mach_messages"]).read_bytes():
        raise ValueError("Mach test fixture and native reference differ")
    if (not oracle["passed"] or not reference["repeatability"]["identical"]
            or oracle["scenario_count"] != len(oracle["scenarios"])
            or any(not item["passed"] for item in oracle["scenarios"])):
        raise ValueError("Mach native reference checks did not pass")
    if data["mach_compatibility"]["reference_evidence_id"] != reference["evidence_id"]:
        raise ValueError("Mach conformance references another capture")
    for name, expected in data["mach_compatibility"]["source_files_sha256"].items():
        if sha((ROOT / name).read_bytes()) != expected:
            raise ValueError("Mach conformance is stale for " + name)

    metrics = {
        "readable_regular_file_paths": inventory["file_count"],
        "mach_o_file_paths": inventory["native_file_count"],
        "shared_cache_images": data["cache"]["imageCount"],
        "shared_cache_dependency_edges": data["cache"]["dependencyEdgeCount"],
        "launch_job_declarations": inventory["launch_job_count"],
        "mach_service_declarations": inventory["declared_mach_service_count"],
        "firmware_and_boot_artifact_records": sum(data["firmware"]["counts"].values()),
        "rea_function_dossiers": (
            data["native"]["coverage"]["functionDossiers"]
            + len(data["graphics"]["windowServer"]["nativeFunctions"])
            + sum(len(item["functions"]) for item in data["monitors"]["images"])
        ),
        "iosurface_and_kernel_library_functions_selected": (
            len(data["graphics"]["iosurfaceCode"]["selectedFunctions"])
            + len(data["cache"]["kernelImage"]["selectedFunctions"])
        ),
        "filesystem_runtime_cases_captured": data["native"]["coverage"]["runtimeCases"],
        "kernel_reference_checks_passed": len(kernel_result["checks"]),
        "graphics_reference_probes_passed": len(graphics_probes),
        "mach_native_scenarios": oracle["scenario_count"],
        "mach_native_checks": oracle["check_count"],
        "mach_reference_operations": sum(len(item["operations"]) for item in oracle["scenarios"]),
        "kernel_send_function_start_spans": data["mach_kernel"]["coverage"]["functionStartSpansDisassembled"],
    }
    summary = {
        "schema": 1, "overall_status": "in_progress", "completion_percentage": None,
        "reference_host": inventory["host"], "objective": scope["objective"],
        "completion_rule": scope["completion_rule"], "metrics": metrics,
        "subsystems": scope["subsystems"], "inputs": inputs,
        "limits": [
            "Inventory, static-code analysis, observed behavior and compatible implementation are separate measures.",
            "Counts overlap between filesystem, cache, firmware and SDK records and cannot be added into whole-OS coverage.",
            "A function dossier can contain unresolved flows and decompiler limitations; it does not mean the full function is understood.",
            "All subsystem scopes still contain unresolved work. No standalone macOS-compatible OS or firmware replacement is claimed.",
        ],
    }
    title = {
        "readable_regular_file_paths": "Regular file paths inventoried",
        "mach_o_file_paths": "Mach-O file paths identified",
        "shared_cache_images": "Shared-cache image headers verified",
        "shared_cache_dependency_edges": "Shared-cache dependency declarations",
        "launch_job_declarations": "Launchd job declarations",
        "mach_service_declarations": "Mach-service declarations",
        "firmware_and_boot_artifact_records": "Firmware/boot artifact records",
        "rea_function_dossiers": "Canonical REA function dossiers",
        "iosurface_and_kernel_library_functions_selected": "Selected IOSurface/libsystem_kernel functions inspected",
        "filesystem_runtime_cases_captured": "Filesystem runtime cases captured",
        "kernel_reference_checks_passed": "Owned-process kernel reference checks passed",
        "graphics_reference_probes_passed": "Headless graphics reference probes passed",
        "mach_native_scenarios": "Mach-message reference scenarios",
        "mach_native_checks": "Mach-message native checks passed",
        "mach_reference_operations": "Recorded Mach operations replayed per pass",
        "kernel_send_function_start_spans": "Selected kernel-send function-start spans inspected",
    }
    lines = [
        "# System research coverage", "",
        "**Overall status: in progress. Full macOS reverse engineering is incomplete.**", "",
        "The requested scope includes graphics, boot and firmware. The current",
        "reference is macOS " + inventory["host"]["version"] + ", build " + inventory["host"]["build"] + ".",
        "This index is generated from the linked reports and their hashed JSON records.", "",
        "## Measured work", "",
        "| Measurement | Count |", "| --- | ---: |",
        *["| " + title[key] + " | " + format(value, ",") + " |" for key, value in metrics.items()], "",
        "These counts measure different kinds of work and overlap. They do not form",
        "a completion percentage. File names, export names and dependency edges do",
        "not establish recovered behavior. Native-code dossiers retain unresolved",
        "flows, inferred types and provider limitations described in their reports.", "",
        "The filesystem capture also records " + str(inventory["error_count"]) + " read denials.",
        "Shared-cache and firmware captures have separate boundaries and identities.", "",
        "## What changed in Absolute", "",
        "The file service now preserves dangling-link identity and separates",
        "literal link destinations from successful target resolution. Symbolic-link",
        "traversal survives CLI parsing, navigation, snapshots and session-state paths.",
        "See [NATIVE-CODE.md](NATIVE-CODE.md) for the observed contract and remaining limits.", "",
        "The separate AbsoluteMach component now implements the measured in-process",
        "inline-message subset. Its tests replay the independent native reference",
        "with two name assignments on both hosts, comparing returned bytes, rights,",
        "queue state, timeouts and trailers. See",
        "[MACH-COMPATIBILITY.md](MACH-COMPATIBILITY.md).", "",
        "| Verification | macOS | Linux |", "| --- | ---: | ---: |",
        "| Unit tests | " + str(verification["macos"]["unit_tests_passed"]) + " | "
            + str(verification["linux"]["unit_tests_passed"]) + " |",
        "| CLI integration checks | " + str(verification["macos"]["cli"]["check_count"]) + " | "
            + str(verification["linux"]["cli"]["check_count"]) + " |",
        "| Desktop and restart checks | "
            + str(verification["macos"]["desktop"]["check_count"] + verification["macos"]["restart"]["check_count"]) + " | "
            + str(verification["linux"]["desktop"]["check_count"]) + " |", "",
        "The [verification record](implementation-verification.json) binds these",
        "results to source hashes and retained local reports. The GTK host still",
        "runs in a development VM; it is not a self-contained bootable OS image.", "",
        "## Subsystems still open", "",
        "| Subsystem | Current depth | Evidence | Next unresolved boundary |",
        "| --- | --- | --- | --- |",
    ]
    for item in scope["subsystems"]:
        depth = "Partial investigation" if item["status"] == "partial" else "Inventory only"
        references = ", ".join("[" + Path(name).stem + "](" + name + ")" for name in item["reports"])
        lines.append("| " + item["name"] + " | " + depth + " | " + references + " | " + item["remaining"][0] + " |")
    lines += [
        "", "The full open-question list is in [scope.json](scope.json). A component",
        "can be completed only for a stated target and contract after its behavior",
        "is established, implemented in Absolute, and checked against the reference.",
        "No subsystem is marked complete by this pass.", "",
        "## Reproduce and extend", "",
        "Investigation-specific commands appear in each report. Run",
        "python3 script/research_status.py after updating the evidence and verification",
        "record; add --check to verify that this index is current without changing it.",
        "The generator checks report links, source hashes and recorded check results.", "",
        "Complete captures, extracted code and decompiler output remain in the",
        "Git-ignored research/local directory. Public reports preserve identities,",
        "original explanations, test contracts and explicit gaps.",
        "",
    ]
    return json.dumps(summary, indent=2, sort_keys=True) + "\n", "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    summary, markdown = generate()
    for name, text in [("coverage.json", summary), ("SYSTEM-COVERAGE.md", markdown)]:
        destination = RESEARCH / name
        if args.check:
            if not destination.is_file() or destination.read_text() != text:
                raise ValueError(name + " is stale; regenerate the coverage index")
        else:
            destination.write_text(text)
    print("Research index verified." if args.check else "Research index updated; all subsystem scopes remain open.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print("research_status: " + str(error), file=sys.stderr)
        raise SystemExit(1)
