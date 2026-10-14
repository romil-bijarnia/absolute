#!/usr/bin/env python3
"""Inspect the installed readlink/stat code and capture isolated filesystem behavior.

All binary slices, pseudocode, disassembly, and runtime captures remain beneath
research/local/native-code. The inspected slice is never executed. Runtime
probes invoke only /usr/bin/readlink and /usr/bin/stat with our own fixtures.
Requires the existing project Node/REA installation and caller-provided Ghidra.
"""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "research/local/native-code"
NODE = ROOT / "tools/node_modules/node/bin/node"
REA = ROOT / "tools/node_modules/rea-agents/scripts/rea.mjs"
PROGRAMS = ("/usr/bin/readlink", "/usr/bin/stat")
PAYLOAD = b"absolute symlink fixture\n"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def main_entry(path):
    """Read LC_MAIN relative to the file-backed Mach-O segment; no fixed address."""
    data = path.read_bytes()
    if struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected a little-endian 64-bit thin Mach-O")
    position, text, entry = 32, None, None
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, length = struct.unpack_from("<II", data, position)
        if length < 8 or position + length > len(data):
            raise ValueError("Invalid Mach-O load command")
        if command == 0x19:
            name = data[position + 8:position + 24].split(b"\0", 1)[0]
            if name == b"__TEXT":
                address, _, offset = struct.unpack_from("<QQQ", data, position + 24)
                text = address - offset
        elif command == 0x80000028:
            entry = struct.unpack_from("<Q", data, position + 8)[0]
        position += length
    if text is None or entry is None:
        raise ValueError("No __TEXT/LC_MAIN mapping")
    return hex(text + entry)


def capture_native(output, refresh):
    target = Path(PROGRAMS[0])
    original_sha = digest(target)
    identity_path = output / "identity.json"
    if identity_path.exists():
        old = json.loads(identity_path.read_text())
        if old.get("sha256") != original_sha:
            raise RuntimeError("Installed binary changed; choose a new --output directory")
    sliced = output / "readlink.arm64e"
    if not sliced.exists():
        subprocess.run(["/usr/bin/lipo", str(target), "-thin", "arm64e", "-output", str(sliced)], check=True)
    slice_sha = digest(sliced)
    if identity_path.exists() and old.get("thinSha256") != slice_sha:
        raise RuntimeError("Retained slice identity changed; choose a new --output directory")
    save(identity_path, {
        "schema": 1, "target": str(target), "sha256": original_sha,
        "thinSlice": str(sliced), "thinSha256": slice_sha,
        "derivation": ["/usr/bin/lipo", str(target), "-thin", "arm64e", "-output", str(sliced)],
        "recordedAt": now(),
    })
    environment = dict(os.environ)
    environment.setdefault("GHIDRA_INSTALL_DIR", "/opt/homebrew/opt/ghidra/libexec")
    environment.setdefault("JAVA_HOME", "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
    snapshot = output / "readlink-snapshot.json"
    if refresh and snapshot.exists():
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        snapshot.rename(output / f"readlink-snapshot.previous-{stamp}.json")
    saved = {}
    if not refresh:
        for path in output.glob("readlink-*.json"):
            try:
                evidence = json.loads(path.read_text())["data"]
                if evidence["subject"]["digest"]["sha256"] != slice_sha:
                    continue
                result = evidence["normalized_result"]
                if evidence["operation"] == "analyze_function":
                    saved[result["procedure"]["address"]] = (path, evidence)
                elif evidence["operation"] == "binary_overview":
                    saved["overview"] = (path, evidence)
            except (KeyError, TypeError, ValueError):
                pass

    def rea(command, argument, key):
        if key in saved:
            return saved[key]
        path = output / ("readlink-overview.json" if key == "overview" else f"readlink-function-{key}.json")
        if path.exists():
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%f")
            path.rename(path.with_name(path.stem + f".previous-{stamp}.json"))
        args = [str(NODE), str(REA), command, str(sliced)]
        if argument is not None:
            args.append(argument)
        args += ["--provider", "ghidra", "--snapshot", str(output / "readlink-snapshot.json"), "--format", "json", "--full-output"]
        with path.open("w") as stdout, path.with_suffix(".stderr.log").open("w") as stderr:
            completed = subprocess.run(args, env=environment, stdout=stdout, stderr=stderr, timeout=240)
        envelope = json.loads(path.read_text())
        if completed.returncode != 0 or not envelope.get("ok") or not envelope.get("data", {}).get("evidence_id"):
            raise RuntimeError(f"REA failed; full output retained at {path}")
        evidence = envelope["data"]
        saved[key] = (path, evidence)
        return path, evidence

    overview_path, overview = rea("inspect", None, "overview")
    pending, visited, functions = [main_entry(sliced)], set(), []
    while pending:
        address = pending.pop(0)
        if address in visited:
            continue
        if len(visited) >= 12:
            raise RuntimeError("Bounded native analysis reached 12 functions; remaining queue needs review")
        visited.add(address)
        path, evidence = rea("function", address, address)
        result = evidence["normalized_result"]
        functions.append({
            "address": address, "name": result["procedure"]["name"],
            "ranges": result["procedure"]["body"]["ranges"],
            "bodyBytes": result["procedure"]["body"]["total_bytes"],
            "instructionCount": len(result.get("assembly", [])),
            "pseudocodePresent": bool(result.get("pseudocode")),
            "evidenceId": evidence["evidence_id"], "file": str(path.relative_to(ROOT)),
            "fileSha256": digest(path),
            "callees": [{"address": c["address"], "name": c["name"], "classification": c["classification"]} for c in result.get("callees", [])],
            "limitations": result.get("limitations", []),
        })
        for callee in result.get("callees", []):
            classification = callee.get("classification", {})
            if not classification.get("external") and not classification.get("thunk"):
                if callee["address"] not in visited:
                    pending.append(callee["address"])
        print(f"Native function {address}: {evidence['evidence_id']}", flush=True)
    save(output / "native-manifest.json", {
        "schema": 1, "recordedAt": now(), "sourceSha256": original_sha, "sliceSha256": slice_sha,
        "overview": {"evidenceId": overview["evidence_id"], "file": str(overview_path.relative_to(ROOT)), "sha256": digest(overview_path)},
        "scope": "Entry and reachable non-thunk functions identified by Ghidra; imported library bodies excluded",
        "functions": functions,
    })


def capture_runtime(output):
    fixture = Path(tempfile.mkdtemp(prefix="readlink-fixture-", dir=output))
    (fixture / "target.txt").write_bytes(PAYLOAD)
    (fixture / "target-dir/nested").mkdir(parents=True)
    (fixture / "target-dir/child.txt").write_bytes(b"child\n")
    links = {
        "file-link": "target.txt", "directory-link": "target-dir", "dangling-link": "missing.txt",
        "chain-link": "file-link", "dotdot-link": "target-dir/../target.txt",
        "absolute-link": str(fixture / "target.txt"), "loop-a": "loop-b", "loop-b": "loop-a",
        "missing-parent-link": "absent-directory/child.txt", "spaced link": "target.txt",
        "nested-link": "target-dir/nested", "non-directory-link": "target.txt/child",
    }
    for name, destination in links.items():
        (fixture / name).symlink_to(destination)
    cases = []

    def capture(case, program, args):
        process = subprocess.run([program, *args], cwd=fixture, env=dict(os.environ, LC_ALL="C"), stdin=subprocess.DEVNULL, capture_output=True, timeout=8)
        def normalized(data):
            return data.decode("utf-8", "backslashreplace").replace(str(fixture), "<fixture>")
        cases.append({
            "case": case, "program": program, "arguments": args,
            "exitCode": process.returncode, "stdout": normalized(process.stdout), "stderr": normalized(process.stderr),
            "stdoutHex": process.stdout.hex(), "stderrHex": process.stderr.hex(),
        })

    names = ["file-link", "directory-link", "dangling-link", "chain-link", "dotdot-link", "absolute-link", "loop-a", "missing-parent-link", "spaced link", "target.txt", "target-dir", "missing.txt", "non-directory-link", "nested-link/../child.txt", "directory-link/", "dangling-link/"]
    for name in names:
        capture("readlink:" + name, PROGRAMS[0], [name])
        capture("readlink-f:" + name, PROGRAMS[0], ["-f", name])
        capture("stat:" + name, PROGRAMS[1], ["-f", "%HT|%z|%p|%Y", name])
        capture("stat-L:" + name, PROGRAMS[1], ["-L", "-f", "%HT|%z|%p|%Y", name])
    for case, args in [
        ("readlink-n", ["-n", "file-link"]),
        ("readlink-multi", ["file-link", "dangling-link"]),
        ("readlink-multi-error", ["file-link", "target.txt", "directory-link"]),
        ("readlink-f-missing-parent", ["-f", "absent-directory/child.txt"]),
        ("readlink-f-dotdot", ["-f", "target-dir/../target.txt"]),
        ("readlink-f-trailing-slash-file", ["-f", "target.txt/"]),
        ("readlink-f-trailing-slash-directory", ["-f", "directory-link/"]),
        ("readlink-f-dot", ["-f", "."]),
        ("readlink-no-arguments", []),
    ]:
        capture(case, PROGRAMS[0], args)
    path = output / "readlink-runtime.json"
    if path.exists():
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        path.rename(output / f"readlink-runtime.previous-{stamp}.json")
    save(path, {
        "schema": 1, "recordedAt": now(), "evidenceType": "runtime-observation",
        "method": "subprocess execution of installed system utilities; no debugger or process attachment",
        "host": subprocess.check_output(["/usr/bin/sw_vers"], text=True).strip(),
        "fixture": str(fixture), "targetBytes": len(PAYLOAD), "links": links,
        "programs": {program: {"sha256": digest(program), "device": os.stat(program).st_dev, "inode": os.stat(program).st_ino} for program in PROGRAMS},
        "cases": cases,
    })
    print(f"Captured {len(cases)} runtime cases: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--refresh", action="store_true", help="repeat native analysis; archive old records")
    parser.add_argument("--runtime-only", action="store_true")
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    if not output.is_relative_to((ROOT / "research/local").resolve()):
        parser.error("Raw evidence output must remain inside gitignored research/local")
    output.mkdir(parents=True, exist_ok=True)
    if not arguments.runtime_only:
        capture_native(output, arguments.refresh)
    capture_runtime(output)
