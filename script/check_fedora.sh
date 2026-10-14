#!/usr/bin/env bash
# Read-only evidence from the active physical Fedora session.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: script/check_fedora.sh [--json] [--verify-profile] [--help]

Inspect the active Fedora aarch64 installation without root privileges.
Reports observed hardware, graphics, network, input, audio, desktop, and tools.
Does not play audio, capture input, probe disks, or change configuration.
Internet access, suspend, physical input, and audible playback need manual checks.
--verify-profile additionally requires Absolute's live panels and widgets to exist.

Exit 0: a supported physical target was inspected.
Exit 1: the target could not be verified, or a required diagnostic failed.
Exit 2: unsupported platform or invalid arguments.
EOF
}

OUTPUT=text
VERIFY_PROFILE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) OUTPUT=json ;;
        --verify-profile) VERIFY_PROFILE=true ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

if [[ "$(uname -s)" != Linux || ! -r /etc/os-release ]]; then
    printf '%s\n' 'Native Fedora checks require booting the physical Mac into Fedora; the current system is not Linux.' >&2
    exit 2
fi
source /etc/os-release
if [[ "${ID:-}" != fedora || "$(uname -m)" != aarch64 ]]; then
    printf '%s\n' 'Native checks require Fedora on aarch64.' >&2
    exit 2
fi
if ! command -v python3 >/dev/null; then
    printf '%s\n' 'python3 is required to collect the Fedora readiness report.' >&2
    exit 1
fi

python3 - "$OUTPUT" "$VERIFY_PROFILE" <<'PY'
import datetime
import glob
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

def read(path):
    try:
        return Path(path).read_text(errors="replace").replace("\0", " ").strip()
    except OSError:
        return None

def run(*args):
    if not shutil.which(args[0]):
        return {"status": "unavailable", "tool": args[0]}
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=10,
                                env={**os.environ, "LC_ALL": "C"})
        return {"status": "observed" if result.returncode == 0 else "failed",
                "exit_code": result.returncode, "output": result.stdout.strip()}
    except (OSError, subprocess.TimeoutExpired):
        return {"status": "failed", "tool": args[0], "reason": "unavailable or timed out"}

def xdg(name, fallback):
    value = os.environ.get(name, "")
    return Path(value) if value.startswith("/") else Path.home() / fallback

model = read("/proc/device-tree/model") or read("/sys/firmware/devicetree/base/model")
compatible = read("/proc/device-tree/compatible") or read("/sys/firmware/devicetree/base/compatible")
virtualization = run("systemd-detect-virt")
virtual_kind = virtualization.get("output")
apple = "apple" in ((model or "") + " " + (compatible or "")).lower()
physical = virtual_kind == "none"
native_target = apple and physical

commands = ["swift", "clang", "gcc", "pkg-config", "git", "AbsoluteLinux",
            "absolute", "plasmashell", "plasma-apply-lookandfeel", "kpackagetool6",
            "dolphin", "firefox", "konsole", "systemsettings", "xdg-open"]
tools = {name: shutil.which(name) is not None for name in commands}
runtime = Path.home() / ".local/libexec/absolute/AbsoluteLinux"
tools["installed_AbsoluteLinux"] = runtime.is_file() and os.access(runtime, os.X_OK)
deps = run("pkg-config", "--modversion", "gtk4", "gio-unix-2.0")
build_ready = all(tools[name] for name in ["swift", "clang", "gcc", "pkg-config"]) and deps["status"] == "observed"

session_type = os.environ.get("XDG_SESSION_TYPE", "unknown")
desktop = os.environ.get("XDG_CURRENT_DESKTOP", "unknown")
display_available = bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
plasma_version = run("plasmashell", "--version")
plasma6 = bool(re.search(r"plasmashell\s+6\.", plasma_version.get("output", "")))
active_plasma = display_available and "kde" in desktop.lower() and plasma6

render_nodes = sorted(Path(p).name for p in glob.glob("/dev/dri/renderD*"))
accessible_nodes = [name for name in render_nodes if os.access("/dev/dri/" + name, os.R_OK | os.W_OK)]
connectors = []
for path in sorted(glob.glob("/sys/class/drm/card*-*/status")):
    connector = Path(path).parent
    connectors.append({"name": connector.name, "status": read(path),
                       "modes": (read(connector / "modes") or "").splitlines()})
glx = run("glxinfo", "-B") if display_available else {"status": "not_observed"}
renderer = None
for line in glx.get("output", "").splitlines():
    if "OpenGL renderer string:" in line:
        renderer = line.split(":", 1)[1].strip()
software = bool(renderer and re.search(r"llvmpipe|softpipe|swrast|software", renderer, re.I))
qdbus = next((path for name in ["qdbus6", "qdbus", "/usr/lib64/qt6/bin/qdbus"] if (path := shutil.which(name))), None)
kwin = run(qdbus, "org.kde.KWin", "/KWin", "org.kde.KWin.supportInformation") if qdbus and active_plasma else {"status": "not_observed"}
kwin_fields = {}
for line in kwin.get("output", "").splitlines():
    for label in ["OpenGL renderer string", "OpenGL vendor string", "Compositing Type"]:
        if line.startswith(label + ":"):
            kwin_fields[label] = line.split(":", 1)[1].strip()
kwin_renderer = kwin_fields.get("OpenGL renderer string")
kwin_software = bool(kwin_renderer and re.search(r"llvmpipe|softpipe|swrast|software", kwin_renderer, re.I))

panel_script = r'''
(function () {
    var result = [];
    panels().forEach(function (panel) {
        var previous = panel.currentConfigGroup;
        panel.currentConfigGroup = ["Absolute"];
        var profile = panel.readConfig("profile", "");
        var role = panel.readConfig("role", "");
        panel.currentConfigGroup = previous;
        if (profile === "org.absolute.desktop") {
            result.push({id: panel.id, role: role, location: panel.location,
                         screen: panel.screen, widgets: panel.widgets().map(function (widget) { return widget.type; })});
        }
    });
    print("ABSOLUTE_PANELS_JSON=" + JSON.stringify(result));
}());
'''
panel_state = {"status": "not_observed", "verified": False, "panels": []}
if qdbus and active_plasma:
    deadline = time.monotonic() + (12 if sys.argv[2] == "true" else 0)
    while True:
        observed = run(qdbus, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", panel_script)
        panel_state["status"] = observed["status"]
        for line in observed.get("output", "").splitlines():
            if line.startswith("ABSOLUTE_PANELS_JSON="):
                try:
                    panel_state["panels"] = json.loads(line.split("=", 1)[1])
                except ValueError:
                    panel_state["status"] = "invalid_response"
        expected = {
            "topbar": ("top", {"org.kde.plasma.kickoff", "org.kde.plasma.appmenu", "org.kde.plasma.panelspacer", "org.kde.plasma.systemtray", "org.kde.plasma.digitalclock"}),
            "dock": ("bottom", {"org.kde.plasma.icontasks", "org.kde.plasma.showdesktop"})
        }
        panel_state["verified"] = observed["status"] == "observed" and all(
            len(matches := [p for p in panel_state["panels"] if p.get("role") == role]) == 1 and
            matches[0].get("location") == location and matches[0].get("screen", -1) >= 0 and
            widgets.issubset(set(matches[0].get("widgets", [])))
            for role, (location, widgets) in expected.items())
        if panel_state["verified"] or time.monotonic() >= deadline:
            break
        time.sleep(0.5)

interfaces = []
for path in sorted(glob.glob("/sys/class/net/*")):
    name = Path(path).name
    if name != "lo":
        interfaces.append({"device": name, "operstate": read(Path(path) / "operstate"),
                           "wireless": (Path(path) / "wireless").exists()})
route = run("ip", "-j", "route", "show", "default")
try:
    default_route = bool(json.loads(route.get("output", "[]"))) if route["status"] == "observed" else None
except ValueError:
    default_route = None

input_names = sorted({name for path in glob.glob("/sys/class/input/event*/device/name") if (name := read(path))})
audio_cards = read("/proc/asound/cards")
volume = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
audio_sink = volume["status"] == "observed"
data_home = xdg("XDG_DATA_HOME", ".local/share")
profile = data_home / "plasma/look-and-feel/org.absolute.desktop/metadata.json"

report = {
    "schema_version": 1,
    "observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "target": {"expected": "physical Apple M3 Max (Mac15,10)",
               "os": platform.freedesktop_os_release().get("PRETTY_NAME"),
               "architecture": platform.machine(), "kernel": platform.release(),
               "device_tree_model": model, "device_tree_compatible": compatible,
               "virtualization": virtual_kind or "unverified", "physical_apple_detected": native_target,
               "exact_marketing_model": "not inferred from device-tree strings"},
    "build": {"dependencies_ready": build_ready, "tools": tools,
              "swift": run("swift", "--version"), "pkg_config_versions": deps},
    "session": {"type": session_type, "desktop": desktop, "display_available": display_available,
                "plasma_version": plasma_version, "active_plasma_6": active_plasma,
                "absolute_profile_installed": profile.is_file(), "absolute_live_panels": panel_state},
    "graphics": {"render_nodes": render_nodes, "accessible_render_nodes": accessible_nodes,
                 "connectors": connectors, "glx_probe_status": glx["status"],
                 "glx_renderer": renderer, "software_renderer_observed": software,
                 "kwin_probe_status": kwin["status"], "kwin": kwin_fields,
                 "kwin_software_renderer_observed": kwin_software,
                 "scope": "GLX client renderer; on Wayland this describes Xwayland, not full compositor behavior",
                 "visual_correctness": "requires interactive validation"},
    "network": {"interfaces": interfaces, "default_route_present": default_route,
                "internet_dns_and_transfer": "not tested"},
    "input": {"enumerated_devices": input_names, "physical_key_and_pointer_events": "not captured or tested"},
    "audio": {"alsa_cards": audio_cards, "default_pipewire_sink_available": audio_sink,
              "volume": volume.get("output") if audio_sink else None,
              "audible_playback_and_microphone": "not tested"},
    "manual_checks_remaining": [
        "Confirm the exact Mac model and installed Asahi hardware support.",
        "Check the native display, pointer, keyboard, scaling, and application window behavior.",
        "Verify Wi-Fi connectivity and an actual Internet transfer.",
        "Verify headphones, microphone, and speakers using the installed Asahi audio support.",
        "Verify suspend/resume, battery/power, external displays, and required USB devices.",
        "Run Absolute's tests natively; boot health and macOS application compatibility are separate checks."
    ],
    "completion": "Evidence inventory only; this report does not certify a complete macOS replacement."
}

if sys.argv[1] == "json":
    print(json.dumps(report, indent=2))
else:
    def line(state, label, detail):
        print(f"[{state}] {label}: {detail}")
    line("PASS" if native_target else "BLOCKED", "Physical target", model or "Apple hardware not verified")
    line("OBSERVED", "Fedora", f"{report['target']['os']}; {platform.machine()}; {platform.release()}")
    line("PASS" if build_ready else "MISSING", "Build dependencies", "ready" if build_ready else "run install_fedora.sh --install to install/build")
    line("PASS" if active_plasma else "PENDING", "Plasma session", f"{desktop}; {session_type}; {plasma_version.get('output', 'version unavailable')}")
    line("SOFTWARE" if kwin_software or (not kwin_renderer and software) else ("OBSERVED" if kwin_renderer or renderer else "PENDING"), "Graphics", kwin_renderer or renderer or "renderer not measured; graphics diagnostics/display may be unavailable")
    line("OBSERVED", "DRM", f"{len(accessible_nodes)} accessible render nodes; {sum(c['status'] == 'connected' for c in connectors)} connected outputs")
    line("OBSERVED", "Network", f"{sum(i['operstate'] == 'up' for i in interfaces)} interfaces up; default route: {default_route}; Internet untested")
    line("OBSERVED", "Input", f"{len(input_names)} devices enumerated; physical input untested")
    line("OBSERVED" if audio_sink else "PENDING", "Audio", volume.get("output", "default PipeWire sink unavailable") + "; audible playback untested")
    line("INSTALLED" if tools["installed_AbsoluteLinux"] else "MISSING", "Absolute", str(runtime))
    line("PASS" if panel_state["verified"] else "PENDING", "Absolute panels", "live topbar, Dock, and required widgets verified" if panel_state["verified"] else "native profile layout not verified")
    print("\nManual checks remain:")
    for item in report["manual_checks_remaining"]:
        print("- " + item)
    print("\n" + report["completion"])
sys.exit(0 if native_target and (sys.argv[2] != "true" or panel_state["verified"]) else 1)
PY
