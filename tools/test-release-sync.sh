#!/usr/bin/env bash
set -euo pipefail

RODIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_MODULE="$RODIN_ROOT/android/kernelsu-next/module.prop"
RODIN_MANIFEST="$RODIN_ROOT/android/package/AndroidManifest.xml"
RODIN_FLUTTER="$RODIN_ROOT/ui/flutter/pubspec.yaml"
RODIN_MAIN="$RODIN_ROOT/ui/flutter/lib/main.dart"
RODIN_DAEMON="$RODIN_ROOT/runtime/daemon-rust/src/lib.rs"
RODIN_HOST="$RODIN_ROOT/runtime/host-rust/src/backend_bridge.rs"

RODIN_CARGO_VERSION="$(sed -n 's/^version = "\([0-9][0-9.]*\)"$/\1/p' \
    "$RODIN_ROOT/Cargo.toml" | head -n 1)"
RODIN_MODULE_VERSION="$(sed -n 's/^version=v//p' "$RODIN_MODULE")"
RODIN_MODULE_CODE="$(sed -n 's/^versionCode=//p' "$RODIN_MODULE")"
RODIN_MANIFEST_VERSION="$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' \
    "$RODIN_MANIFEST")"
RODIN_MANIFEST_CODE="$(sed -n 's/.*android:versionCode="\([^"]*\)".*/\1/p' \
    "$RODIN_MANIFEST")"
RODIN_FLUTTER_VERSION="$(sed -n 's/^version: \([^+]*\)+.*/\1/p' "$RODIN_FLUTTER")"
RODIN_FLUTTER_CODE="$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' "$RODIN_FLUTTER")"
RODIN_CHANGELOG_VERSION="$(sed -n 's/^## \([0-9][0-9.]*\)$/\1/p' \
    "$RODIN_ROOT/CHANGELOG.md" | head -n 1)"

for RODIN_VERSION in \
    "$RODIN_MODULE_VERSION" "$RODIN_MANIFEST_VERSION" \
    "$RODIN_FLUTTER_VERSION" "$RODIN_CHANGELOG_VERSION"; do
    [ "$RODIN_VERSION" = "$RODIN_CARGO_VERSION" ] || {
        echo "Release version mismatch: $RODIN_VERSION / $RODIN_CARGO_VERSION" >&2
        exit 1
    }
done

for RODIN_CODE in "$RODIN_MODULE_CODE" "$RODIN_MANIFEST_CODE" "$RODIN_FLUTTER_CODE"; do
    [ "$RODIN_CODE" = "$RODIN_MODULE_CODE" ] || {
        echo "Release versionCode mismatch: $RODIN_CODE / $RODIN_MODULE_CODE" >&2
        exit 1
    }
done

IFS=. read -r RODIN_MAJOR RODIN_MINOR RODIN_PATCH <<EOF
$RODIN_CARGO_VERSION
EOF
RODIN_EXPECTED_CODE="$(printf '%d%02d%02d' \
    "$RODIN_MAJOR" "$RODIN_MINOR" "$RODIN_PATCH")"
[ "$RODIN_MODULE_CODE" = "$RODIN_EXPECTED_CODE" ] || {
    echo "Release versionCode is not derived from the semantic version" >&2
    exit 1
}

grep -Fq "label: 'v$RODIN_CARGO_VERSION'" "$RODIN_MAIN" || {
    echo "In-app release label is not synchronized" >&2
    exit 1
}

RODIN_DAEMON_SOCKET="$(sed -n 's/^pub const SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$RODIN_DAEMON")"
RODIN_HOST_SOCKET="$(sed -n 's/^const SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$RODIN_HOST")"
RODIN_DAEMON_REVERSE="$(sed -n 's/^pub const REVERSE_SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$RODIN_DAEMON")"
RODIN_HOST_REVERSE="$(sed -n 's/^const REVERSE_SOCKET_NAME: &str = "\([^"]*\)";/\1/p' \
    "$RODIN_HOST")"
RODIN_PROTOCOL="$(sed -n 's/^pub const PROTOCOL_VERSION: &str = "\([^"]*\)";/\1/p' \
    "$RODIN_DAEMON")"

[ -n "$RODIN_DAEMON_SOCKET" ] && [ "$RODIN_DAEMON_SOCKET" = "$RODIN_HOST_SOCKET" ] || {
    echo "App/daemon primary socket mismatch" >&2
    exit 1
}
[ -n "$RODIN_DAEMON_REVERSE" ] && [ "$RODIN_DAEMON_REVERSE" = "$RODIN_HOST_REVERSE" ] || {
    echo "App/daemon reverse socket mismatch" >&2
    exit 1
}
grep -Fq "Some(\"$RODIN_PROTOCOL\")" "$RODIN_HOST" || {
    echo "App/daemon protocol mismatch" >&2
    exit 1
}

for RODIN_PACKAGER in \
    "$RODIN_ROOT/tools/build-kernelsu-next-module.sh" \
    "$RODIN_ROOT/tools/export-aosp-bundle.sh"; do
    grep -Fq 'build-and-install.sh' "$RODIN_PACKAGER"
    grep -Fq 'Rodin-Essential.apk' "$RODIN_PACKAGER"
    grep -Fq 'host-cargo/aarch64-linux-android/release/rodin_daemon' "$RODIN_PACKAGER"
    grep -Fq -- '--strip-unneeded' "$RODIN_PACKAGER"
done

echo 'RELEASE_SYNC_CONTRACT_TEST=PASS'
