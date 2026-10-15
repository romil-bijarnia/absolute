#!/usr/bin/env bash
# Native Fedora user installation. No VM, bootloader, or partition operations.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION=check
ACTION_SET=false
APPLY_DESKTOP=false
RESTORE_DIR=

usage() {
    cat <<'EOF'
Usage: script/install_fedora.sh [--check | --install | --uninstall]
       script/install_fedora.sh --install --apply-desktop
       script/install_fedora.sh --apply-desktop
       script/install_fedora.sh --restore-desktop BACKUP_DIRECTORY

--check             Read-only report from the active physical Fedora session.
--install           Install missing Fedora build dependencies with sudo/dnf,
                    build the GTK preview, and install it and the Plasma profile
                    for the current user. Does not activate the profile.
--apply-desktop     Back up KDE preferences, then apply Absolute's Plasma profile.
                    This replaces the current Plasma panels and desktop layout.
--restore-desktop   Restore a named preferences backup. Keeps the backup itself.
--uninstall         Remove managed launchers, binary, and inactive Plasma profile.
                    Keeps desktop session data and all preference backups.
--help              Show this help on any operating system.

Run as your normal user after booting the physical Mac into Fedora aarch64.
No reboot, login replacement, partition changes, or automatic startup is performed.
EOF
}

choose_action() {
    if [[ "$ACTION_SET" == true ]]; then
        printf '%s\n' 'Choose only one main action.' >&2; exit 2
    fi
    ACTION="$1"; ACTION_SET=true
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) choose_action check ;;
        --install) choose_action install ;;
        --uninstall) choose_action uninstall ;;
        --apply-desktop) APPLY_DESKTOP=true ;;
        --restore-desktop)
            choose_action restore
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            RESTORE_DIR="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done
if [[ "$APPLY_DESKTOP" == true ]]; then
    if [[ "$ACTION_SET" == false ]]; then ACTION=apply
    elif [[ "$ACTION" != install ]]; then
        printf '%s\n' '--apply-desktop can be used alone or with --install.' >&2; exit 2
    fi
fi
if [[ "$ACTION" == check ]]; then exec bash "$ROOT_DIR/script/check_fedora.sh"; fi

fail() { printf '%s\n' "$*" >&2; exit 1; }
if [[ "$(uname -s)" != Linux || ! -r /etc/os-release ]]; then
    printf '%s\n' 'Boot the physical Mac into Fedora before running this action. Nothing was installed.' >&2
    exit 2
fi
source /etc/os-release
if [[ "${ID:-}" != fedora || "$(uname -m)" != aarch64 ]]; then
    printf '%s\n' 'This installer requires Fedora aarch64.' >&2; exit 2
fi
[[ "$EUID" -ne 0 ]] || fail 'Run as your normal Fedora user, without sudo. Only package installation uses sudo.'
command -v systemd-detect-virt >/dev/null || fail 'Cannot verify that this is a physical Fedora installation.'
VIRTUALIZATION="$(systemd-detect-virt 2>/dev/null || true)"
[[ "$VIRTUALIZATION" == none ]] || fail "Physical Apple hardware is required; virtualization detected: ${VIRTUALIZATION:-unknown}."
DEVICE_TREE=/sys/firmware/devicetree/base
[[ -r "$DEVICE_TREE/compatible" ]] || DEVICE_TREE=/proc/device-tree
HARDWARE="$(cat "$DEVICE_TREE/model" "$DEVICE_TREE/compatible" 2>/dev/null | tr '\0' '\n' || true)"
[[ "$HARDWARE" == *Apple* || "$HARDWARE" == *apple,* ]] || fail 'Apple hardware could not be verified from the device tree.'
command -v python3 >/dev/null || fail 'python3 is required; install it using Fedora before continuing.'

DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
BIN_DIR="$HOME/.local/bin"
RUNTIME_DIR="$HOME/.local/libexec/absolute"
LAUNCHER="$BIN_DIR/absolute"
DESKTOP_FILE="$DATA_DIR/applications/org.absolute.Preview.desktop"
PROFILE_DIR="$DATA_DIR/plasma/look-and-feel/org.absolute.desktop"
PROFILE_SOURCE="$ROOT_DIR/linux/fedora/plasma/org.absolute.desktop"
BACKUP_ROOT="$STATE_DIR/absolute/plasma-backups"
MANAGED_MARKER=org.absolute.native-install-v1

for path in "$DATA_DIR" "$CONFIG_DIR" "$CACHE_DIR" "$STATE_DIR" "$BIN_DIR" "$RUNTIME_DIR"; do
    [[ "$path" == /* ]] || fail 'HOME and XDG directories must be absolute paths.'
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || fail 'Installation paths cannot contain newline characters.'
    parent="$path"
    while [[ ! -e "$parent" ]]; do parent="$(dirname "$parent")"; done
    [[ -d "$parent" && -O "$parent" ]] || fail "Installation destination is not user-owned: $parent"
done

check_managed_paths() {
    [[ ! -L "$RUNTIME_DIR" && ! -L "$PROFILE_DIR" && ! -L "$LAUNCHER" && ! -L "$DESKTOP_FILE" ]] || fail 'Managed installation paths must not be symbolic links.'
    if [[ -e "$RUNTIME_DIR" ]] && [[ ! -f "$RUNTIME_DIR/.absolute-managed" || "$(cat "$RUNTIME_DIR/.absolute-managed")" != "$MANAGED_MARKER" ]]; then fail "Unmanaged directory already exists: $RUNTIME_DIR"; fi
    if [[ -e "$PROFILE_DIR" ]] && [[ ! -f "$PROFILE_DIR/.absolute-managed" || "$(cat "$PROFILE_DIR/.absolute-managed")" != "$MANAGED_MARKER" ]]; then fail "Unmanaged profile already exists: $PROFILE_DIR"; fi
    if [[ -e "$LAUNCHER" ]] && ! grep -q '^# Absolute native Fedora launcher$' "$LAUNCHER"; then fail "Existing launcher is not managed by this installer: $LAUNCHER"; fi
    if [[ -e "$DESKTOP_FILE" ]] && ! grep -q '^X-Absolute-Managed=true$' "$DESKTOP_FILE"; then fail "Existing desktop entry is not managed by this installer: $DESKTOP_FILE"; fi
}

install_profile() {
    [[ -f "$PROFILE_SOURCE/metadata.json" ]] || fail 'The source archive is missing the Absolute Plasma profile.'
    mkdir -p "$(dirname "$PROFILE_DIR")"
    local staged
    staged="$(mktemp -d "$(dirname "$PROFILE_DIR")/.absolute-profile.XXXXXX")"
    cp -a "$PROFILE_SOURCE/." "$staged/"
    printf '%s\n' "$MANAGED_MARKER" > "$staged/.absolute-managed"
    if [[ -d "$PROFILE_DIR" ]]; then
        local previous="$PROFILE_DIR.previous.$$"
        mv "$PROFILE_DIR" "$previous"
        if mv "$staged" "$PROFILE_DIR"; then rm -rf -- "$previous"
        else mv "$previous" "$PROFILE_DIR"; fail 'Profile installation failed; the previous profile was restored.'; fi
    else mv "$staged" "$PROFILE_DIR"
    fi
}

plasma_preflight() {
    [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* && -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || fail 'Apply the profile from an active KDE Plasma session.'
    command -v plasma-apply-lookandfeel >/dev/null || fail 'plasma-apply-lookandfeel is unavailable.'
    plasmashell --version 2>/dev/null | grep -Eq 'plasmashell 6\.' || fail 'The profile requires KDE Plasma 6.'
    local app
    for app in dolphin firefox konsole systemsettings; do
        command -v "$app" >/dev/null || fail "Install the Fedora $app application before applying the profile."
    done
    python3 - "$ROOT_DIR/linux/fedora/plasma/profile.json" "$DATA_DIR" "$PROFILE_SOURCE" <<'PY'
import json, os, shutil, subprocess, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
qdbus = next((path for name in ["qdbus6", "qdbus", "/usr/lib64/qt6/bin/qdbus"] if (path := shutil.which(name))), None)
if not qdbus: raise SystemExit("Qt's qdbus tool is required to verify the live Plasma shell before resetting its layout.")
listing = subprocess.run([qdbus, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript",
    'print("ABSOLUTE_PREFLIGHT=" + JSON.stringify(knownWidgetTypes));'],
    check=True, capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"}, timeout=15)
responses = [line.split("=", 1)[1] for line in listing.stdout.splitlines() if line.startswith("ABSOLUTE_PREFLIGHT=")]
if not responses: raise SystemExit("Plasma did not report its available widgets; no layout was changed.")
plugins = set(json.loads(responses[-1]))
missing = [plugin for plugin in manifest["requiredWidgetIds"] if plugin not in plugins]
directories = [Path(sys.argv[2])] + [Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p.startswith("/")]
for alternatives in manifest["requiredApplicationDesktopIds"]:
    if not any((directory / "applications" / name).is_file() for directory in directories for name in alternatives):
        missing.append("application: " + " or ".join(alternatives))
for relative in ["color-schemes/BreezeDark.colors", "icons/breeze-dark/index.theme", "plasma/desktoptheme/default/metadata.json"]:
    if not any((directory / relative).is_file() for directory in directories):
        missing.append(relative)
for relative in ["metadata.json", "contents/defaults", "contents/layouts/org.kde.plasma.desktop-layout.js", "contents/images/ocean.svg", "contents/images/absolute-symbolic.svg"]:
    if not (Path(sys.argv[3]) / relative).is_file(): missing.append("profile: " + relative)
if missing:
    raise SystemExit("Plasma preflight failed before layout reset:\n- " + "\n- ".join(missing))
print("Plasma applets, applications, appearance assets, and Absolute profile verified.")
PY
}

desktop_backup() {
    python3 - "$CONFIG_DIR" "$HOME" "$BACKUP_ROOT" <<'PY'
import datetime, json, os, shutil, sys
from pathlib import Path
config, home, root = map(Path, sys.argv[1:])
items = ["kdeglobals", "plasmarc", "plasmashellrc", "plasma-org.kde.plasma.desktop-appletsrc",
         "kglobalshortcutsrc", "plasma-apply-lookandfeelrc", "kdedefaults", "Trolltech.conf",
         "gtkrc", "gtkrc-2.0", "gtk-3.0", "gtk-4.0", "kwinrc", "ksplashrc", "kcminputrc"]
# KDE can follow preference symlinks while writing; a copied symlink would not
# preserve the original target's contents. Stop before activation in that case.
for item in items:
    source = config / item
    links = [source] if source.is_symlink() else list(source.rglob("*")) if source.is_dir() else []
    if any(path.is_symlink() for path in links):
        raise SystemExit("Profile application requires regular preference files for reversible backup; symbolic link found under " + str(source))
backup = root / (datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + str(os.getpid()))
backup.mkdir(parents=True, mode=0o700)
(backup / "config").mkdir(mode=0o700)
def copy(source, dest):
    if source.is_symlink(): dest.symlink_to(os.readlink(source))
    elif source.is_dir(): shutil.copytree(source, dest, symlinks=True)
    else: shutil.copy2(source, dest)
present = []
for item in items:
    source = config / item
    if source.exists() or source.is_symlink():
        copy(source, backup / "config" / item)
        present.append(item)
manifest = {"schema": "org.absolute.plasma-backup-v1", "config_home": str(config),
            "user_home": str(home), "items": items, "present": present}
(backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(backup)
PY
}

apply_desktop() {
    # The desktop surface (WhiteSur, fonts, wallpaper, layout, shortcuts, login screen)
    # is owned by script/absolute_surface.sh; it takes its own preferences backup.
    bash "$ROOT_DIR/script/absolute_surface.sh" --install --no-packages
    bash "$ROOT_DIR/script/absolute_surface.sh" --apply
}

restore_desktop() {
    [[ -d "$RESTORE_DIR" && -f "$RESTORE_DIR/manifest.json" ]] || fail 'Choose a backup directory containing manifest.json.'
    command -v pgrep >/dev/null || fail 'pgrep is required to verify that Plasma has stopped before restoring preferences.'
    local restart_shell=false
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user stop plasma-plasmashell.service
        restart_shell=true
        trap 'systemctl --user start plasma-plasmashell.service || true' EXIT
    fi
    if pgrep -u "$EUID" -x plasmashell >/dev/null; then
        fail 'Plasma is running outside its user service. Sign out, then restore from a Fedora text console so it cannot overwrite the restored files.'
    fi
    python3 - "$RESTORE_DIR" "$CONFIG_DIR" "$HOME" "$BACKUP_ROOT" <<'PY'
import json, os, shutil, sys, tempfile
from pathlib import Path
backup, config, home, root = map(Path, sys.argv[1:])
allowed = {"kdeglobals", "plasmarc", "plasmashellrc", "plasma-org.kde.plasma.desktop-appletsrc",
           "kglobalshortcutsrc", "plasma-apply-lookandfeelrc", "kdedefaults", "Trolltech.conf",
           "gtkrc", "gtkrc-2.0", "gtk-3.0", "gtk-4.0", "kwinrc", "ksplashrc", "kcminputrc"}
if root.resolve() not in backup.resolve().parents:
    raise SystemExit("Backup must be inside this user's Absolute backup directory.")
manifest = json.loads((backup / "manifest.json").read_text())
if (manifest.get("schema") != "org.absolute.plasma-backup-v1" or
    manifest.get("config_home") != str(config) or manifest.get("user_home") != str(home) or
    set(manifest.get("items", [])) != allowed or not set(manifest.get("present", [])).issubset(allowed)):
    raise SystemExit("Backup manifest does not match this user's known preference paths.")
for item in manifest["present"]:
    source = backup / "config" / item
    if not source.exists() and not source.is_symlink():
        raise SystemExit("Backup is incomplete: " + item)
def copy(source, dest):
    if source.is_symlink(): dest.symlink_to(os.readlink(source))
    elif source.is_dir(): shutil.copytree(source, dest, symlinks=True)
    else: shutil.copy2(source, dest)
config.mkdir(parents=True, exist_ok=True)
# Stage every restore before replacing anything; retain displaced files if a move fails.
with tempfile.TemporaryDirectory(prefix=".absolute-restore-", dir=config) as staging:
    staged = Path(staging)
    for item in manifest["present"]: copy(backup / "config" / item, staged / item)
    previous = backup / ("before-restore-" + str(os.getpid()))
    previous.mkdir(mode=0o700)
    changed = []
    try:
        for item in sorted(allowed):
            target = config / item
            existed = target.exists() or target.is_symlink()
            if existed: shutil.move(str(target), str(previous / item))
            changed.append((item, existed))
            if item in manifest["present"]: shutil.move(str(staged / item), str(target))
    except OSError:
        for item, existed in reversed(changed):
            target = config / item
            if target.is_dir() and not target.is_symlink(): shutil.rmtree(target)
            elif target.exists() or target.is_symlink(): target.unlink()
            if existed: shutil.move(str(previous / item), str(target))
        raise
    print("Preferences displaced by restore were retained at " + str(previous))
print("Restored preferences from " + str(backup))
PY
    if [[ "$restart_shell" == true ]]; then systemctl --user start plasma-plasmashell.service; trap - EXIT; fi
    printf '%s\n' 'Sign out and back in when convenient so all applications reload the restored appearance.'
}

uninstall_profile_preflight() {
    python3 - "$CONFIG_DIR" "$BACKUP_ROOT" <<'PY'
import json, os, shutil, subprocess, sys
from pathlib import Path
from urllib.parse import unquote
config, backups = map(Path, sys.argv[1:])
profile = "org.absolute.desktop"
def refuse(reason):
    raise SystemExit(reason + "\nRestore an earlier desktop backup before uninstalling. Backups: " + str(backups))

# Appearance-only theme changes can leave these references in the saved layout.
for name in ["plasma-org.kde.plasma.desktop-appletsrc", "plasmashellrc"]:
    path = config / name
    if path.exists() or path.is_symlink():
        try:
            contents = path.read_text(errors="replace")
        except OSError:
            refuse("Cannot check saved Plasma preferences: " + str(path))
        if profile in unquote(contents):
            refuse("Saved Plasma layout still references Absolute's panels or assets: " + str(path))

if not shutil.which("pgrep"):
    refuse("pgrep is required to verify that Absolute's live panels are unused.")
running = subprocess.run(["pgrep", "-u", str(os.geteuid()), "-x", "plasmashell"], capture_output=True, timeout=10)
if running.returncode == 1:
    print("No saved Absolute layout references or running Plasma shell found.")
    sys.exit(0)
if running.returncode != 0:
    refuse("Could not determine whether Plasma is running.")
qdbus = next((path for name in ["qdbus6", "qdbus", "/usr/lib64/qt6/bin/qdbus"] if (path := shutil.which(name))), None)
if not qdbus:
    refuse("Qt's qdbus tool is required to inspect the running Plasma layout before uninstalling.")
script = r'''
(function () {
    var references = [];
    panels().forEach(function (panel) {
        var previous = panel.currentConfigGroup;
        panel.currentConfigGroup = ["Absolute"];
        if (panel.readConfig("profile", "") === "org.absolute.desktop") references.push("panel:" + panel.id);
        panel.currentConfigGroup = previous;
        panel.widgets().forEach(function (widget) {
            var group = widget.currentConfigGroup;
            widget.currentConfigGroup = ["General"];
            if (String(widget.readConfig("icon", "")).indexOf("org.absolute.desktop") >= 0) references.push("icon:" + widget.id);
            widget.currentConfigGroup = group;
        });
    });
    desktops().forEach(function (desktop) {
        var previous = desktop.currentConfigGroup;
        desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        if (String(desktop.readConfig("Image", "")).indexOf("org.absolute.desktop") >= 0) references.push("wallpaper:" + desktop.id);
        desktop.currentConfigGroup = previous;
    });
    print("ABSOLUTE_LIVE_REFERENCES=" + JSON.stringify(references));
}());
'''
try:
    observed = subprocess.run([qdbus, "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script],
                              capture_output=True, text=True, timeout=15)
    responses = [line.split("=", 1)[1] for line in observed.stdout.splitlines() if line.startswith("ABSOLUTE_LIVE_REFERENCES=")]
    references = json.loads(responses[-1]) if observed.returncode == 0 and responses else None
except (OSError, subprocess.TimeoutExpired, ValueError):
    references = None
if not isinstance(references, list):
    refuse("Could not verify whether the running Plasma layout still uses Absolute's assets.")
if references:
    refuse("The running Plasma layout still uses Absolute's panels, wallpaper, or icons.")
print("Saved and live Plasma layouts no longer reference Absolute's profile assets.")
PY
}

case "$ACTION" in
    install)
        check_managed_paths
        [[ -f "$ROOT_DIR/linux/Package.swift" && -f "$PROFILE_SOURCE/metadata.json" ]] || fail 'Run from a complete Absolute source checkout or archive.'
        PACKAGES=(swift-lang clang gcc pkgconf-pkg-config gtk4-devel glib2-devel adwaita-icon-theme xdg-utils desktop-file-utils)
        MISSING=()
        for package in "${PACKAGES[@]}"; do rpm -q "$package" >/dev/null 2>&1 || MISSING+=("$package"); done
        if [[ ${#MISSING[@]} -gt 0 ]]; then
            printf 'Installing missing Fedora packages: %s\n' "${MISSING[*]}"
            sudo dnf install -y --setopt=install_weak_deps=False "${MISSING[@]}"
        fi
        pkg-config --exists gtk4 gio-unix-2.0 || fail 'GTK/GIO development files are missing.'
        BUILD_DIR="$CACHE_DIR/absolute/build/fedora-linux"
        swift build --package-path "$ROOT_DIR/linux" --scratch-path "$BUILD_DIR" --configuration release --jobs 4
        BUILT_BIN="$(swift build --package-path "$ROOT_DIR/linux" --scratch-path "$BUILD_DIR" --configuration release --show-bin-path)/AbsoluteLinux"
        [[ -x "$BUILT_BIN" ]] || fail 'The native build did not produce AbsoluteLinux.'
        "$BUILT_BIN" --help
        mkdir -p "$RUNTIME_DIR" "$BIN_DIR" "$(dirname "$DESKTOP_FILE")"
        install -m 0755 "$BUILT_BIN" "$RUNTIME_DIR/AbsoluteLinux.next"
        mv -f "$RUNTIME_DIR/AbsoluteLinux.next" "$RUNTIME_DIR/AbsoluteLinux"
        printf '%s\n' "$MANAGED_MARKER" > "$RUNTIME_DIR/.absolute-managed"
        cat > "$LAUNCHER.next" <<'EOF'
#!/usr/bin/env bash
# Absolute native Fedora launcher
set -euo pipefail
exec "$HOME/.local/libexec/absolute/AbsoluteLinux" --project "$HOME" "$@"
EOF
        chmod 0755 "$LAUNCHER.next"
        mv -f "$LAUNCHER.next" "$LAUNCHER"
        python3 - "$DESKTOP_FILE.next.desktop" "$LAUNCHER" <<'PY'
from pathlib import Path
import sys
def desktop_argument(value):
    # https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html
    value = value.replace("%", "%%")
    value = "".join("\\" + char if char in '\\"`$' else char for char in value)
    return '"' + value.replace("\\", "\\\\") + '"'
Path(sys.argv[1]).write_text("[Desktop Entry]\nType=Application\nName=Absolute Desktop Preview\n"
    "Comment=Native desktop and file browser\nExec=/usr/bin/env -- " + desktop_argument(sys.argv[2]) +
    "\nIcon=user-desktop\nTerminal=false\nCategories=System;Utility;\nX-Absolute-Managed=true\n")
PY
        desktop-file-validate "$DESKTOP_FILE.next.desktop"
        mv -f "$DESKTOP_FILE.next.desktop" "$DESKTOP_FILE"
        install_profile
        update-desktop-database "$DATA_DIR/applications"
        printf 'Installed Absolute Desktop Preview: %s\n' "$LAUNCHER"
        printf 'Installed Plasma profile: %s\n' "$PROFILE_DIR"
        if [[ "$APPLY_DESKTOP" == true ]]; then apply_desktop
        else printf '%s\n' 'To activate the backed-up Plasma layout, run: bash script/install_fedora.sh --apply-desktop'; fi
        ;;
    apply) check_managed_paths; apply_desktop ;;
    restore) restore_desktop ;;
    uninstall)
        check_managed_paths
        ACTIVE_PROFILE=
        if [[ -d "$PROFILE_DIR" ]]; then
            command -v kreadconfig6 >/dev/null || fail 'kreadconfig6 is required to verify that the installed Plasma profile is inactive.'
            ACTIVE_PROFILE="$(kreadconfig6 --file "$CONFIG_DIR/kdeglobals" --group KDE --key LookAndFeelPackage --default org.kde.breeze.desktop)"
            [[ "$ACTIVE_PROFILE" != org.absolute.desktop ]] || fail "Restore a desktop backup before uninstalling the active profile. Backups: $BACKUP_ROOT"
            uninstall_profile_preflight
        fi
        rm -f -- "$LAUNCHER" "$DESKTOP_FILE"
        [[ ! -d "$RUNTIME_DIR" ]] || rm -rf -- "$RUNTIME_DIR"
        [[ ! -d "$PROFILE_DIR" ]] || rm -rf -- "$PROFILE_DIR"
        if command -v update-desktop-database >/dev/null && [[ -d "$DATA_DIR/applications" ]]; then update-desktop-database "$DATA_DIR/applications"; fi
        printf '%s\n' 'Removed the managed Absolute installation. Session data and preference backups were retained.'
        ;;
esac
