#!/usr/bin/env python3
"""Capture bounded macOS graphics evidence without changing the installed OS.

Raw tool output stays in research/local/graphics. The public report contains
identities, selected declarations and explicit coverage limits. Pass --probe to
run the owned headless CoreGraphics/IOSurface/Metal workload as well.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "research/local/graphics"
NODE = ROOT / "tools/node_modules/node/bin/node"
REA = ROOT / "tools/node_modules/rea-agents/scripts/rea.mjs"
WINDOWSERVER = Path("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer")
CACHE_MAP = Path("/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e.map")
IMAGES = {
    "skylight": "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
    "coregraphics": "/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics",
    "quartzcore": "/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore",
    "metal": "/System/Library/Frameworks/Metal.framework/Versions/A/Metal",
    "iosurface": "/System/Library/Frameworks/IOSurface.framework/Versions/A/IOSurface",
    "coredisplay": "/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay",
    "iogpu": "/System/Library/PrivateFrameworks/IOGPU.framework/Versions/A/IOGPU",
    "agxmetalg15x_m1": "/System/Library/Extensions/AGXMetalG15X_M1.bundle/Contents/MacOS/AGXMetalG15X_M1",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def command(name, argv, env=None, timeout=180, reuse=False):
    path = LOCAL / name
    if reuse and path.exists() and path.stat().st_size:
        raw = path.read_bytes()
        return {"file": name, "sha256": digest(raw), "bytes": len(raw), "reused": True}
    started = datetime.now(timezone.utc).isoformat()
    try:
        result = subprocess.run([str(x) for x in argv], cwd=ROOT, env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        path.with_suffix(path.suffix + ".timeout").write_bytes(error.stdout or b"")
        raise
    if path.exists():
        previous = path.read_bytes()
        if previous != result.stdout:
            archived = path.with_name(path.stem + ".previous-" + digest(previous)[:16] + path.suffix)
            if not archived.exists():
                archived.write_bytes(previous)
    path.write_bytes(result.stdout)
    path.with_suffix(path.suffix + ".stderr.log").write_bytes(result.stderr)
    record = {"file": name, "command": [str(x) for x in argv], "started": started,
              "exitCode": result.returncode, "sha256": digest(result.stdout),
              "bytes": len(result.stdout)}
    save_json(path.with_suffix(path.suffix + ".record.json"), record)
    if result.returncode:
        raise RuntimeError(f"{name} failed; see its retained stderr")
    return record


def rea_record(filename, operation, *args, reuse=False):
    command(filename, [NODE, REA, operation, WINDOWSERVER, *args,
                       "--format", "json", "--full-output"], reuse=reuse)
    record = json.loads((LOCAL / filename).read_text())
    if not record.get("ok") or not record.get("data", {}).get("evidence_id"):
        raise RuntimeError(f"{filename} did not return canonical Evidence")
    return record["data"]


def inspect_cache_image(item, reuse):
    key, image = item
    filename = key + "-dyld-info.txt"
    record = command(filename, ["/usr/bin/xcrun", "dyld_info", "-uuid", "-platform",
                     "-segments", "-linked_dylibs", "-exports", image], reuse=reuse)
    raw = (LOCAL / filename).read_text()
    exports, dependencies = [], []
    section = None
    for line in raw.splitlines():
        marker = re.match(r"\s+-(\w+):$", line)
        if marker:
            section = marker.group(1)
        elif section == "exports":
            match = re.match(r"\s*(0x[0-9a-fA-F]+|\[re-export\])\s+(\S+)", line)
            if match:
                exports.append({"location": match.group(1), "name": match.group(2)})
        elif section == "linked_dylibs":
            match = re.match(r"\s*(.*?)\s+(/\S+)$", line)
            if match:
                dependencies.append({"attributes": match.group(1).strip(), "path": match.group(2)})
    uuid = re.search(r"-uuid:\s+([A-F0-9-]+)", raw)
    relevant = re.compile(r"^_(SLXServer|SLS(NewWindow|SetWindowBounds|OrderWindow|SetWindowShape|GetWindowBounds|MainConnectionID|ReleaseWindow)|CG(DisplayBounds|GetActiveDisplayList|WindowListCopyWindowInfo|ContextCreate|ContextFillRect)|MTL(CreateSystemDefaultDevice|CopyAllDevices)|IOSurface(Create|Lock|Unlock|GetBaseAddress)|IOGPU(Device|CommandQueue|Resource)|OBJC_CLASS_\$_(CAMetalLayer|CALayer|AGXG15X))")
    return {"key": key, "imagePath": image, "regularFilePresent": Path(image).exists(),
            "machOUuid": uuid.group(1) if uuid else None,
            "evidenceType": "apple-dyld-info-static-observation",
            "outputFile": "local/graphics/" + filename,
            "outputSha256": record["sha256"], "exportRows": len(exports),
            "declaredDependencies": dependencies,
            "selectedExportSeeds": [e for e in exports if relevant.search(e["name"])],
            "limits": ["An exported name is not a recovered signature or verified implementation.",
                       "Offsets are the installed dyld_info output, not standalone file offsets."]}


def plist_identity(path):
    data = path.read_bytes()
    value = plistlib.loads(data)
    return {"path": str(path), "sha256": digest(data),
            "identifier": value.get("CFBundleIdentifier"),
            "version": value.get("CFBundleVersion"),
            "executable": value.get("CFBundleExecutable"),
            "personalities": value.get("IOKitPersonalities", {}),
            "declaredOSBundleLibraries": value.get("OSBundleLibraries", {})}


def inspect_iosurface_code(reuse, probe):
    image = IMAGES["iosurface"]
    filename = "iosurface-disassembly.txt"
    record = command(filename, ["/usr/bin/xcrun", "dyld_info", "-function_starts", "-disassemble", image], reuse=reuse)
    lines = (LOCAL / filename).read_text().splitlines()
    names = ["_IOSurfaceGetWidth", "_IOSurfaceClientGetWidth", "_IOSurfaceGetBytesPerRow",
             "_IOSurfaceClientGetBytesPerRow", "_IOSurfaceGetAllocSize", "_IOSurfaceClientGetAllocSize",
             "_IOSurfaceClientGetPlaneCount", "_IOSurfaceLock", "_IOSurfaceClientLock",
             "_IOSurfaceUnlock", "_IOSurfaceClientUnlock", "__ioSurfaceConnectInternal"]
    functions = []
    call_offsets = []
    for name in names:
        start = lines.index(name + ":")
        end = start + 1
        while end < len(lines) and not re.match(r"^[^\s].*:$", lines[end]):
            end += 1
        body = lines[start + 1:end]
        instructions = [line for line in body if re.match(r"^0x[0-9A-Fa-f]+\s", line)]
        first = int(instructions[0].split()[0], 16)
        last = int(instructions[-1].split()[0], 16)
        functions.append({"name": name, "startAddress": hex(first), "lastInstructionAddress": hex(last),
                          "instructionCount": len(instructions),
                          "assemblySha256": digest("\n".join(instructions).encode())})
        if name in ["_IOSurfaceClientLock", "_IOSurfaceClientUnlock"]:
            selector = 2 if name.endswith("Lock") else 3
            selected = None
            for i, line in enumerate(instructions[:-1]):
                if re.search(r"mov\s+w1, #0x" + str(selector) + r"\s", line) and re.search(r"\sbl\s", instructions[i + 1]):
                    selected = int(instructions[i + 1].split()[0], 16) - first
            if selected is None:
                raise RuntimeError(f"{name} changed; no bounded selector/call pattern was established")
            call_offsets.append(selected)
    linkage = None
    if probe:
        command("linkage-build.stdout", ["/usr/bin/xcrun", "clang", "-Wall", "-Wextra", "-O0",
                    ROOT / "script/research_graphics_linkage.c", "-o", LOCAL / "graphics-linkage"])
        command("graphics-linkage.json", [LOCAL / "graphics-linkage", *map(str, call_offsets)], timeout=30)
        linkage = json.loads((LOCAL / "graphics-linkage.json").read_text())
        linkage["sourceSha256"] = digest((ROOT / "script/research_graphics_linkage.c").read_bytes())
        linkage["outputSha256"] = digest((LOCAL / "graphics-linkage.json").read_bytes())
    return {"evidenceType": "apple-dyld-info-static-disassembly", "image": image,
            "outputFile": "local/graphics/" + filename, "outputSha256": record["sha256"],
            "selectedFunctions": functions, "resolvedCalls": linkage,
            "limits": ["This is assembly inspection, not REA or Ghidra pseudocode.",
                       "Only the selected functions were interpreted; other disassembly remains unreviewed.",
                       "Private structure offsets and selector values are observations for this captured image UUID.",
                       "Kernel implementations of the traps and cross-process surface sharing remain unexamined."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    LOCAL.mkdir(parents=True, exist_ok=True)
    host = subprocess.check_output(["/usr/bin/sw_vers"], text=True).strip()
    identity = {"host": host, "windowServerSha256": digest(WINDOWSERVER.read_bytes()),
                "cacheMapSha256": digest(CACHE_MAP.read_bytes())}
    identity_file = LOCAL / "identity.json"
    same_identity = identity_file.exists() and json.loads(identity_file.read_text()) == identity
    reuse = same_identity and not args.refresh
    # Initial manually captured canonical results are adopted only when their
    # subject digest matches this installed executable.
    def reusable_evidence(filename):
        if args.refresh:
            return False
        try:
            data = json.loads((LOCAL / filename).read_text())["data"]
            return data["subject"]["digest"]["sha256"] == identity["windowServerSha256"]
        except (FileNotFoundError, KeyError, ValueError):
            return False

    macho = rea_record("windowserver-inspect-macho.json", "inspect-macho",
                       reuse=reusable_evidence("windowserver-inspect-macho.json"))
    launch = rea_record("windowserver-launchd-plist.json", "inspect-plist", "--relative-path",
                        "/System/Library/LaunchDaemons/com.apple.WindowServer.plist", reuse=reuse)
    native = []

    def function(address, filename):
        if not reusable_evidence(filename):
            environment = os.environ.copy()
            environment.setdefault("GHIDRA_INSTALL_DIR", "/opt/homebrew/opt/ghidra/libexec")
            environment.setdefault("JAVA_HOME", "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home")
            command(filename, [NODE, REA, "function", WINDOWSERVER, address, "--provider", "ghidra",
                      "--snapshot", LOCAL / "windowserver-ghidra-snapshot.json",
                      "--format", "json", "--full-output"], env=environment)
        data = json.loads((LOCAL / filename).read_text())["data"]
        if not data.get("evidence_id"):
            raise RuntimeError(f"No canonical function evidence in {filename}")
        normalized = data["normalized_result"]
        procedure = normalized["procedure"]
        native.append({"evidenceId": data["evidence_id"], "file": "local/graphics/" + filename,
                       "procedure": {k: procedure[k] for k in ["address", "name", "body"]},
                       "callees": [{"address": x["address"], "name": x["name"]} for x in normalized["callees"]],
                       "limits": data["limitations"]})
        return normalized

    entry_offset = macho["normalized_result"]["entrypoints"]["items"][0]["file_offset"]
    text_segment = next(x for x in macho["normalized_result"]["segments"]["items"] if x["name"] == "__TEXT")
    entry_address = hex(int(text_segment["vm_address"], 16) + entry_offset - text_segment["file_offset"])
    entry = function(entry_address, "windowserver-entry-function.json")
    helpers = [x for x in entry["callees"] if not x["classification"]["external"] and not x["classification"]["thunk"]]
    if len(helpers) != 1:
        raise RuntimeError("WindowServer bootstrap changed; review its canonical entry evidence before selecting a helper")
    function(helpers[0]["address"], "windowserver-setup-function.json")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        cache_images = list(pool.map(lambda item: inspect_cache_image(item, reuse), IMAGES.items()))
    iosurface_code = inspect_iosurface_code(reuse, args.probe)
    declarations = []
    for image in IMAGES.values():
        p = Path(image)
        info = p.parent / "Resources/Info.plist" if ".framework/" in image else p.parent.parent / "Info.plist"
        if info.exists():
            declarations.append(plist_identity(info))
    for name in ["AGXG15C.kext", "IOGPUFamily.kext", "IOSurface.kext"]:
        declarations.append(plist_identity(Path("/System/Library/Extensions") / name / "Contents/Info.plist"))
    command("agx-ioreg-local.plist", ["/usr/sbin/ioreg", "-r", "-c", "AGXAcceleratorG15X", "-a"])
    ioreg = plistlib.loads((LOCAL / "agx-ioreg-local.plist").read_bytes())
    allowed = {"CFBundleIdentifier", "CFBundleIdentifierKernel", "IOClass", "IOProviderClass",
               "MetalPluginName", "gpu-core-count", "model"}
    gpu = [{k: v for k, v in node.items() if k in allowed and isinstance(v, (str, int, list))} for node in ioreg]
    probe = None
    if args.probe:
        command("probe-build.stdout", ["/usr/bin/xcrun", "swiftc", ROOT / "script/research_graphics_probe.swift",
                                       "-o", LOCAL / "graphics-probe"])
        command("graphics-probe.json", [LOCAL / "graphics-probe"], timeout=30)
        probe = json.loads((LOCAL / "graphics-probe.json").read_text())
        probe["sourceSha256"] = digest((ROOT / "script/research_graphics_probe.swift").read_bytes())
        probe["outputSha256"] = digest((LOCAL / "graphics-probe.json").read_bytes())
    report = {"schema": 1, "capturedAt": datetime.now(timezone.utc).isoformat(), **identity,
              "scope": "WindowServer bootstrap, twelve selected IOSurface functions, eight cached graphics images, selected declarations and owned-process probes",
              "windowServer": {"path": str(WINDOWSERVER), "bytes": WINDOWSERVER.stat().st_size,
                  "machoEvidenceId": macho["evidence_id"], "machoFile": "local/graphics/windowserver-inspect-macho.json",
                  "architectures": macho["normalized_result"]["architectures"],
                  "entrypoints": macho["normalized_result"]["entrypoints"],
                  "nativeFunctions": native,
                  "launchdEvidenceId": launch["evidence_id"],
                  "launchd": launch["normalized_result"]["value"]},
              "cacheImages": cache_images, "iosurfaceCode": iosurface_code, "bundleDeclarations": declarations,
              "runningGpuAllowlistedProperties": gpu, "runtimeProbe": probe,
              "limits": ["No protected process was launched, attached to, injected into, or modified.",
                  "Only the two WindowServer bootstrap functions were decompiled, not SkyLight's server implementation.",
                  "Only selected IOSurface getter and lock/unlock code paths were inspected beyond WindowServer bootstrap.",
                  "No CoreGraphics renderer, Core Animation compositor, Metal compiler, AGX user-client, shader ISA or GPU firmware implementation was reconstructed.",
                  "A successful macOS Metal workload is not an open-source driver or evidence of Linux GPU support.",
                  "Hardware-specific AGX selection is observed on this M3 Max; it does not establish support for every Apple GPU.",
                  "Raw evidence remains local and is omitted from Git; no Apple binary or recovered pseudocode is included in this summary."]}
    save_json(ROOT / "research/graphics-findings.json", report)
    save_json(identity_file, identity)
    print(json.dumps({"cacheImages": len(cache_images), "exportRows": sum(x["exportRows"] for x in cache_images),
                      "nativeFunctions": len(native), "probe": probe, "report": "research/graphics-findings.json"}, indent=2))


if __name__ == "__main__":
    main()
