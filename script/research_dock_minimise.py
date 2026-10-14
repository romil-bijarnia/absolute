#!/usr/bin/env python3
"""Recover the Dock's minimise effects (Genie, Scale, Suck) from the installed Dock.app.

Reuses the Dock copy and REA snapshot that script/research_dock_magnification.py
creates beneath research/local/dock-magnification, and analyses the procedures
that build the minimise warp meshes, drive the transition clock and choose the
duration. Nothing is executed, attached to or modified; the running Dock is never
touched. Successful REA records are reused on later runs when the copied
binary's identity is unchanged. Requires the project Node/REA installation and a
Ghidra install for records that are not yet retained.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from research_dock_magnification import (DEFAULT_OUTPUT, ROOT, TARGET, digest, now, rea_record, run_rea, save)  # noqa: E402

# Procedures of build 26A5421a that carry the behaviour. Other builds need a new pass.
PROCEDURES = {
    "0x100026ba8": "effect dispatcher: reads minimizeEffect, forces Scale when the transition flag is set, calls one builder",
    "0x100026c64": "Genie builder: step budgets, squeeze and slide ramps, profile rows, two-column warp mesh, thumbnail reveal",
    "0x1000276d8": "Genie profile subdivision: recursive midpoint rows until segments are under 8 pt or within 0.6 pt of straight",
    "0x100037fb4": "Scale builder: rectangle eased toward the target as a 2 x 2 mesh",
    "0x100038164": "Suck builder: grid of one line per 70 pt, at most 19 cells, every point pulled at the same speed",
    "0x100026514": "transition update: progress = 0.5 - 0.5 cos(pi * property value), then setNeedUpdate:",
    "0x1000502b4": "DockFloatAnimatedProperty step: linear clock, cosine only when an easing function is attached",
    "0x100026600": "DOCKWindowTile::updateTransition: target image rect from the tile's icon rect, dispatch, mask from the reveal",
    "0x100034890": "DOCKWindowTile::beginMinMax:minimizing:animate:: mask layer, stored layer image, window tags, duration in seconds",
    "0x100099934": "DockBar::_handleMinimizeWindow:animate:duration:: animated property 0 to 1 over the duration, direction from the bar orientation",
    "0x100097d7c": "DockBar::handleDockEventMinimizeWindow:context:: effectDur, x10 under the slow-motion modifier, x2 under a second modifier",
    "0x1002564d4": "DockBar::setEffectDur:",
    "0x10002ff18": "Tile::doCommand:: duration site for the Dock menu, effectDur = 400 ms when minimizeEffect is Suck, else 200 ms",
    "0x100059c80": "duration site on effect change: effectDur = 500 ms Genie, 400 ms Suck, 200 ms Scale",
}
SEARCH_PATTERN = ("updateTransition|effectDur|genieSpeed|genieTo|beginMinMax|handleMinimizeWindow|minimizeEffect|"
                  "slowMotion|startMinimize|minimizeWindow|DOCKWindowTile::")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=ROOT / "research/dock-minimise-findings.json")
    parser.add_argument("--skip-rea", action="store_true", help="only rebuild the report from retained records")
    args = parser.parse_args()
    output = args.output

    identity_path = output / "identity.json"
    sliced = output / "Dock.arm64e"
    if not identity_path.exists() or not sliced.exists():
        raise RuntimeError("Run script/research_dock_magnification.py first; it copies the Dock and records its identity")
    identity = json.loads(identity_path.read_text())
    if identity.get("sha256") != digest(TARGET):
        raise RuntimeError("Installed Dock changed; rerun the magnification pass into a new --output directory")
    slice_sha = digest(sliced)

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

    procedures = {}
    for address, role in PROCEDURES.items():
        evidence = record(f"fn-{address[2:]}", "function", address)
        result = evidence["normalized_result"]
        procedures[address] = {
            "role": role,
            "ghidraName": result["procedure"].get("name"),
            "bodyBytes": result["procedure"].get("body", {}).get("total_bytes"),
            "callers": [c.get("name") or c.get("address") for c in result.get("callers", [])],
            "callees": sorted({c.get("name") or c.get("address") for c in result.get("callees", [])}),
            "evidenceId": evidence["evidence_id"],
        }
    search = record("search-minimise", "search", "--kind", "procedures", "--mode", "regex", "--pattern", SEARCH_PATTERN)
    named = {m["value"]: m["address"] for m in search["normalized_result"] if isinstance(m, dict) and "value" in m}

    host = subprocess.run(["/usr/bin/sw_vers"], capture_output=True, text=True, check=True).stdout.strip()
    report = {
        "schema": 1,
        "recordedAt": now(),
        "host": host,
        "scope": "Static recovery of the Dock's minimise effects, their transition clock and duration from the installed "
                 "Dock executable. No process was executed, attached to or modified.",
        "target": {"path": str(TARGET), "sourceSha256": identity["sha256"], "sourceBytes": identity["bytes"],
                   "copySha256": slice_sha, "architecture": "arm64e", "derivation": "byte copy of the thin arm64e executable"},
        "providers": {"rea": "6.4.0", "ghidra": "12.1.3", "searchEvidenceId": search["evidence_id"]},
        "procedures": procedures,
        "namedProcedures": named,
        "constants": {
            "stepsPerLogUnit": 50,
            "genieMinimumSegment": 8,
            "genieLinearSegment": 128,
            "genieLinearTolerance": 0.6,
            "genieMaximumRows": 400,
            "genieSubdivisionCalls": 64,
            "suckCellSize": 70,
            "suckMaximumCells": 19,
            "durationMilliseconds": {"genie": 500, "scale": 200, "suck": 400},
            "slowMotionFactor": 10,
            "secondModifierFactor": 2,
            "genieSpeedDefault": 0.5,
            "genieSpeedPreference": "genie-speed",
        },
        "model": {
            "clock": "p = 0.5 - 0.5 cos(pi * clamp((now - start) / duration, 0, 1)); the property itself is linear",
            "steps": "steps(d) = floor(ln(|d| / 2 + 1)) * 50",
            "genie": {
                "edges": "L = target.leading - window.leading, R = target.trailing - window.trailing",
                "travel": "T = |window.far - target.far| unless the window overlaps the target, then T = window length",
                "budgets": "A = steps(max(2 * overlap, (|L| + |R|) / 8)), B = steps(T), enter = B * acos(1 - 2 |T - length| / T) / pi, "
                           "A = max(A, enter), lead = A - enter",
                "ramps": "total = p (B + lead); squeeze = ramp(clamp(total, 0, A) / A); slide = ramp(clamp(total - lead, 0, B) / B)",
                "profile": "sigma(y) = ramp((y - centre) / trunc(travel + 0.5)), centre = window.far + overlap * squeeze",
                "rows": "far = centre - T * slide; rows from far to max(far - length, target.far) while sliding, then one row at "
                        "max(far - length, target.near) once |T - length| < T * slide; edge offsets L * squeeze * sigma, R * squeeze * sigma",
                "mesh": "two points per row, local coordinate linear over the mesh extent, rows ordered by increasing screen coordinate",
                "reveal": "clamp(1 - (T - T * slide) / (length - target.length), 0, 1), or 1 only at the end when the window is not taller than the target",
            },
            "scale": "e = ramp(p); corners = window + (target - window) * e; 2 x 2 mesh; settled when e >= 1",
            "suck": "e = ramp(p); grid of clamp(trunc(size / 70), 1, 19) cells; reach = largest same-corner displacement; "
                    "each point moves toward its target place by min(distance, reach * e)",
        },
        "implementation": {
            "source": "Sources/AbsoluteCore/DockMinimise.swift",
            "tests": "Tests/AbsoluteCoreTests/DockMinimiseTests.swift",
            "demo": "research/dock-minimise-demo.html",
        },
        "limitations": [
            "Static reading of machine code; no minimise was recorded on screen and no Dock process was attached to.",
            "Addresses are specific to build 26A5421a.",
            "The two modifier masks passed to CGSInputModifierKeyState are recorded by value, not by key name.",
            "The second arrival pass that fades the warped window out once the reveal completes is not modelled.",
        ],
    }
    save(args.report, report)
    print(f"wrote {args.report}")


if __name__ == "__main__":
    main()
