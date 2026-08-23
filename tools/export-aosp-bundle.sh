#!/usr/bin/env bash
set -euo pipefail

RODIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_STAMP="$(date +%Y%m%d-%H%M%S)"
RODIN_DESTINATION="${1:-$RODIN_ROOT/dist/aosp/RodinEssential-$RODIN_STAMP}"
RODIN_BUILD_DIR="$RODIN_ROOT/out/aosp-export/$RODIN_STAMP/build"
RODIN_TEMPLATE="$RODIN_ROOT/android/aosp"

if [ -e "$RODIN_DESTINATION" ]; then
    echo "Destination already exists: $RODIN_DESTINATION" >&2
    exit 1
fi

RODIN_BUILD_ONLY=1 \
RODIN_OUTPUT_DIR="$RODIN_BUILD_DIR" \
    "$RODIN_ROOT/build-and-install.sh"

RODIN_APK="$RODIN_BUILD_DIR/Rodin-Essential.apk"
RODIN_DAEMON="$RODIN_BUILD_DIR/host-cargo/aarch64-linux-android/release/rodin_daemon"
RODIN_CTL="$RODIN_BUILD_DIR/host-cargo/aarch64-linux-android/release/rodin_ctl"

for RODIN_ARTIFACT in "$RODIN_APK" "$RODIN_DAEMON" "$RODIN_CTL"; do
    [ -f "$RODIN_ARTIFACT" ] || {
        echo "Missing AOSP artifact: $RODIN_ARTIFACT" >&2
        exit 1
    }
done

mkdir -p "$RODIN_DESTINATION/prebuilt" "$RODIN_DESTINATION/docs"
cp -a "$RODIN_TEMPLATE/Android.bp" "$RODIN_DESTINATION/Android.bp"
cp -a "$RODIN_TEMPLATE/rodin-essential.mk" "$RODIN_DESTINATION/rodin-essential.mk"
cp -a "$RODIN_TEMPLATE/BoardConfigRodinEssential.mk" "$RODIN_DESTINATION/BoardConfigRodinEssential.mk"
cp -a "$RODIN_TEMPLATE/rodin_daemon.rc" "$RODIN_DESTINATION/rodin_daemon.rc"
cp -a "$RODIN_TEMPLATE/sepolicy" "$RODIN_DESTINATION/sepolicy"
cp -a "$RODIN_TEMPLATE/README.md" "$RODIN_DESTINATION/README.md"
cp -a "$RODIN_ROOT/docs/ROM_INTEGRATION.md" "$RODIN_DESTINATION/docs/ROM_INTEGRATION.md"
install -m 0644 "$RODIN_APK" "$RODIN_DESTINATION/prebuilt/RodinEssential.apk"
install -m 0755 "$RODIN_DAEMON" "$RODIN_DESTINATION/prebuilt/rodin_daemon"
install -m 0755 "$RODIN_CTL" "$RODIN_DESTINATION/prebuilt/rodin_ctl"

if unzip -Z1 "$RODIN_DESTINATION/prebuilt/RodinEssential.apk" \
    | grep -Eq '(^|/)classes([0-9]*)?\.dex$'; then
    echo "AOSP export contains DEX" >&2
    exit 1
fi

file "$RODIN_DESTINATION/prebuilt/rodin_daemon" | grep -q 'ARM aarch64'
file "$RODIN_DESTINATION/prebuilt/rodin_ctl" | grep -q 'ARM aarch64'

(
    cd "$RODIN_DESTINATION"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

echo "AOSP_EXPORT=PASS"
echo "DIRECTORY=$RODIN_DESTINATION"
