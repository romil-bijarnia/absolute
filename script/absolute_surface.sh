#!/usr/bin/env bash
# Absolute surface installer for Fedora KDE Plasma 6.
#
# Turns a Fedora Plasma session into Absolute's macOS-like desktop: menu bar,
# floating Dock, WhiteSur window decorations, icons and cursors, Inter and
# JetBrains Mono, the night wallpaper, KWin's Magic Lamp minimise, the centred
# search, macOS-style shortcuts, the Konsole profile and the login screen.
# Runs as the normal user; sudo is used only for packages and the login screen.
# Works on the physical Fedora Asahi installation and inside Absolute's VM.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_ID=org.absolute.desktop
PROFILE_SOURCE="$ROOT_DIR/linux/fedora/plasma/$PROFILE_ID"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
PROFILE_DIR="$DATA_DIR/plasma/look-and-feel/$PROFILE_ID"
THEME_CACHE="$CACHE_DIR/absolute/whitesur"
BACKUP_ROOT="$STATE_DIR/absolute/plasma-backups"
MANAGED_MARKER=org.absolute.native-install-v1
WALLPAPER_SIZE="${ABSOLUTE_WALLPAPER_SIZE:-3456x2234}"

# WhiteSur is a dependency, fetched at these exact commits and never vendored.
WHITESUR_KDE=cf4df59ce91004f7ea39358b1b8ff917d5c329f7
WHITESUR_ICONS=73d8040da51a9ed74e47c7366e7e9ff437601a5c
WHITESUR_CURSORS=e190baf618ed95ee217d2fd45589bd309b37672b
WHITESUR_GTK=d5782652d412137e26fb8ff55b55a5572e4c6995

PACKAGES=(plasma-desktop plasma-workspace sddm sddm-kcm kde-gtk-config breeze-gtk kvantum
          dolphin konsole kate gwenview elisa okular ark spectacle kcalc plasma-systemmonitor
          plasma-discover firefox keepassxc
          rsms-inter-fonts jetbrains-mono-fonts brightnessctl
          git python3-numpy python3-pillow rsync)

DO_PACKAGES=true; DO_THEMES=true; DO_PROFILE=true; DO_APPLY=false; DO_SDDM=false; DO_FIREFOX=true; DO_MAC_KEYS=false; DO_DOCK=false
ACTION=install
ACTION_SET=false
RESTORE_DIR=

usage() {
    cat <<'EOF'
Usage: script/absolute_surface.sh [--check | --install | --apply | --all | --restore BACKUP]
       options: --no-packages --no-themes --no-firefox --login-screen --mac-keys --dock

--check       Report what is installed and active; changes nothing.
--install     Install packages (sudo dnf), WhiteSur themes (user-local), fonts, the
              wallpaper and the Absolute profile. Leaves the current desktop as it is.
--apply       Back up the current Plasma preferences, then switch the running session
              to Absolute's desktop. Requires an active Plasma session.
--all         --install followed by --apply, plus --sddm when sudo is available.
--login-screen
              Set up the login screen (alone, or together with another action): Absolute's
              wallpaper, WhiteSur colours, icons and cursors, for Plasma Login Manager
              (Fedora 44+) or SDDM. Uses sudo.
--mac-keys    Mac keyboard in every application through Toshy (Cmd+C/V/Q/W/T/Tab and
              the rest, terminal-aware), fetched at a pinned commit. Needs a sign-out.
--dock        Build and install Absolute's Dock (replaces the Plasma dock panel) and the
              Genie minimise effect for KWin, from this checkout. Needs sudo for the
              build packages and the effect plugin; the Dock starts with the session.
--restore     Restore a preferences backup made by --apply.
EOF
}

fail() { printf '%s\n' "$*" >&2; exit 1; }
note() { printf '\033[1m%s\033[0m\n' "$*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) ACTION=check; ACTION_SET=true ;;
        --install) ACTION=install; ACTION_SET=true ;;
        --apply) ACTION=apply; ACTION_SET=true ;;
        --all) ACTION=all; ACTION_SET=true ;;
        --sddm|--login-screen) DO_SDDM=true; [[ "$ACTION_SET" == true ]] || ACTION=login ;;
        --mac-keys) DO_MAC_KEYS=true; [[ "$ACTION_SET" == true ]] || ACTION=mackeys ;;
        --dock) DO_DOCK=true; [[ "$ACTION_SET" == true ]] || ACTION=dock ;;
        --no-packages) DO_PACKAGES=false ;;
        --no-themes) DO_THEMES=false ;;
        --no-firefox) DO_FIREFOX=false ;;
        --restore) ACTION=restore; ACTION_SET=true; [[ $# -ge 2 ]] || { usage >&2; exit 2; }; RESTORE_DIR="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

[[ "$(uname -s)" == Linux && -r /etc/os-release ]] || fail 'Run this inside Fedora.'
source /etc/os-release
[[ "${ID:-}" == fedora ]] || fail 'This installer targets Fedora.'
[[ "$EUID" -ne 0 ]] || fail 'Run as your normal user, without sudo.'

# When run over SSH into a machine with a Plasma session, pick up that session's bus.
session_env() {
    local uid runtime
    uid="$(id -u)"; runtime="${XDG_RUNTIME_DIR:-/run/user/$uid}"
    export XDG_RUNTIME_DIR="$runtime"
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || { [[ -S "$runtime/bus" ]] && export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"; }
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        local socket
        socket="$(ls "$runtime"/wayland-[0-9] 2>/dev/null | head -1 || true)"
        [[ -n "$socket" ]] && export WAYLAND_DISPLAY="$(basename "$socket")"
    fi
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
    [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] || export XDG_CURRENT_DESKTOP=KDE
}

plasma_running() { pgrep -u "$EUID" -x plasmashell >/dev/null; }

install_packages() {
    local missing=()
    for package in "${PACKAGES[@]}"; do rpm -q "$package" >/dev/null 2>&1 || missing+=("$package"); done
    if [[ ${#missing[@]} -gt 0 ]]; then
        note "Installing Fedora packages: ${missing[*]}"
        sudo dnf -y install "${missing[@]}"
    else
        note "Fedora packages already installed."
    fi
}

fetch_pinned() {
    # fetch_pinned NAME URL COMMIT: a shallow checkout of exactly that commit.
    local dir="$THEME_CACHE/$1" url="$2" commit="$3"
    if [[ -d "$dir/.git" ]] && [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$commit" ]]; then return 0; fi
    rm -rf "$dir"; mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
    git -C "$dir" checkout -q FETCH_HEAD
}

install_themes() {
    command -v git >/dev/null || fail 'git is required to fetch WhiteSur.'
    mkdir -p "$THEME_CACHE"
    note "Fetching WhiteSur at its pinned commits"
    fetch_pinned kde https://github.com/vinceliuice/WhiteSur-kde "$WHITESUR_KDE"
    fetch_pinned icons https://github.com/vinceliuice/WhiteSur-icon-theme "$WHITESUR_ICONS"
    fetch_pinned cursors https://github.com/vinceliuice/WhiteSur-cursors "$WHITESUR_CURSORS"
    fetch_pinned gtk https://github.com/vinceliuice/WhiteSur-gtk-theme "$WHITESUR_GTK"
    note "Installing WhiteSur for KDE (decorations, colours, Plasma style, Kvantum, splash)"
    (cd "$THEME_CACHE/kde" && bash ./install.sh >/dev/null)
    note "Installing WhiteSur icons"
    (cd "$THEME_CACHE/icons" && bash ./install.sh -a >/dev/null)
    note "Installing WhiteSur cursors"
    (cd "$THEME_CACHE/cursors" && bash ./install.sh >/dev/null)
    note "Installing WhiteSur for GTK applications"
    (cd "$THEME_CACHE/gtk" && bash ./install.sh -c Dark -o normal -l </dev/null >/dev/null 2>&1) || printf 'WhiteSur GTK install reported a problem; GTK applications keep their current theme.\n'
    # Kvantum theme file for the dark variant.
    mkdir -p "$CONFIG_DIR/Kvantum"
    printf '[General]\ntheme=WhiteSurDark\n' > "$CONFIG_DIR/Kvantum/kvantum.kvconfig"
    # GTK settings so GTK applications match without a running kded.
    mkdir -p "$CONFIG_DIR/gtk-3.0" "$CONFIG_DIR/gtk-4.0"
    for version in gtk-3.0 gtk-4.0; do
        cat > "$CONFIG_DIR/$version/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=WhiteSur-Dark
gtk-icon-theme-name=WhiteSur-dark
gtk-cursor-theme-name=WhiteSur-cursors
gtk-font-name=Inter 10
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=close,minimize,maximize:
EOF
    done
}

install_wallpaper() {
    local target="$1/contents/images/absolute-night.png"
    note "Rendering the wallpaper at $WALLPAPER_SIZE"
    python3 "$ROOT_DIR/script/wallpaper_absolute.py" --output "$target" --size "$WALLPAPER_SIZE" >/dev/null
}

install_profile() {
    [[ -f "$PROFILE_SOURCE/metadata.json" ]] || fail 'The checkout is missing the Absolute Plasma profile.'
    mkdir -p "$(dirname "$PROFILE_DIR")"
    local staged
    staged="$(mktemp -d "$(dirname "$PROFILE_DIR")/.absolute-profile.XXXXXX")"
    cp -a "$PROFILE_SOURCE/." "$staged/"
    printf '%s\n' "$MANAGED_MARKER" > "$staged/.absolute-managed"
    install_wallpaper "$staged"
    rm -rf "$PROFILE_DIR"
    mv "$staged" "$PROFILE_DIR"
    note "Installed the Absolute profile at $PROFILE_DIR"
    # Absolute's own menu bar applets: application name, search, Control Centre.
    mkdir -p "$DATA_DIR/plasma/plasmoids"
    for applet in "$ROOT_DIR"/linux/fedora/plasma/applets/*/; do
        local id
        id="$(basename "$applet")"
        rm -rf "$DATA_DIR/plasma/plasmoids/$id"
        cp -a "$applet" "$DATA_DIR/plasma/plasmoids/$id"
    done
    # The same image as a wallpaper package, so it is listed in System Settings > Wallpaper.
    local pack="$DATA_DIR/wallpapers/Absolute"
    mkdir -p "$pack/contents/images"
    cp "$PROFILE_DIR/contents/images/absolute-night.png" "$pack/contents/images/$WALLPAPER_SIZE.png"
    python3 - "$pack/contents/images/$WALLPAPER_SIZE.png" "$pack/contents/screenshot.png" <<'PY'
import sys
from PIL import Image
image = Image.open(sys.argv[1]); image.thumbnail((800, 800)); image.save(sys.argv[2])
PY
    cat > "$pack/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/Wallpaper",
    "KPlugin": {
        "Id": "Absolute",
        "Name": "Absolute Night",
        "Description": "Glassy ribbons of light over a deep blue night.",
        "Authors": [{"Name": "Absolute contributors"}],
        "License": "MIT"
    }
}
EOF
    # Konsole profile matching the Mac's terminal: black, soft grey text, JetBrains Mono.
    mkdir -p "$DATA_DIR/konsole"
    cp "$ROOT_DIR/linux/fedora/konsole/Absolute.profile" "$ROOT_DIR/linux/fedora/konsole/Absolute.colorscheme" "$DATA_DIR/konsole/"
}

desktop_backup() {
    python3 - "$CONFIG_DIR" "$HOME" "$BACKUP_ROOT" <<'PY'
import datetime, json, os, shutil, sys
from pathlib import Path
config, home, root = map(Path, sys.argv[1:])
items = ["kdeglobals", "plasmarc", "plasmashellrc", "plasma-org.kde.plasma.desktop-appletsrc",
         "kglobalshortcutsrc", "plasma-apply-lookandfeelrc", "kdedefaults", "Trolltech.conf",
         "gtkrc", "gtkrc-2.0", "gtk-3.0", "gtk-4.0", "kwinrc", "ksplashrc", "kcminputrc"]
extra = ["krunnerrc", "plasmanotifyrc", "kscreenlockerrc", "konsolerc", "dolphinrc", "Kvantum"]
backup = root / (datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + str(os.getpid()))
backup.mkdir(parents=True, mode=0o700)
(backup / "config").mkdir(mode=0o700)
def copy(source, dest):
    if source.is_symlink(): dest.symlink_to(os.readlink(source))
    elif source.is_dir(): shutil.copytree(source, dest, symlinks=True)
    else: shutil.copy2(source, dest)
present = []
for item in items + extra:
    source = config / item
    if source.exists() or source.is_symlink():
        copy(source, backup / "config" / item)
        present.append(item)
manifest = {"schema": "org.absolute.plasma-backup-v1", "config_home": str(config),
            "user_home": str(home), "items": items, "present": [p for p in present if p in items],
            "extra": [p for p in present if p in extra]}
(backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(backup)
PY
}

write_setting() {
    # write_setting FILE GROUP[/SUBGROUP...] KEY VALUE
    local file="$1" groups="$2" key="$3" value="$4" args=()
    IFS='/' read -r -a parts <<< "$groups"
    for part in "${parts[@]}"; do args+=(--group "$part"); done
    kwriteconfig6 --file "$file" "${args[@]}" --key "$key" "$value"
}

qt_key_codes() {
    # qt_key_codes "Ctrl+Up" "Meta+W" ... : prints busctl arguments for a(ai) key sequences.
    python3 - "$@" <<'PY'
import sys
modifiers = {"meta": 0x10000000, "super": 0x10000000, "cmd": 0x10000000, "ctrl": 0x04000000, "alt": 0x08000000, "shift": 0x02000000}
special = {"space": 0x20, "tab": 0x01000001, "esc": 0x01000000, "escape": 0x01000000, "return": 0x01000004, "enter": 0x01000004,
           "up": 0x01000013, "down": 0x01000015, "left": 0x01000012, "right": 0x01000014, "pgup": 0x01000016, "pgdown": 0x01000017,
           "home": 0x01000010, "end": 0x01000011, "backspace": 0x01000003, "delete": 0x01000007, "print": 0x01000009}
codes = []
if sys.argv[1:] == ["none"]:
    print("0"); raise SystemExit
for chord in sys.argv[1:]:
    code = 0
    for part in chord.split("+"):
        key = part.strip().lower()
        if key in modifiers: code |= modifiers[key]
        elif key in special: code |= special[key]
        elif len(key) == 1: code |= ord(key.upper())
        elif key.startswith("f") and key[1:].isdigit(): code |= 0x01000030 + int(key[1:]) - 1
        else: raise SystemExit("Unknown key: " + part)
    codes.append(code)
print(str(len(codes)) + " " + " ".join("4 %d 0 0 0" % code for code in codes))
PY
}

set_shortcut() {
    # set_shortcut COMPONENT ACTION COMPONENT-NAME ACTION-NAME CHORD...
    local component="$1" action="$2" component_name="$3" action_name="$4"; shift 4
    local keys
    keys="$(qt_key_codes "$@")" || return 1
    # 6 = NoAutoloading | SetPresent: replace whatever the service holds for this action.
    # shellcheck disable=SC2086
    if ! busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setShortcutKeys "asa(ai)u" 4 "$component" "$action" "$component_name" "$action_name" $keys 6 >/dev/null 2>&1; then
        printf 'Shortcut not set (no shortcut service): %s/%s\n' "$component" "$action"
    fi
}

apply_settings() {
    note "Applying Absolute's window, shortcut and application settings"
    # Window manager: Magic Lamp minimise, blur, Overview, centred placement, no borders.
    write_setting kwinrc Plugins magiclampEnabled true
    write_setting kwinrc Plugins squashEnabled false
    write_setting kwinrc Plugins blurEnabled true
    write_setting kwinrc Plugins overviewEnabled true
    write_setting kwinrc Plugins contrastEnabled true
    # Windows open and close with the Mac's quick scale, not Plasma's fade.
    write_setting kwinrc Plugins scaleEnabled true
    write_setting kwinrc Plugins fadeEnabled false
    write_setting kwinrc Plugins glideEnabled false
    write_setting kwinrc Windows Placement Centered
    write_setting kwinrc org.kde.kdecoration2 ButtonsOnLeft XIA
    write_setting kwinrc org.kde.kdecoration2 ButtonsOnRight ""
    write_setting kwinrc org.kde.kdecoration2 BorderSize None
    write_setting kwinrc org.kde.kdecoration2 BorderSizeAuto false
    write_setting kwinrc TabBox LayoutName big_icons
    # Fonts: Inter for the interface, JetBrains Mono for code.
    write_setting kdeglobals General font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals General menuFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals General toolBarFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals General smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals General fixed "JetBrains Mono,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals WM activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
    write_setting kdeglobals KDE SingleClick false
    # Search floats in the middle of the screen; notifications arrive top right.
    write_setting krunnerrc General FreeFloating true
    write_setting plasmanotifyrc Notifications PopupPosition TopRight
    # Lock screen shows the same wallpaper.
    write_setting kscreenlockerrc Greeter/Wallpaper/org.kde.image/General Image "file://$PROFILE_DIR/contents/images/absolute-night.png"
    # Konsole opens with Absolute's profile.
    write_setting konsolerc "Desktop Entry" DefaultProfile Absolute.profile
    write_setting konsolerc KonsoleWindow ShowMenuBarByDefault false
    # Shortcuts a Mac hand expects, with Plasma's defaults kept as alternatives. KWin hosts
    # the shortcut service in Plasma 6.7 and keeps its own copy, so they are set through it.
    set_shortcut org.kde.krunner.desktop _launch KRunner KRunner "Meta+Space" "Alt+Space" "Alt+F2"
    # Mission Control on Ctrl+Up and App Expose on Ctrl+Down. With the Mac keyboard remapper
    # active, physical Ctrl reaches KWin as Meta, so both spellings are bound and the
    # quick-tile defaults that used Meta+Up/Down give way.
    set_shortcut kwin Overview KWin "Toggle Overview" "Ctrl+Up" "Meta+Up" "Meta+W"
    set_shortcut kwin "Window Quick Tile Top" KWin "Quick Tile Window to the Top" none
    set_shortcut kwin ExposeClass KWin "Toggle Present Windows (Window class)" "Ctrl+Down" "Meta+Down" "Meta+F7"
    set_shortcut kwin "Window Quick Tile Bottom" KWin "Quick Tile Window to the Bottom" none
    set_shortcut kwin "Walk Through Windows" KWin "Walk Through Windows" "Meta+Tab" "Alt+Tab"
    set_shortcut kwin "Walk Through Windows (Reverse)" KWin "Walk Through Windows (Reverse)" "Meta+Shift+Tab" "Alt+Shift+Tab"
    set_shortcut kwin "Window Close" KWin "Close Window" "Meta+Q" "Alt+F4"
    set_shortcut kwin "Window Minimize" KWin "Minimize Window" "Meta+H" "Meta+PgDown"
    set_shortcut kwin "Show Desktop" KWin "Peek at Desktop" "F11" "Meta+D"
    # The system tray keeps its settings in its own inner containment, which the layout
    # script cannot reach: Wi-Fi and battery only, nothing hidden, so no overflow chevron.
    python3 - "$CONFIG_DIR/plasma-org.kde.plasma.desktop-appletsrc" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
trays = re.findall(r"\[Containments\]\[(\d+)\]\nactivityId=[^\n]*\n(?:[^\[]*\n)*?plugin=org\.kde\.plasma\.private\.systemtray", text)
if not trays:
    trays = [m.group(1) for m in re.finditer(r"\[Containments\]\[(\d+)\]\n((?:(?!\[).*\n)*)", text) if "plugin=org.kde.plasma.private.systemtray" in m.group(2)]
open("/tmp/absolute-tray-ids", "w").write(" ".join(trays))
PY
    for tray in $(cat /tmp/absolute-tray-ids 2>/dev/null); do
        for key in extraItems knownItems shownItems; do
            kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group "$tray" --group General --key "$key" "org.kde.plasma.networkmanagement,org.kde.plasma.battery"
        done
        kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc --group Containments --group "$tray" --group General --key hiddenItems ""
    done
    rm -f /tmp/absolute-tray-ids
    # No update badge from Discover's notifier in the bar; Discover itself still updates.
    mkdir -p "$CONFIG_DIR/autostart"
    printf '[Desktop Entry]\nType=Application\nName=Discover Notifier\nHidden=true\n' > "$CONFIG_DIR/autostart/org.kde.discover.notifier.desktop"
    # GTK applications follow the theme through Plasma's GTK bridge when it is running.
    if command -v dbus-send >/dev/null && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        dbus-send --session --dest=org.kde.GtkConfig --type=method_call /GtkConfig org.kde.GtkConfig.setGtkTheme string:WhiteSur-Dark 2>/dev/null || true
    fi
}

reload_session() {
    busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
    systemctl --user restart plasma-krunner.service 2>/dev/null || true
    systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
}

apply_desktop() {
    session_env
    plasma_running || fail 'Apply from a running Plasma session (sign in to the desktop first).'
    command -v plasma-apply-lookandfeel >/dev/null || fail 'plasma-apply-lookandfeel is missing.'
    command -v kwriteconfig6 >/dev/null || fail 'kwriteconfig6 is missing.'
    [[ -f "$PROFILE_DIR/contents/images/absolute-night.png" ]] || fail 'Run --install first; the profile is not installed.'
    for asset in "$DATA_DIR/aurorae/themes/WhiteSur-dark" "$DATA_DIR/icons/WhiteSur-dark" "$DATA_DIR/icons/WhiteSur-cursors" "$DATA_DIR/color-schemes/WhiteSurDark.colors" "$DATA_DIR/plasma/desktoptheme/WhiteSur-dark"; do
        [[ -e "$asset" ]] || fail "WhiteSur is not installed: $asset is missing. Run --install."
    done
    local backup
    backup="$(desktop_backup)"
    note "Preferences backup: $backup"
    printf 'Restore with: bash %q --restore %q\n' "$ROOT_DIR/script/absolute_surface.sh" "$backup"
    plasma-apply-lookandfeel --apply "$PROFILE_ID" --resetLayout || fail "Profile activation failed; restore the backup at $backup"
    apply_settings
    reload_session
    note "Absolute's desktop is active. Sign out and back in once so every application picks up the fonts and theme."
}

install_login_screen() {
    # Fedora 44 ships Plasma Login Manager (a Plasma-native SDDM fork). Its greeter runs as
    # the plasmalogin user, so the wallpaper, cursors, colours and icons it uses must live
    # under /usr/share, and its wallpaper is set in /etc/plasmalogin.conf.d.
    note "Setting up the login screen (sudo)"
    local wallpaper="$PROFILE_DIR/contents/images/absolute-night.png"
    [[ -f "$wallpaper" ]] || fail 'Run --install first; the wallpaper is not rendered.'
    sudo install -d -m 0755 /usr/share/backgrounds/absolute
    sudo install -m 0644 "$wallpaper" /usr/share/backgrounds/absolute/absolute-night.png
    for asset in icons/WhiteSur-cursors icons/WhiteSur-dark icons/WhiteSur color-schemes/WhiteSurDark.colors plasma/desktoptheme/WhiteSur-dark; do
        if [[ -e "$DATA_DIR/$asset" ]]; then
            sudo rm -rf "/usr/share/$asset"
            sudo cp -r "$DATA_DIR/$asset" "/usr/share/$asset"
        fi
    done
    if command -v plasmalogin >/dev/null || [[ -f /etc/plasmalogin.conf ]]; then
        # The greeter reads /etc/plasmalogin.conf itself (its conf.d is not consulted).
        sudo touch /etc/plasmalogin.conf
        sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --key WallpaperPlugin org.kde.image
        sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key Image file:///usr/share/backgrounds/absolute/absolute-night.png
        sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage file:///usr/share/backgrounds/absolute/absolute-night.png
        sudo kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key FillMode 2
        sudo rm -f /etc/plasmalogin.conf.d/absolute.conf
        local greeter_home
        greeter_home="$(getent passwd plasmalogin | cut -d: -f6)"
        if [[ -n "$greeter_home" ]]; then
            sudo install -d -m 0755 -o plasmalogin -g plasmalogin "$greeter_home/.config"
            printf '[General]\nColorScheme=WhiteSurDark\nfont=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nmenuFont=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\ntoolBarFont=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nsmallestReadableFont=Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n\n[Icons]\nTheme=WhiteSur-dark\n\n[KDE]\nSingleClick=false\n' | sudo tee "$greeter_home/.config/kdeglobals" >/dev/null
            printf '[Mouse]\ncursorTheme=WhiteSur-cursors\ncursorSize=24\n' | sudo tee "$greeter_home/.config/kcminputrc" >/dev/null
            printf '[Theme]\nname=WhiteSur-dark\n' | sudo tee "$greeter_home/.config/plasmarc" >/dev/null
            if [[ -f "$CONFIG_DIR/kwinoutputconfig.json" ]]; then
                sudo install -m 0644 "$CONFIG_DIR/kwinoutputconfig.json" "$greeter_home/.config/kwinoutputconfig.json"
            fi
            sudo chown -R plasmalogin:plasmalogin "$greeter_home/.config"
        fi
        note "Login screen set: Absolute wallpaper, WhiteSur colours, icons and cursors, same display scale as the session."
    elif [[ -d /usr/share/sddm ]]; then
        # Older Fedora with plain SDDM: WhiteSur's SDDM theme with Absolute's wallpaper.
        [[ -d "$THEME_CACHE/kde/sddm" ]] || fail 'WhiteSur is not fetched; run --install first.'
        sudo bash -c "cd '$THEME_CACHE/kde/sddm' && bash ./install.sh" >/dev/null
        local theme=/usr/share/sddm/themes/WhiteSur-dark
        [[ -d "$theme" ]] || fail 'The WhiteSur login theme did not install.'
        python3 -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2], quality=92)' "$wallpaper" /tmp/absolute-sddm-background.jpeg
        sudo install -m 0644 /tmp/absolute-sddm-background.jpeg "$theme/background.jpeg"
        rm -f /tmp/absolute-sddm-background.jpeg
        sudo mkdir -p /etc/sddm.conf.d
        printf '[Theme]\nCurrent=WhiteSur-dark\nCursorTheme=WhiteSur-cursors\nFont=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' | sudo tee /etc/sddm.conf.d/absolute.conf >/dev/null
        note "Login screen set to WhiteSur's SDDM theme with Absolute's wallpaper."
    else
        note "No supported login manager found; login screen left as it is."
    fi
}

TOSHY_COMMIT=51bfa66c360b45a0ca74be6afcb2528b8217f9af

install_mac_keys() {
    # Toshy remaps the keyboard per application (xwaykeyz on evdev, a KWin script for
    # the active window), so Cmd behaves as on a Mac everywhere, including terminals.
    note "Installing Toshy for Mac-style shortcuts (sudo for packages)"
    sudo dnf -y -q install gcc python3-devel wayland-devel wayland-protocols-devel libxkbcommon-devel \
        cairo-gobject-devel gobject-introspection-devel dbus-devel systemd-devel >/dev/null
    fetch_pinned toshy https://github.com/RedBearAK/toshy "$TOSHY_COMMIT"
    session_env
    (cd "$THEME_CACHE/toshy" && yes | ./setup_toshy.py install --fancy-pants > "$CACHE_DIR/absolute/toshy-install.log" 2>&1) \
        || fail "Toshy's installer failed; see $CACHE_DIR/absolute/toshy-install.log"
    python3 - "$CONFIG_DIR/toshy/toshy_config.py" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
block = """keyboards_UserCustom_dct = {
    # Absolute: the Mac keyboard reaches a virtual machine under the QEMU names, and the
    # physical Mac under its own; the Cmd key arrives as Super, an Apple layout.
    'QEMU Virtio Keyboard': 'Apple',
    'QEMU QEMU USB Keyboard': 'Apple',
    'Apple Internal Keyboard / Trackpad': 'Apple',
    'Apple SPI Keyboard': 'Apple',
}"""
text, count = re.subn(r"keyboards_UserCustom_dct = \{.*?\n\}", block, text, count=1, flags=re.S)
if count != 1:
    raise SystemExit("Toshy config has no keyboards_UserCustom_dct block")
open(path, "w").write(text)
print("Toshy keyboard types set")
PY
    note "Mac keys installed. Sign out and back in once; Toshy starts with the session."
}

DOCK_BUILD_PACKAGES=(cmake extra-cmake-modules gcc-c++ kwin-devel qt6-qtbase-devel qt6-qtdeclarative-devel
    layer-shell-qt-devel kf6-kwindowsystem-devel kf6-kconfig-devel kf6-kcoreaddons-devel libepoxy-devel
    libdrm-devel mesa-libgbm-devel libxcb-devel xcb-util-devel xcb-util-cursor-devel xcb-util-wm-devel
    xcb-util-keysyms-devel xcb-util-image-devel kf6-kidletime-devel kf6-kcrash-devel kf6-kdecoration-devel
    lcms2-devel libdisplay-info-devel libinput-devel pixman-devel kf6-kpackage-devel kf6-kcmutils-devel
    kf6-knotifications-devel kf6-kservice-devel kf6-ksvg-devel kf6-kguiaddons-devel plasma-activities-devel
    kf6-kauth-devel kf6-kcolorscheme-devel wayland-devel)

install_dock() {
    note "Building Absolute's Dock and the Genie effect (sudo for packages and the effect)"
    local missing=()
    for package in "${DOCK_BUILD_PACKAGES[@]}"; do rpm -q "$package" >/dev/null 2>&1 || missing+=("$package"); done
    if [[ ${#missing[@]} -gt 0 ]]; then sudo dnf -y -q install --skip-unavailable "${missing[@]}"; fi
    local build="$CACHE_DIR/absolute/build"
    mkdir -p "$build" "$HOME/.local/bin" "$CONFIG_DIR/autostart" "$CONFIG_DIR/absolute"
    cmake -S "$ROOT_DIR/linux/dock" -B "$build/dock" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$build/dock" -j"$(nproc)" >/dev/null
    install -m 0755 "$build/dock/absolute-dock" "$HOME/.local/bin/absolute-dock"
    cmake -S "$ROOT_DIR/linux/kwin/genie" -B "$build/genie" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$build/genie" -j"$(nproc)" >/dev/null
    sudo cmake --install "$build/genie" >/dev/null
    # The Dock starts with the session and takes the Plasma dock panel's place. KWin
    # only grants the window-management protocol to clients whose desktop entry declares
    # it, matched by executable path, so the entry is installed as an application too.
    mkdir -p "$DATA_DIR/applications"
    for target in "$DATA_DIR/applications/org.absolute.Dock.desktop" "$CONFIG_DIR/autostart/org.absolute.Dock.desktop"; do
        cat > "$target" <<EOF
[Desktop Entry]
Type=Application
Name=Absolute Dock
Exec=$HOME/.local/bin/absolute-dock
Icon=user-desktop
NoDisplay=true
OnlyShowIn=KDE;
X-KDE-autostart-phase=1
X-KDE-Wayland-Interfaces=org_kde_plasma_window_management
EOF
    done
    update-desktop-database "$DATA_DIR/applications" >/dev/null 2>&1 || true
    if [[ ! -f "$CONFIG_DIR/absolute/dockrc" ]]; then
        cat > "$CONFIG_DIR/absolute/dockrc" <<'EOF'
; Absolute Dock. Sizes in points, as the Mac's Dock keys them.
tileSize=64
largeSize=128
magnification=true
autohide=false
EOF
    fi
    # Genie replaces Magic Lamp and Squash as the minimise animation.
    write_setting kwinrc Plugins absolute_genieEnabled true
    write_setting kwinrc Plugins magiclampEnabled false
    write_setting kwinrc Plugins squashEnabled false
    if plasma_running; then
        session_env
        busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
        busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s \
            'panels().forEach(function (p) { var g = p.currentConfigGroup; p.currentConfigGroup = ["Absolute"]; var role = p.readConfig("role", ""); p.currentConfigGroup = g; if (role === "dock") { p.remove(); } });' >/dev/null 2>&1 || true
        pkill -x absolute-dock >/dev/null 2>&1 || true
        (setsid "$HOME/.local/bin/absolute-dock" >/dev/null 2>&1 &)
    fi
    note "Dock installed: $HOME/.local/bin/absolute-dock (config in $CONFIG_DIR/absolute/dockrc), Genie effect enabled."
}

restore_desktop() {
    [[ -d "$RESTORE_DIR" && -f "$RESTORE_DIR/manifest.json" ]] || fail 'Choose a backup directory containing manifest.json.'
    session_env
    local restart=false
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user stop plasma-plasmashell.service; restart=true
    fi
    python3 - "$RESTORE_DIR" "$CONFIG_DIR" <<'PY'
import json, shutil, sys
from pathlib import Path
backup, config = Path(sys.argv[1]), Path(sys.argv[2])
manifest = json.loads((backup / "manifest.json").read_text())
names = manifest.get("present", []) + manifest.get("extra", [])
for name in manifest.get("items", []) + manifest.get("extra", []):
    target = config / name
    if target.is_dir() and not target.is_symlink(): shutil.rmtree(target)
    elif target.exists() or target.is_symlink(): target.unlink()
for name in names:
    source = backup / "config" / name
    if source.is_dir(): shutil.copytree(source, config / name, symlinks=True)
    else: shutil.copy2(source, config / name)
print("Restored " + str(len(names)) + " preference files from " + str(backup))
PY
    [[ "$restart" == true ]] && systemctl --user start plasma-plasmashell.service
    note "Sign out and back in to finish restoring."
}

check() {
    session_env
    printf 'Fedora: %s\n' "${PRETTY_NAME:-unknown}"
    printf 'Plasma: %s\n' "$(rpm -q --qf '%{VERSION}' plasma-workspace 2>/dev/null || echo 'not installed')"
    printf 'Session: %s\n' "$(plasma_running && echo running || echo 'not running')"
    printf 'Virtualisation: %s\n' "$(systemd-detect-virt 2>/dev/null || echo unknown)"
    for asset in "$DATA_DIR/aurorae/themes/WhiteSur-dark" "$DATA_DIR/icons/WhiteSur-dark" "$DATA_DIR/icons/WhiteSur-cursors" "$DATA_DIR/plasma/desktoptheme/WhiteSur-dark" "$PROFILE_DIR/contents/images/absolute-night.png" "$DATA_DIR/konsole/Absolute.profile" /usr/share/backgrounds/absolute/absolute-night.png; do
        printf '%-10s %s\n' "$([[ -e "$asset" ]] && echo present || echo missing)" "$asset"
    done
    printf 'Active look and feel: %s\n' "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage --default org.kde.breeze.desktop 2>/dev/null || echo unknown)"
    printf 'Fonts: %s\n' "$(fc-list 2>/dev/null | grep -ciE 'Inter|JetBrains' || echo 0) Inter/JetBrains Mono files"
}

case "$ACTION" in
    check) check ;;
    install)
        if [[ "$DO_PACKAGES" == true ]]; then install_packages; fi
        if [[ "$DO_THEMES" == true ]]; then install_themes; fi
        install_profile
        note "Installed. Activate with: bash script/absolute_surface.sh --apply"
        if [[ "$DO_SDDM" == true ]]; then install_login_screen; fi
        ;;
    apply)
        apply_desktop
        if [[ "$DO_SDDM" == true ]]; then install_login_screen; fi
        ;;
    all)
        if [[ "$DO_PACKAGES" == true ]]; then install_packages; fi
        if [[ "$DO_THEMES" == true ]]; then install_themes; fi
        install_profile
        apply_desktop
        if sudo -n true 2>/dev/null || [[ "$DO_SDDM" == true ]]; then install_login_screen
        else note "Login screen skipped (sudo would prompt); run --login-screen later."; fi
        if [[ "$DO_MAC_KEYS" == true ]]; then install_mac_keys; fi
        if [[ "$DO_DOCK" == true ]]; then install_dock; fi
        ;;
    login) install_login_screen ;;
    mackeys) install_mac_keys ;;
    dock) install_dock ;;
    restore) restore_desktop ;;
esac
