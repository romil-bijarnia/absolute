#!/usr/bin/env python3
"""Print `export` lines for the running Plasma session's environment.

Processes started over ssh miss what startplasma sets (the config directory that
holds the look-and-feel defaults, the platform theme, the Wayland socket, the
session bus), so they draw with the wrong icons and settings. Usage:

    eval "$(python3 script/session_env.py)"

Reads the environment of the user's plasmashell process.
"""

import os
import shlex
import subprocess
import sys

KEYS = {
    "DBUS_SESSION_BUS_ADDRESS", "DESKTOP_SESSION", "DISPLAY", "KDE_FULL_SESSION", "KDE_SESSION_VERSION",
    "LANG", "PATH", "QT_QPA_PLATFORM", "QT_QPA_PLATFORMTHEME", "QT_WAYLAND_RECONNECT", "WAYLAND_DISPLAY",
    "XDG_CONFIG_DIRS", "XDG_CONFIG_HOME", "XDG_CURRENT_DESKTOP", "XDG_DATA_DIRS", "XDG_DATA_HOME",
    "XDG_RUNTIME_DIR", "XDG_SEAT", "XDG_SESSION_CLASS", "XDG_SESSION_DESKTOP", "XDG_SESSION_ID",
    "XDG_SESSION_TYPE", "XCURSOR_THEME", "XCURSOR_SIZE", "GTK_RC_FILES", "GTK2_RC_FILES", "SHELL", "HOME",
}


def main():
    user = os.environ.get("USER") or os.getlogin()
    pids = subprocess.run(["pgrep", "-u", user, "-x", "plasmashell"], capture_output=True, text=True).stdout.split()
    if not pids:
        sys.exit("No plasmashell process for this user; sign in to the desktop first.")
    with open(f"/proc/{pids[0]}/environ", "rb") as handle:
        entries = handle.read().split(b"\0")
    for entry in entries:
        if b"=" not in entry:
            continue
        key, value = entry.split(b"=", 1)
        key = key.decode()
        if key in KEYS:
            print(f"export {key}={shlex.quote(value.decode(errors='replace'))}")


if __name__ == "__main__":
    main()
