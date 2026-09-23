#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-watch-script-tests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "error: $*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="$3"
    [[ "$actual" == "$expected" ]] || {
        fail "$description: expected '$expected', got '$actual'"
    }
}

test_build_queries_path_then_builds_once() {
    local fixture="$TEST_ROOT/build"
    local fake_bin="$fixture/fake-bin"
    local bin_dir="$fixture/build-output"
    local invocation_log="$fixture/swift-invocations.log"
    mkdir -p "$fixture/scripts" "$fixture/Resources" "$fake_bin"
    cp "$ROOT_DIR/scripts/build_app.sh" "$fixture/scripts/build_app.sh"
    : > "$fixture/Resources/Info.plist"

    cat > "$fixture/scripts/build_icon.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
: > "$1"
SCRIPT
    chmod +x "$fixture/scripts/build_icon.sh"

    cat > "$fake_bin/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$SWIFT_INVOCATION_LOG"

if [[ "$1" == "test" ]]; then
    exit 0
fi

show_bin_path=0
for argument in "$@"; do
    if [[ "$argument" == "--show-bin-path" ]]; then
        show_bin_path=1
    fi
done

if [[ "$show_bin_path" == "1" ]]; then
    printf '%s\n' "$FAKE_BIN_DIR"
    exit 0
fi

mkdir -p "$FAKE_BIN_DIR"
printf '#!/usr/bin/env bash\n' > "$FAKE_BIN_DIR/CodexWatch"
chmod +x "$FAKE_BIN_DIR/CodexWatch"
SCRIPT
    chmod +x "$fake_bin/swift"

    PATH="$fake_bin:/usr/bin:/bin" \
        RUN_TESTS=0 \
        SIGN_IDENTITY=none \
        SWIFT_INVOCATION_LOG="$invocation_log" \
        FAKE_BIN_DIR="$bin_dir" \
        "$fixture/scripts/build_app.sh" "$fixture/dist"

    local invocation_count
    local metadata_count
    local build_count
    local first_invocation
    local second_invocation
    invocation_count="$(wc -l < "$invocation_log" | tr -d ' ')"
    metadata_count="$(grep -c -- '--show-bin-path' "$invocation_log" || true)"
    build_count="$(grep -vc -- '--show-bin-path' "$invocation_log" || true)"
    first_invocation="$(sed -n '1p' "$invocation_log")"
    second_invocation="$(sed -n '2p' "$invocation_log")"

    assert_equals 2 "$invocation_count" "Swift invocation count"
    assert_equals 1 "$metadata_count" "binary-path query count"
    assert_equals 1 "$build_count" "real build count"
    [[ "$first_invocation" == *"--show-bin-path"* ]] || {
        fail "the metadata-only binary-path query must happen before the real build"
    }
    [[ "$second_invocation" != *"--show-bin-path"* ]] || {
        fail "the real build must not use --show-bin-path"
    }
    [[ -x "$fixture/dist/Vibe View.app/Contents/MacOS/CodexWatch" ]] || {
        fail "build_app.sh did not package the executable created by the real build"
    }
}

make_release_fixture() {
    local fixture="$1"
    local fake_bin="$fixture/fake-bin"
    mkdir -p "$fixture/scripts" "$fixture/Resources" "$fake_bin"
    cp "$ROOT_DIR/scripts/release.sh" "$fixture/scripts/release.sh"
    : > "$fixture/Resources/Info.plist"

    cat > "$fixture/scripts/check_release.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAIL_RELEASE_GATE:-0}" != "1" ]] || exit 9
printf 'passed\n' > "$(dirname "$0")/gate-passed"
SCRIPT
    chmod +x "$fixture/scripts/check_release.sh"

    cat > "$fixture/scripts/build_app.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ -f "$(dirname "$0")/gate-passed" ]] || { echo 'release gate was skipped' >&2; exit 1; }
mkdir -p "$1/Vibe View.app/Contents"
printf 'archive payload\n' > "$1/Vibe View.app/Contents/payload"
SCRIPT
    chmod +x "$fixture/scripts/build_app.sh"

    cat > "$fixture/scripts/verify_app.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
[[ -d "$1" ]] || { echo "error: app missing: $1" >&2; exit 1; }
[[ "$(cat "$1/Contents/payload")" == "archive payload" ]] || {
    echo "error: unexpected app payload" >&2
    exit 1
}
printf '%s|%s\n' "${EXPECTED_ARCHITECTURES:-}" "$1" >> "$VERIFY_LOG"
SCRIPT
    chmod +x "$fixture/scripts/verify_app.sh"

    cat > "$fake_bin/plutil" <<'SCRIPT'
#!/usr/bin/env bash
printf '1.3.0\n'
SCRIPT
    chmod +x "$fake_bin/plutil"

    cat > "$fake_bin/uname" <<'SCRIPT'
#!/usr/bin/env bash
printf 'arm64\n'
SCRIPT
    chmod +x "$fake_bin/uname"

    cat > "$fake_bin/ditto" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-c" ]]; then
    app_path="$5"
    archive_path="$6"
    : > "$archive_path"
    mkdir -p "$archive_path.contents"
    cp -R "$app_path" "$archive_path.contents/"
    exit 0
fi

if [[ "$1" == "-x" ]]; then
    archive_path="$3"
    destination="$4"
    cp -R "$archive_path.contents/Vibe View.app" "$destination/"
    if [[ "${FAKE_ARCHIVE_EXTRA:-0}" == "1" ]]; then
        printf 'unexpected\n' > "$destination/unexpected.txt"
    fi
    exit 0
fi

echo "error: unsupported ditto invocation" >&2
exit 1
SCRIPT
    chmod +x "$fake_bin/ditto"

    cat > "$fake_bin/shasum" <<'SCRIPT'
#!/usr/bin/env bash
printf '0123456789abcdef  %s\n' "$3"
SCRIPT
    chmod +x "$fake_bin/shasum"
}

test_release_verifies_exact_archive_payload() {
    local fixture="$TEST_ROOT/release-success"
    local verify_log="$fixture/verify.log"
    local dist="$fixture/dist"
    make_release_fixture "$fixture"
    mkdir -p "$dist"
    printf 'keep\n' > "$dist/adjacent-sentinel"

    PATH="$fixture/fake-bin:/usr/bin:/bin" \
        ARCHITECTURES="arm64 x86_64" \
        ARCHIVE_ARCH=universal \
        VERIFY_LOG="$verify_log" \
        "$fixture/scripts/release.sh" "$dist"

    local verify_count
    local first_verification
    local second_verification
    local extracted_verification_prefix
    verify_count="$(wc -l < "$verify_log" | tr -d ' ')"
    first_verification="$(sed -n '1p' "$verify_log")"
    second_verification="$(sed -n '2p' "$verify_log")"
    extracted_verification_prefix="arm64 x86_64|$dist/.codex-watch-archive-verify."

    assert_equals 2 "$verify_count" "app verification count"
    assert_equals "arm64 x86_64|$dist/Vibe View.app" "$first_verification" \
        "pre-archive verification"
    [[ "$second_verification" == "$extracted_verification_prefix"*"/Vibe View.app" ]] || {
        fail "the second verification did not target the extracted archive app"
    }
    [[ -f "$dist/VibeView-1.3.0-macOS-universal.zip" ]] || {
        fail "release archive was not produced"
    }
    [[ -f "$dist/VibeView-1.3.0-macOS-universal.zip.sha256" ]] || {
        fail "release checksum was not produced"
    }
    local checksum_target
    checksum_target="$(awk 'NR == 1 { print $2 }' "$dist/VibeView-1.3.0-macOS-universal.zip.sha256")"
    assert_equals "VibeView-1.3.0-macOS-universal.zip" "$checksum_target" \
        "portable checksum target"
    [[ "$(cat "$dist/adjacent-sentinel")" == "keep" ]] || {
        fail "archive verification cleanup modified an adjacent path"
    }
    if find "$dist" -maxdepth 1 -type d -name '.codex-watch-archive-verify.*' -print -quit | grep -q .; then
        fail "archive verification directory was not cleaned"
    fi
}

test_release_rejects_extra_top_level_archive_content() {
    local fixture="$TEST_ROOT/release-extra-content"
    local verify_log="$fixture/verify.log"
    local dist="$fixture/dist"
    make_release_fixture "$fixture"
    mkdir -p "$dist"
    printf 'keep\n' > "$dist/adjacent-sentinel"

    if PATH="$fixture/fake-bin:/usr/bin:/bin" \
        ARCHITECTURES="arm64 x86_64" \
        ARCHIVE_ARCH=universal \
        VERIFY_LOG="$verify_log" \
        FAKE_ARCHIVE_EXTRA=1 \
        "$fixture/scripts/release.sh" "$dist" \
        > "$fixture/release.stdout" 2> "$fixture/release.stderr"; then
        fail "release.sh accepted unexpected top-level archive content"
    fi

    grep -q 'archive must contain only Vibe View.app at its root' "$fixture/release.stderr" || {
        fail "release.sh failed for the wrong reason when archive content was unexpected"
    }

    if find "$dist" -maxdepth 1 -type d -name '.codex-watch-archive-verify.*' -print -quit | grep -q .; then
        fail "failed archive verification left its temporary directory behind"
    fi
    [[ "$(cat "$dist/adjacent-sentinel")" == "keep" ]] || {
        fail "failed archive verification cleanup modified an adjacent path"
    }
}

test_release_gate_failure_prevents_packaging() {
    local fixture="$TEST_ROOT/release-gate-failure"
    make_release_fixture "$fixture"
    if PATH="$fixture/fake-bin:/usr/bin:/bin" FAIL_RELEASE_GATE=1 \
        "$fixture/scripts/release.sh" "$fixture/dist"; then
        fail "release accepted a failed prerequisite"
    fi
    [[ ! -d "$fixture/dist" ]] || fail "release packaged an app before prerequisites passed"
}

test_release_gate_failure_prevents_packaging
test_build_queries_path_then_builds_once
test_release_verifies_exact_archive_payload
test_release_rejects_extra_top_level_archive_content

echo "Release script tests passed"
