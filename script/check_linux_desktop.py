#!/usr/bin/env python3
"""Exercise the real GTK host through X11 mouse and keyboard events."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

binary, project = Path(sys.argv[1]), Path(sys.argv[2])
output = project / "research/local" / datetime.datetime.now().strftime("linux-ui-check-%Y%m%d-%H%M%S")
output.mkdir(parents=True)
state_path, session_path = output / "ui-state.json", output / "desktop-session.json"
log = (output / "desktop.log").open("w")
checks, errors, shots = {}, [], []
process = None
display = subprocess.Popen(["Xvfb", ":99", "-screen", "0", "1440x900x24", "-nolisten", "tcp"],
                           stdout=log, stderr=log)

def command(*args):
    return subprocess.run(list(args), text=True, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.strip()

def wait(condition, description, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            result = condition()
            if result:
                return result
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError):
            pass
        time.sleep(0.08)
    raise RuntimeError("Timed out: " + description)

def state():
    return json.loads(state_path.read_text())

def focused():
    s = state()
    return next(b for b in s["browsers"] if b["id"].lower() == s["focusedWindow"].lower())

def click(role, browser=True, double=False):
    if browser and role.startswith("entry:"):
        for attempt in range(20):
            boxes = focused()["widgets"]
            item, viewport = boxes[role], boxes["contents"]
            center = item["y"] + item["height"] / 2
            if viewport["y"] + 8 <= center <= viewport["y"] + viewport["height"] - 8:
                break
            direction = "5" if center > viewport["y"] + viewport["height"] else "4"
            command("xdotool", "mousemove", "--sync",
                    str(round(viewport["x"] + viewport["width"] / 2)),
                    str(round(viewport["y"] + viewport["height"] / 2)), "click", direction)
            time.sleep(0.15)
    rect = (focused()["widgets"] if browser else state()["widgets"])[role]
    x, y = round(rect["x"] + rect["width"] / 2), round(rect["y"] + rect["height"] / 2)
    args = ["xdotool", "mousemove", "--sync", str(x), str(y), "click"]
    if double:
        args += ["--repeat", "2", "--delay", "120"]
    args += ["1"]
    command(*args)

def key(value):
    command("xdotool", "key", "--clearmodifiers", value)

def text(value):
    command("xdotool", "type", "--clearmodifiers", "--delay", "20", value)

def capture(name):
    time.sleep(0.2)
    command("import", "-window", "root", str(output / name))
    shots.append(name)

def start():
    global process
    state_path.unlink(missing_ok=True)
    process = subprocess.Popen([str(binary), "--project", str(project),
                               "--state-file", str(session_path), "--debug-state", str(state_path)],
                              stdout=log, stderr=log)
    wait(lambda: state_path.exists() and state()["widgets"].get("desktop"), "native desktop mapped")
    window = command("xdotool", "search", "--name", "^Absolute Linux Desktop$").splitlines()[-1]
    command("xdotool", "windowfocus", "--sync", window)
    return window

def stop():
    global process
    if process is None:
        return
    process.terminate()
    process.wait(timeout=8)
    process = None

try:
    wait(lambda: command("xdotool", "getdisplaygeometry"), "virtual display ready")
    bus = command("dbus-daemon", "--session", "--fork", "--print-address")
    os.environ["DBUS_SESSION_BUS_ADDRESS"] = bus
    start()
    checks["gtk_window_and_real_folder"] = state()["renderer"] == "GTK4" and "Package.swift" in focused()["names"]
    checks["linux_applications_discovered"] = state()["applicationCount"] > 0
    capture("01-linux-desktop.png")

    click("entry:" + str(project / "Sources"), double=True)
    wait(lambda: focused()["directory"] == str(project / "Sources"), "open Sources")
    checks["double_click_opens_folder"] = "AbsoluteCore" in focused()["names"]
    click("search")
    text("AbsoluteCore")
    wait(lambda: focused()["names"] == ["AbsoluteCore"], "filter folder")
    checks["folder_filter"] = True
    key("ctrl+a"); key("BackSpace")
    wait(lambda: focused()["filter"] == "", "clear filter")
    click("back")
    wait(lambda: focused()["directory"] == str(project), "back")
    checks["back_navigation"] = True
    click("forward")
    wait(lambda: focused()["directory"] == str(project / "Sources"), "forward")
    checks["forward_navigation"] = True
    click("favorite:Absolute")
    wait(lambda: focused()["directory"] == str(project), "project favorite")
    key("ctrl+shift+period")
    wait(lambda: focused()["hidden"] and ".git" in focused()["names"], "hidden files shortcut")
    checks["hidden_files_keyboard_command"] = True
    click("view")
    wait(lambda: not focused()["grid"], "list mode")
    checks["list_view"] = focused()["widgets"]["entry:" + str(project / "Package.swift")]["width"] > 200

    click("entry:" + str(project / "Package.swift"))
    wait(lambda: focused().get("selected") == str(project / "Package.swift"), "select Package.swift")
    key("ctrl+i")
    wait(lambda: state().get("modalTitle") == "Package.swift" and state()["widgets"].get("dialog"), "Get Info")
    checks["get_info_keyboard_and_native_panel"] = "Kind: Code" in state()["modalText"] and "Permissions:" in state()["modalText"]
    capture("02-file-info.png")
    click("dialog-reveal", browser=False)
    wait(lambda: not state().get("modalTitle"), "reveal closes inspector")
    checks["reveal_selects_file_in_parent"] = focused()["directory"] == str(project) and focused().get("selected") == str(project / "Package.swift")
    click("entry:" + str(project / "Package.swift"))
    key("space")
    wait(lambda: "PackageDescription" in state().get("modalText", ""), "text preview")
    checks["space_opens_text_preview"] = True
    key("Escape")
    wait(lambda: not state().get("modalTitle"), "close preview")

    first_id = focused()["id"]
    old = next(w for w in state()["snapshot"]["session"]["windows"] if w["id"].lower() == first_id.lower())
    rect = focused()["widgets"]["titlebar"]
    x, y = round(rect["x"] + rect["width"] / 2), round(rect["y"] + rect["height"] / 2)
    command("xdotool", "mousemove", "--sync", str(x), str(y), "mousedown", "1",
            "mousemove", "--sync", str(x + 70), str(y + 30), "mouseup", "1")
    wait(lambda: next(w for w in state()["snapshot"]["session"]["windows"] if w["id"].lower() == first_id.lower())["x"] > old["x"] + 40, "drag window")
    checks["mouse_drag_updates_shared_geometry"] = True
    old = next(w for w in state()["snapshot"]["session"]["windows"] if w["id"].lower() == first_id.lower())
    rect = focused()["widgets"]["resize"]
    x, y = round(rect["x"] + rect["width"] / 2), round(rect["y"] + rect["height"] / 2)
    command("xdotool", "mousemove", "--sync", str(x), str(y), "mousedown", "1",
            "mousemove", "--sync", str(x + 80), str(y + 30), "mouseup", "1")
    wait(lambda: next(w for w in state()["snapshot"]["session"]["windows"] if w["id"].lower() == first_id.lower())["width"] > old["width"] + 40, "resize window")
    checks["mouse_resize_updates_shared_geometry"] = True
    click("minimize")
    wait(lambda: not state().get("focusedWindow"), "minimize")
    checks["minimize_window"] = True
    click("dock-files", browser=False)
    wait(lambda: state().get("focusedWindow"), "Dock restore")
    checks["dock_restores_same_window"] = focused()["id"] == first_id

    key("ctrl+n")
    wait(lambda: len(state()["browsers"]) == 2, "second window")
    second_id = focused()["id"]
    click("entry:" + str(project / "Sources"), double=True)
    wait(lambda: focused()["directory"] == str(project / "Sources"), "second folder")
    checks["independent_file_windows"] = second_id != first_id and next(b for b in state()["browsers"] if b["id"] == first_id)["directory"] == str(project)
    click("minimize")
    wait(lambda: state().get("focusedWindow", "").lower() == first_id.lower(), "focus first window")

    key("ctrl+k")
    wait(lambda: state()["launcherVisible"] and state()["widgets"].get("launcher"), "launcher")
    if len(state()["launcherResults"]) > 1:
        click("launcher-entry:" + state()["launcherPaths"][1], browser=False)
        wait(lambda: state()["launcherSelection"] == 1, "launcher mouse selection")
        checks["launcher_mouse_selection"] = True
        key("Up")
        wait(lambda: state()["launcherSelection"] == 0, "launcher previous")
        key("Down")
        wait(lambda: state()["launcherSelection"] == 1, "launcher next")
        key("Up")
        wait(lambda: state()["launcherSelection"] == 0, "launcher previous")
        checks["launcher_arrow_navigation"] = True
        click("launcher-search", browser=False)
    text("xterm")
    wait(lambda: state()["launcherQuery"] == "xterm" and state()["launcherResults"], "search native apps")
    checks["launcher_uses_shared_search"] = "xterm" in state()["launcherResults"][0].lower()
    capture("03-application-launcher.png")
    key("Escape")
    wait(lambda: not state()["launcherVisible"], "dismiss launcher")
    checks["escape_dismisses_launcher"] = True
    click("dock-wallpaper", browser=False)
    wait(lambda: state()["snapshot"]["wallpaper"] == "dusk", "change wallpaper")
    checks["wallpaper_action"] = True
    capture("04-before-restart.png")
    expected = state()["snapshot"]
    key("ctrl+q")
    process.wait(timeout=8)
    checks["normal_quit_exits"] = process.returncode == 0
    process = None
    saved = json.loads(session_path.read_text())
    checks["quit_flushes_session"] = all(saved[k] == expected[k] for k in ["session", "browsers", "wallpaper"])
    start()
    actual = state()["snapshot"]
    checks["fresh_process_restores_windows"] = actual["session"] == expected["session"]
    checks["fresh_process_restores_folders_and_preferences"] = actual["browsers"] == expected["browsers"]
    checks["fresh_process_restores_wallpaper"] = actual["wallpaper"] == expected["wallpaper"]
    checks["restored_folders_have_no_error"] = all(not b.get("error") for b in state()["browsers"])
    capture("05-restored-linux-desktop.png")
except Exception as error:
    errors.append(str(error))
    try:
        capture("failure.png")
    except Exception:
        pass
finally:
    try:
        stop()
    except Exception as error:
        errors.append("Shutdown: " + str(error))
    display.terminate()
    display.wait(timeout=5)
    log.close()
    report = {"passed": bool(checks) and all(checks.values()) and not errors,
              "checks": checks, "errors": errors, "screenshots": shots,
              "scope": "Real GTK windows on Linux, driven by X11 mouse and keyboard events; independent process restart. External application launches are not exercised."}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print("Linux graphical evidence:", output)
sys.exit(0 if report["passed"] else 1)
