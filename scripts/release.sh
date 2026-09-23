#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-${DIST_DIR:-$ROOT_DIR/dist}}"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Resources/Info.plist")}"
ARCHIVE_ARCH="${ARCHIVE_ARCH:-$(uname -m)}"
ARCHITECTURES="${ARCHITECTURES:-}"
APP_PATH="$DIST_DIR/Vibe View.app"
ARCHIVE_PATH="$DIST_DIR/VibeView-$VERSION-macOS-$ARCHIVE_ARCH.zip"

if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" != "v$VERSION" ]]; then
    echo "error: tag $GITHUB_REF_NAME does not match app version v$VERSION" >&2
    exit 1
fi

"$ROOT_DIR/scripts/check_release.sh"

RUN_TESTS="${RUN_TESTS:-1}" \
    "$ROOT_DIR/scripts/build_app.sh" "$DIST_DIR"

verify_app() {
    local path="$1"
    if [[ -n "$ARCHITECTURES" ]]; then
        EXPECTED_ARCHITECTURES="$ARCHITECTURES" \
            "$ROOT_DIR/scripts/verify_app.sh" "$path"
    else
        "$ROOT_DIR/scripts/verify_app.sh" "$path"
    fi
}

verify_app "$APP_PATH"

rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

ARCHIVE_VERIFY_DIR="$(mktemp -d "$DIST_DIR/.codex-watch-archive-verify.XXXXXX")"
cleanup_archive_verify_dir() {
    if [[ -n "$ARCHIVE_VERIFY_DIR" ]]; then
        rm -rf "$ARCHIVE_VERIFY_DIR"
        ARCHIVE_VERIFY_DIR=""
    fi
}
trap cleanup_archive_verify_dir EXIT

ditto -x -k "$ARCHIVE_PATH" "$ARCHIVE_VERIFY_DIR"
EXTRACTED_APP_PATH="$ARCHIVE_VERIFY_DIR/Vibe View.app"
shopt -s dotglob nullglob
ARCHIVE_ROOT_ITEMS=("$ARCHIVE_VERIFY_DIR"/*)
shopt -u dotglob nullglob
if [[ "${#ARCHIVE_ROOT_ITEMS[@]}" -ne 1 || "${ARCHIVE_ROOT_ITEMS[0]}" != "$EXTRACTED_APP_PATH" ]]; then
    echo "error: archive must contain only Vibe View.app at its root" >&2
    exit 1
fi
verify_app "$EXTRACTED_APP_PATH"

cleanup_archive_verify_dir
trap - EXIT

ARCHIVE_DIRECTORY="$(dirname "$ARCHIVE_PATH")"
ARCHIVE_NAME="$(basename "$ARCHIVE_PATH")"
(
    cd "$ARCHIVE_DIRECTORY"
    shasum -a 256 "$ARCHIVE_NAME"
) | tee "$ARCHIVE_PATH.sha256"

CHECKSUM_TARGET="$(awk 'NR == 1 { print $2 }' "$ARCHIVE_PATH.sha256")"
if [[ "$CHECKSUM_TARGET" != "$ARCHIVE_NAME" ]]; then
    echo "error: checksum must reference the portable archive filename" >&2
    exit 1
fi

echo "Release archive: $ARCHIVE_PATH"
