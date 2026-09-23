#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-${DIST_DIR:-$ROOT_DIR/dist}}"

export CODEX_WATCH_SCRATCH_PATH="${CODEX_WATCH_SCRATCH_PATH:-${TMPDIR:-/tmp}/codex-watch-swift-build}"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/check_contracts.sh"
swift test --scratch-path "$CODEX_WATCH_SCRATCH_PATH"
RUN_TESTS=0 "$ROOT_DIR/scripts/build_app.sh" "$DIST_DIR"
"$ROOT_DIR/scripts/verify_app.sh" "$DIST_DIR/Vibe View.app"

echo "Full verification passed: $DIST_DIR/Vibe View.app"
