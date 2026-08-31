#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_MODULE="$RODIN_PROJECT_ROOT/android/kernelsu-next"
RODIN_SERVICE="$RODIN_MODULE/service.sh"
RODIN_INSTALLER="$RODIN_MODULE/customize.sh"
RODIN_ACTION="$RODIN_MODULE/action.sh"

for RODIN_SCRIPT in customize.sh service.sh action.sh uninstall.sh; do
    bash -n "$RODIN_MODULE/$RODIN_SCRIPT"
    if LC_ALL=C grep -q $'\r' "$RODIN_MODULE/$RODIN_SCRIPT"; then
        echo "CRLF line endings are not allowed: $RODIN_SCRIPT" >&2
        exit 1
    fi
done

[ -f "$RODIN_MODULE/skip_mount" ] || {
    echo "Root module must remain script-only and skip system mounting" >&2
    exit 1
}

if find "$RODIN_MODULE" -maxdepth 1 -type f \
    \( -name 'sepolicy.rule' -o -name 'apply-sepolicy.sh' \) | grep -q .; then
    echo "Root module must not depend on app-to-root SELinux relaxation" >&2
    exit 1
fi

if grep -ERq 'magiskpolicy|ksud[[:space:]]+sepolicy|allow[[:space:]]+appdomain' \
    "$RODIN_MODULE"; then
    echo "Root module contains an obsolete SELinux patch path" >&2
    exit 1
fi

grep -Fxq 'export RODIN_REVERSE_IPC=1' "$RODIN_SERVICE"
grep -Fxq 'export RODIN_LOOPBACK_IPC=1' "$RODIN_SERVICE"
grep -Fq 'export RODIN_APP_UID' "$RODIN_SERVICE"
grep -Fq 'pm list packages -U' "$RODIN_SERVICE"
grep -Fq 'sys.boot_completed' "$RODIN_SERVICE"
grep -Fq 'rom_native_backend_detected' "$RODIN_SERVICE"
grep -Fq 'App IPC: verified (daemon-initiated)' "$RODIN_ACTION"
grep -Fq 'App IPC: verified (authenticated loopback)' "$RODIN_ACTION"
grep -Fq 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' "$RODIN_INSTALLER"
grep -Fq 'App/module version mismatch' "$RODIN_INSTALLER"
grep -Fq 'touch_resampler_ready' "$RODIN_ACTION"
[ -s "$RODIN_PROJECT_ROOT/runtime/daemon-rust/src/touch_resampler.rs" ] || {
    echo "The v1.18.0 touch resampler source is missing" >&2
    exit 1
}

if grep -Eq 'pm[[:space:]]+uninstall|rm[[:space:]].*io\.github\.neeschal\.rodinessential' \
    "$RODIN_INSTALLER"; then
    echo "Installer must never remove an existing app or its data automatically" >&2
    exit 1
fi

RODIN_MODULE_VERSION="$(sed -n 's/^version=v//p' "$RODIN_MODULE/module.prop")"
RODIN_MODULE_CODE="$(sed -n 's/^versionCode=//p' "$RODIN_MODULE/module.prop")"
RODIN_MANIFEST_VERSION="$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' \
    "$RODIN_PROJECT_ROOT/android/package/AndroidManifest.xml")"
RODIN_MANIFEST_CODE="$(sed -n 's/.*android:versionCode="\([^"]*\)".*/\1/p' \
    "$RODIN_PROJECT_ROOT/android/package/AndroidManifest.xml")"
RODIN_FLUTTER_VERSION="$(sed -n 's/^version: \([^+]*\)+.*/\1/p' \
    "$RODIN_PROJECT_ROOT/ui/flutter/pubspec.yaml")"
RODIN_FLUTTER_CODE="$(sed -n 's/^version: [^+]*+\([0-9]*\).*/\1/p' \
    "$RODIN_PROJECT_ROOT/ui/flutter/pubspec.yaml")"

for RODIN_VERSION in "$RODIN_MODULE_VERSION" "$RODIN_MANIFEST_VERSION" "$RODIN_FLUTTER_VERSION"; do
    [ "$RODIN_VERSION" = "$RODIN_MODULE_VERSION" ] || {
        echo "Application/module version mismatch" >&2
        exit 1
    }
done
for RODIN_CODE in "$RODIN_MODULE_CODE" "$RODIN_MANIFEST_CODE" "$RODIN_FLUTTER_CODE"; do
    [ "$RODIN_CODE" = "$RODIN_MODULE_CODE" ] || {
        echo "Application/module versionCode mismatch" >&2
        exit 1
    }
done

echo 'ROOT_MODULE_CONTRACT_TEST=PASS'
