#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
    echo "usage: $0 '/path/to/Vibe View.app'" >&2
    exit 2
fi

EXECUTABLE="$APP_PATH/Contents/MacOS/CodexWatch"
INFO_PLIST="$APP_PATH/Contents/Info.plist"

[[ -d "$APP_PATH" ]] || { echo "error: app not found: $APP_PATH" >&2; exit 1; }
[[ -x "$EXECUTABLE" ]] || { echo "error: executable missing: $EXECUTABLE" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "error: Info.plist missing: $INFO_PLIST" >&2; exit 1; }

plutil -lint "$INFO_PLIST"

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null || true)"
ICON_PATH="$APP_PATH/Contents/Resources/${ICON_NAME}.icns"
[[ "$ICON_NAME" == "CodexWatch" ]] || {
    echo "error: CFBundleIconFile must be CodexWatch" >&2
    exit 1
}
[[ -f "$ICON_PATH" ]] || { echo "error: app icon missing: $ICON_PATH" >&2; exit 1; }

ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-watch-icon-verify.XXXXXX")"
trap 'rm -rf "$ICONSET_DIR"' EXIT
iconutil -c iconset "$ICON_PATH" -o "$ICONSET_DIR/CodexWatch.iconset"

verify_icon_representation() {
    local filename="$1"
    local expected_pixels="$2"
    local path="$ICONSET_DIR/CodexWatch.iconset/$filename"
    [[ -f "$path" ]] || {
        echo "error: app icon is missing $filename" >&2
        exit 1
    }
    local width
    local height
    width="$(sips -g pixelWidth "$path" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$path" | awk '/pixelHeight/ { print $2 }')"
    [[ "$width" == "$expected_pixels" && "$height" == "$expected_pixels" ]] || {
        echo "error: $filename must be ${expected_pixels}x${expected_pixels}, got ${width}x${height}" >&2
        exit 1
    }
}

verify_icon_representation icon_16x16.png 16
verify_icon_representation icon_16x16@2x.png 32
verify_icon_representation icon_32x32.png 32
verify_icon_representation icon_32x32@2x.png 64
verify_icon_representation icon_128x128.png 128
verify_icon_representation icon_128x128@2x.png 256
verify_icon_representation icon_256x256.png 256
verify_icon_representation icon_256x256@2x.png 512
verify_icon_representation icon_512x512.png 512
verify_icon_representation icon_512x512@2x.png 1024

DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO_PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ "$DISPLAY_NAME" == "Vibe View" ]] || { echo "error: unexpected display name" >&2; exit 1; }
[[ "$BUNDLE_ID" == "com.moebis.codexwatch" ]] || { echo "error: unexpected bundle identifier" >&2; exit 1; }
[[ "$VERSION" == "1.3.3" ]] || { echo "error: unexpected version" >&2; exit 1; }
[[ "$BUILD" == "28" ]] || { echo "error: unexpected build number" >&2; exit 1; }

codesign --verify --strict "$APP_PATH"

if [[ -n "${EXPECTED_ARCHITECTURES:-}" ]]; then
    ACTUAL_ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
    for EXPECTED_ARCHITECTURE in $EXPECTED_ARCHITECTURES; do
        case " $ACTUAL_ARCHITECTURES " in
            *" $EXPECTED_ARCHITECTURE "*) ;;
            *)
                echo "error: executable is missing architecture $EXPECTED_ARCHITECTURE" >&2
                exit 1
                ;;
        esac
    done
fi

SIGNATURE_FLAGS="$(codesign -dvv "$APP_PATH" 2>&1 || true)"
case "$SIGNATURE_FLAGS" in
    *"flags="*"runtime"*) ;;
    *)
        echo "error: hardened runtime flag is missing" >&2
        exit 1
        ;;
esac

echo "Verified: $APP_PATH"
