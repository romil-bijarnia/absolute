#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$1"
BUILD_DIR="${2:-/absolute-linux-build}"
cd "$ROOT_DIR"
swift build --package-path linux --scratch-path "$BUILD_DIR" --jobs 2
BIN_DIR="$(swift build --package-path linux --scratch-path "$BUILD_DIR" --show-bin-path)"
mkdir -p dist/linux research/local
cp "$BIN_DIR/AbsoluteLinux" dist/linux/AbsoluteLinux

Xvfb :99 -screen 0 1440x900x24 -nolisten tcp > research/local/linux-xvfb.log 2>&1 &
DISPLAY_PID=$!
for attempt in {1..30}; do
    if xdotool getdisplaygeometry >/dev/null 2>&1; then break; fi
    sleep 0.1
done
DBUS_SESSION_BUS_ADDRESS="$(dbus-daemon --session --fork --print-address)"
export DBUS_SESSION_BUS_ADDRESS
x11vnc -display :99 -forever -shared -nopw -localhost -rfbport 5900 -quiet \
    > research/local/linux-vnc.log 2>&1 &
VNC_PID=$!
websockify --web=/usr/share/novnc 0.0.0.0:6080 localhost:5900 \
    > research/local/linux-viewer.log 2>&1 &
VIEWER_PID=$!
APP_ARGS=(--project "$ROOT_DIR")
if [[ -n "${ABSOLUTE_DEBUG_STATE:-}" ]]; then
    APP_ARGS+=(--debug-state "$ABSOLUTE_DEBUG_STATE")
fi
"$BIN_DIR/AbsoluteLinux" "${APP_ARGS[@]}" &
DESKTOP_PID=$!

cleanup() {
    if kill -0 "$DESKTOP_PID" 2>/dev/null; then
        kill -TERM "$DESKTOP_PID"
        wait "$DESKTOP_PID" || true
    fi
    kill "$VIEWER_PID" "$VNC_PID" "$DISPLAY_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT
wait "$DESKTOP_PID"
