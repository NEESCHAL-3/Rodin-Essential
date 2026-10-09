#!/usr/bin/env bash
set -euo pipefail
APK="${1:?APK required}"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
test "$(unzip -Z1 "$APK" | grep -E '(^|/)classes([0-9]*)?\.dex$')" = classes.dex
DEX="$(mktemp --suffix=.dex)"
trap 'rm -f -- "$DEX"' EXIT
unzip -p "$APK" classes.dex > "$DEX"
test "$(wc -c < "$DEX")" -le 32768
DEXDUMP="$(find "$SDK/build-tools" -type f -name dexdump | sort -V | tail -1)"
test -n "$DEXDUMP"
CLASSES="$("$DEXDUMP" "$DEX" | awk -F "'" '/Class descriptor/ {print $2}')"
test -n "$CLASSES"
if printf '%s\n' "$CLASSES" | grep -Ev '^Lio/github/neeschal/rodinessential/(RodinActivity|BypassTileService)(;|\$)'; then
    echo 'Unexpected managed class in APK' >&2; exit 1
fi
printf '%s\n' "$CLASSES" | grep -qx 'Lio/github/neeschal/rodinessential/RodinActivity;'
printf '%s\n' "$CLASSES" | grep -qx 'Lio/github/neeschal/rodinessential/BypassTileService;'
echo 'PLATFORM_BRIDGE_DEX=PASS (framework adapters only)'
