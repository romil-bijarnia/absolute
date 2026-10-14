#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BACKGROUND="${2:-}"
APP_NAME="AbsoluteDesktop"
BUNDLE_ID="org.absolute.desktop"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Absolute.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
cd "$ROOT_DIR"

case "$MODE" in
  run|--verify|--debug|--logs|--telemetry|--build-only|--test|--self-check) ;;
  *) echo "usage: $0 [run|--build-only|--test|--self-check|--verify|--debug|--logs|--telemetry] [--background]" >&2; exit 2 ;;
esac
if [[ -n "$BACKGROUND" && "$BACKGROUND" != "--background" ]]; then
  echo "Unknown launch option: $BACKGROUND" >&2
  exit 2
fi

launch_app() {
  if [[ "$BACKGROUND" == "--background" ]]; then
    /usr/bin/open -g -n "$APP_BUNDLE" --args --background "$@"
  else
    /usr/bin/open -n "$APP_BUNDLE" --args "$@"
  fi
}

wait_for_report() {
  local report="$1"
  for check_attempt in {1..60}; do
    if [[ -f "$report" ]]; then return 0; fi
    sleep 0.5
  done
  echo "Native self-check timed out; inspect $(dirname "$report")" >&2
  return 1
}

wait_for_exit() {
  local app_pid="$1"
  for check_attempt in {1..50}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  echo "The self-check app did not finish quitting." >&2
  return 1
}

print_report() {
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps(r,indent=2)); sys.exit(0 if r["passed"] else 1)' "$1"
}

if [[ "$MODE" == "--test" ]]; then
  exec swift test
fi

if [[ "$MODE" != "--build-only" ]]; then
  for app_pid in $(pgrep -x "$APP_NAME" || true); do
    app_command="$(ps -ww -p "$app_pid" -o comm= || true)"
    if [[ "$app_command" == "$APP_BINARY" ]]; then kill "$app_pid"; fi
  done
fi

swift build --product "$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"
mkdir -p "$APP_MACOS"
cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Absolute</string>
<key>CFBundleDisplayName</key><string>Absolute</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP_BUNDLE"

case "$MODE" in
  --build-only) echo "Built $APP_BUNDLE" ;;
  run) launch_app ;;
  --verify)
    launch_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    echo "Absolute is running."
    ;;
  --self-check)
    CHECK_DIR="$ROOT_DIR/research/local/ui-check-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$CHECK_DIR"
    launch_app --self-check "$CHECK_DIR" --state-file "$CHECK_DIR/desktop-session.json" --exit-after-check
    wait_for_report "$CHECK_DIR/results.json"
    print_report "$CHECK_DIR/results.json"
    CHECK_PID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["process_identifier"])' "$CHECK_DIR/results.json")"
    wait_for_exit "$CHECK_PID"
    launch_app --restore-check "$CHECK_DIR" --state-file "$CHECK_DIR/desktop-session.json" --exit-after-check
    wait_for_report "$CHECK_DIR/restore-results.json"
    print_report "$CHECK_DIR/restore-results.json"
    CHECK_PID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["process_identifier"])' "$CHECK_DIR/restore-results.json")"
    wait_for_exit "$CHECK_PID"
    echo "Native screenshots and restart reports: $CHECK_DIR"
    ;;
  --debug) lldb -- "$APP_BINARY" ;;
  --logs)
    launch_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry)
    launch_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
esac
