#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_NAME="${ABSOLUTE_VM_NAME:-absolute-dev}"
SWIFT_IMAGE="docker.io/library/swift:6.2-noble@sha256:eccc7a97f9b9881d9659e2e788081fd7675f86d39793b51200bfb178398b3784"

command -v limactl >/dev/null || { echo "Lima is required to run the Linux checks." >&2; exit 1; }
VM_STATUS="$(limactl list "$VM_NAME" --format '{{.Status}}' 2>/dev/null || true)"
if [[ -z "$VM_STATUS" ]]; then
  limactl start --tty=false --name="$VM_NAME" --vm-type=vz --cpus=2 --memory=4 --disk=16 \
    --mount-only="$ROOT_DIR:w" template:ubuntu-24.04
elif [[ "$VM_STATUS" != "Running" ]]; then
  limactl start --tty=false "$VM_NAME"
fi

limactl shell "$VM_NAME" nerdctl run --rm --cpus=2 --memory=3g \
  --volume "$ROOT_DIR:$ROOT_DIR:rw" --workdir "$ROOT_DIR" \
  --volume absolute-swift-build:/absolute-build \
  "$SWIFT_IMAGE" bash script/check_core.sh "$ROOT_DIR" /absolute-build
