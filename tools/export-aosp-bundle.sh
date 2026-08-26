#!/usr/bin/env bash
set -euo pipefail

RODIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_STAMP="$(date +%Y%m%d-%H%M%S)"
RODIN_DESTINATION="${1:-$RODIN_ROOT/dist/aosp/RodinEssential-$RODIN_STAMP}"
RODIN_BUILD_DIR="$RODIN_ROOT/out/aosp-export/$RODIN_STAMP/build"
RODIN_TEMPLATE="$RODIN_ROOT/android/aosp"
RODIN_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"

[ -n "${RODIN_KEYSTORE:-}" ] || {
    echo "RODIN_KEYSTORE is required for a reproducibly signed AOSP bundle." >&2
    echo "ROM maintainers must keep the same private key for every update." >&2
    exit 1
}
[ -f "$RODIN_KEYSTORE" ] || {
    echo "RODIN_KEYSTORE does not exist: $RODIN_KEYSTORE" >&2
    exit 1
}

for RODIN_TOOL in openssl readelf sha256sum unzip; do
    command -v "$RODIN_TOOL" >/dev/null 2>&1 || {
        echo "Missing AOSP export tool: $RODIN_TOOL" >&2
        exit 1
    }
done

"$RODIN_ROOT/tools/test-aosp-integration.sh"

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
RODIN_BUILD_TOOLS="$(find "$RODIN_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
RODIN_APKSIGNER="$RODIN_SDK_ROOT/build-tools/$RODIN_BUILD_TOOLS/apksigner"

[ -x "$RODIN_APKSIGNER" ] || {
    echo "Missing Android APK signer: $RODIN_APKSIGNER" >&2
    exit 1
}

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

"$RODIN_APKSIGNER" verify --print-certs-pem "$RODIN_APK" 2>/dev/null \
    | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
    >"$RODIN_DESTINATION/prebuilt/RodinEssential.x509.pem"
openssl x509 -in "$RODIN_DESTINATION/prebuilt/RodinEssential.x509.pem" \
    -noout -subject >/dev/null
RODIN_APK_CERT_DIGEST="$("$RODIN_APKSIGNER" verify --print-certs "$RODIN_APK" \
    2>/dev/null | sed -n 's/^.*certificate SHA-256 digest: //p' | head -n 1 \
    | tr '[:upper:]' '[:lower:]')"
RODIN_PEM_CERT_DIGEST="$(openssl x509 \
    -in "$RODIN_DESTINATION/prebuilt/RodinEssential.x509.pem" -outform DER \
    | sha256sum | awk '{print $1}')"
[[ "$RODIN_APK_CERT_DIGEST" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Unable to read the exported APK certificate" >&2
    exit 1
}
[ "$RODIN_APK_CERT_DIGEST" = "$RODIN_PEM_CERT_DIGEST" ] || {
    echo "Exported APK and SELinux public certificate do not match" >&2
    exit 1
}
openssl x509 -in "$RODIN_DESTINATION/prebuilt/RodinEssential.x509.pem" \
    -noout -subject -issuer -dates -fingerprint -sha256 \
    >"$RODIN_DESTINATION/SIGNING-CERTIFICATE.txt"

if unzip -Z1 "$RODIN_DESTINATION/prebuilt/RodinEssential.apk" \
    | grep -Eq '(^|/)classes([0-9]*)?\.dex$'; then
    echo "AOSP export contains DEX" >&2
    exit 1
fi

file "$RODIN_DESTINATION/prebuilt/rodin_daemon" | grep -q 'ARM aarch64'
file "$RODIN_DESTINATION/prebuilt/rodin_ctl" | grep -q 'ARM aarch64'

RODIN_DAEMON_NEEDED="$(readelf -d "$RODIN_DESTINATION/prebuilt/rodin_daemon" \
    | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | LC_ALL=C sort)"
RODIN_CTL_NEEDED="$(readelf -d "$RODIN_DESTINATION/prebuilt/rodin_ctl" \
    | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | LC_ALL=C sort)"
RODIN_EXPECTED_DAEMON_NEEDED=$'libbinder_ndk.so\nlibc.so\nlibdl.so'
RODIN_EXPECTED_CTL_NEEDED=$'libc.so\nlibdl.so'
[ "$RODIN_DAEMON_NEEDED" = "$RODIN_EXPECTED_DAEMON_NEEDED" ] || {
    echo "rodin_daemon dependencies do not match Android.bp" >&2
    printf '%s\n' "$RODIN_DAEMON_NEEDED" >&2
    exit 1
}
[ "$RODIN_CTL_NEEDED" = "$RODIN_EXPECTED_CTL_NEEDED" ] || {
    echo "rodin_ctl dependencies do not match Android.bp" >&2
    printf '%s\n' "$RODIN_CTL_NEEDED" >&2
    exit 1
}

(
    cd "$RODIN_DESTINATION"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

echo "AOSP_EXPORT=PASS"
echo "APK_CERT_SHA256=$RODIN_APK_CERT_DIGEST"
echo "DIRECTORY=$RODIN_DESTINATION"
