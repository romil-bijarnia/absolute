#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="${ABSOLUTE_VM_NAME:-absolute-dev}"
IMAGE_NAME=absolute-linux-dev:0.3
CONTAINER_NAME=absolute-desktop
DESKTOP_PORT="${ABSOLUTE_DESKTOP_PORT:-6090}"
case "$MODE" in
    run|--build-only|--self-check|--stop) ;;
    *) echo "usage: $0 [run|--build-only|--self-check|--stop]" >&2; exit 2 ;;
esac
command -v limactl >/dev/null || { echo "Lima is required." >&2; exit 1; }
if [[ "$MODE" == "--stop" ]]; then
    exec limactl shell "$VM_NAME" nerdctl stop --time=15 "$CONTAINER_NAME"
fi
VM_STATUS="$(limactl list "$VM_NAME" --format '{{.Status}}' 2>/dev/null || true)"
if [[ -z "$VM_STATUS" ]]; then
    limactl start --tty=false --name="$VM_NAME" --vm-type=vz --cpus=2 --memory=4 --disk=16 \
        --mount-only="$ROOT_DIR:w" template:ubuntu-24.04
elif [[ "$VM_STATUS" != "Running" ]]; then
    limactl start --tty=false "$VM_NAME"
fi
IMAGE_FINGERPRINT="$(shasum -a 256 "$ROOT_DIR/linux/container/Containerfile" | awk '{print $1}')"
BUILT_FINGERPRINT="$(limactl shell "$VM_NAME" nerdctl image inspect "$IMAGE_NAME" \
    --format '{{ index .Config.Labels "org.absolute.containerfile" }}' 2>/dev/null || true)"
if [[ "$BUILT_FINGERPRINT" != "$IMAGE_FINGERPRINT" ]]; then
    mkdir -p "$ROOT_DIR/research/local"
    if ! limactl shell "$VM_NAME" nerdctl build -t "$IMAGE_NAME" --label "org.absolute.containerfile=$IMAGE_FINGERPRINT" \
        -f "$ROOT_DIR/linux/container/Containerfile" "$ROOT_DIR/linux/container" \
        > "$ROOT_DIR/research/local/linux-image-build.log" 2>&1; then
        tail -n 30 "$ROOT_DIR/research/local/linux-image-build.log" >&2
        exit 1
    fi
fi
COMMON_ARGS=(--cpus=2 --memory=3g --volume "$ROOT_DIR:$ROOT_DIR:rw" --workdir "$ROOT_DIR"
    --volume absolute-linux-build:/absolute-linux-build)
case "$MODE" in
    --build-only)
        limactl shell "$VM_NAME" nerdctl run --rm "${COMMON_ARGS[@]}" "$IMAGE_NAME" \
            bash -c 'set -e; swift build --package-path linux --scratch-path /absolute-linux-build --jobs 2; bin_dir="$(swift build --package-path linux --scratch-path /absolute-linux-build --show-bin-path)"; mkdir -p dist/linux; cp "$bin_dir/AbsoluteLinux" dist/linux/AbsoluteLinux'
        ;;
    --self-check)
        limactl shell "$VM_NAME" nerdctl run --rm "${COMMON_ARGS[@]}" "$IMAGE_NAME" \
            bash -c 'set -e; swift build --package-path linux --scratch-path /absolute-linux-build --jobs 2; bin_dir="$(swift build --package-path linux --scratch-path /absolute-linux-build --show-bin-path)"; python3 script/check_linux_desktop.py "$bin_dir/AbsoluteLinux" "$PWD"'
        ;;
    run)
        if limactl shell "$VM_NAME" nerdctl container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
            limactl shell "$VM_NAME" nerdctl stop --time=15 "$CONTAINER_NAME" >/dev/null 2>&1 || true
            limactl shell "$VM_NAME" nerdctl rm "$CONTAINER_NAME" >/dev/null
        fi
        DEBUG_ARGS=()
        if [[ -n "${ABSOLUTE_DEBUG_STATE:-}" ]]; then DEBUG_ARGS=(--env "ABSOLUTE_DEBUG_STATE=$ABSOLUTE_DEBUG_STATE"); fi
        limactl shell "$VM_NAME" nerdctl run --detach --name "$CONTAINER_NAME" \
            "${COMMON_ARGS[@]}" "${DEBUG_ARGS[@]}" \
            --volume absolute-linux-state:/absolute-state --env XDG_STATE_HOME=/absolute-state \
            --publish "127.0.0.1:$DESKTOP_PORT:6080" "$IMAGE_NAME" \
            bash linux/container/start-desktop.sh "$ROOT_DIR" /absolute-linux-build >/dev/null
        echo "Absolute Linux desktop: http://localhost:$DESKTOP_PORT/vnc_lite.html"
        echo "Startup logs: limactl shell $VM_NAME nerdctl logs $CONTAINER_NAME"
        ;;
esac
