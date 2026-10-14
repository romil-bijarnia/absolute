#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${2:-$ROOT_DIR/.build}"
cd "$ROOT_DIR"

swift test --scratch-path "$BUILD_DIR" --jobs 2
case "$(uname -s)" in
  Linux) CHECK_PLATFORM=linux ;;
  Darwin) CHECK_PLATFORM=macos ;;
  *) CHECK_PLATFORM=other ;;
esac
swift run --scratch-path "$BUILD_DIR" --skip-build absolute verify "$ROOT_DIR" \
  "$ROOT_DIR/research/local/$CHECK_PLATFORM-core-report.json"
