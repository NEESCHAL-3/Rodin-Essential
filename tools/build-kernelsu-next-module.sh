#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_MODULE_SOURCE="$RODIN_PROJECT_ROOT/android/kernelsu-next"
RODIN_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
RODIN_STAMP="$(date +%Y%m%d-%H%M%S)"
RODIN_BUILD_ROOT="$RODIN_PROJECT_ROOT/out/kernelsu-next/$RODIN_STAMP"
RODIN_STAGE="$RODIN_BUILD_ROOT/module"
RODIN_APP_BUILD="$RODIN_BUILD_ROOT/application"

RODIN_VERSION="$(sed -n 's/^version=//p' "$RODIN_MODULE_SOURCE/module.prop")"
RODIN_ZIP_NAME="Rodin-Essential-KernelSU-Next-Magisk-${RODIN_VERSION}.zip"
RODIN_ZIP="$RODIN_BUILD_ROOT/$RODIN_ZIP_NAME"
RODIN_STABLE_ZIP="$RODIN_PROJECT_ROOT/out/Rodin-Essential-KernelSU-Next-Magisk.zip"

[ -n "${RODIN_KEYSTORE:-}" ] || {
    echo "RODIN_KEYSTORE is required for a distributable root module." >&2
    echo "Use one persistent signing key for every module update." >&2
    exit 1
}

RODIN_NDK_VERSION="$(find "$RODIN_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
RODIN_NDK="$RODIN_SDK_ROOT/ndk/$RODIN_NDK_VERSION"
RODIN_TOOLCHAIN="$RODIN_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
RODIN_STRIP="$RODIN_TOOLCHAIN/llvm-strip"
RODIN_BUILD_TOOLS="$(find "$RODIN_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
RODIN_AAPT2="$RODIN_SDK_ROOT/build-tools/$RODIN_BUILD_TOOLS/aapt2"
RODIN_APKSIGNER="$RODIN_SDK_ROOT/build-tools/$RODIN_BUILD_TOOLS/apksigner"
RODIN_ZIPALIGN="$RODIN_SDK_ROOT/build-tools/$RODIN_BUILD_TOOLS/zipalign"

for RODIN_TOOL in "$RODIN_STRIP" "$RODIN_AAPT2" "$RODIN_APKSIGNER" "$RODIN_ZIPALIGN"; do
    [ -x "$RODIN_TOOL" ] || {
        echo "Missing Android build tool: $RODIN_TOOL" >&2
        exit 1
    }
done

"$RODIN_PROJECT_ROOT/tools/test-kernelsu-watchdog-lock.sh"
"$RODIN_PROJECT_ROOT/tools/test-root-module-contract.sh"

mkdir -p "$RODIN_STAGE/bin" "$RODIN_STAGE/app"

echo "===== RODIN ESSENTIAL — KERNELSU NEXT + MAGISK MODULE ====="
echo "version=$RODIN_VERSION"
echo "ndk=$RODIN_NDK_VERSION"
echo "output=$RODIN_ZIP"

RODIN_BUILD_ONLY=1 \
RODIN_OUTPUT_DIR="$RODIN_APP_BUILD" \
    "$RODIN_PROJECT_ROOT/build-and-install.sh"

RODIN_APK="$RODIN_APP_BUILD/Rodin-Essential.apk"
RODIN_DAEMON="$RODIN_APP_BUILD/host-cargo/aarch64-linux-android/release/rodin_daemon"
RODIN_CTL="$RODIN_APP_BUILD/host-cargo/aarch64-linux-android/release/rodin_ctl"

for RODIN_ARTIFACT in "$RODIN_APK" "$RODIN_DAEMON" "$RODIN_CTL"; do
    [ -f "$RODIN_ARTIFACT" ] || {
        echo "Missing release artifact: $RODIN_ARTIFACT" >&2
        exit 1
    }
done

install -m 0644 "$RODIN_MODULE_SOURCE/module.prop" "$RODIN_STAGE/module.prop"
install -m 0755 "$RODIN_MODULE_SOURCE/customize.sh" "$RODIN_STAGE/customize.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/service.sh" "$RODIN_STAGE/service.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/action.sh" "$RODIN_STAGE/action.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/uninstall.sh" "$RODIN_STAGE/uninstall.sh"
install -m 0644 "$RODIN_MODULE_SOURCE/skip_mount" "$RODIN_STAGE/skip_mount"
install -m 0644 "$RODIN_APK" "$RODIN_STAGE/app/RodinEssential.apk"
install -m 0755 "$RODIN_DAEMON" "$RODIN_STAGE/bin/rodin_daemon"
install -m 0755 "$RODIN_CTL" "$RODIN_STAGE/bin/rodin_ctl"

"$RODIN_STRIP" --strip-unneeded "$RODIN_STAGE/bin/rodin_daemon"
"$RODIN_STRIP" --strip-unneeded "$RODIN_STAGE/bin/rodin_ctl"

for RODIN_SCRIPT in customize.sh service.sh action.sh uninstall.sh; do
    bash -n "$RODIN_STAGE/$RODIN_SCRIPT"
    if LC_ALL=C grep -q $'\r' "$RODIN_STAGE/$RODIN_SCRIPT"; then
        echo "CRLF line endings are not allowed: $RODIN_SCRIPT" >&2
        exit 1
    fi
done

grep -Fxq 'export RODIN_REVERSE_IPC=1' "$RODIN_STAGE/service.sh" || {
    echo "Missing authenticated reverse IPC activation" >&2
    exit 1
}
grep -Fq 'App IPC: verified (daemon-initiated)' "$RODIN_STAGE/action.sh" || {
    echo "Module Action does not verify the Android app transport" >&2
    exit 1
}

RODIN_MODID="$(sed -n 's/^id=//p' "$RODIN_STAGE/module.prop")"
RODIN_VERSION_CODE="$(sed -n 's/^versionCode=//p' "$RODIN_STAGE/module.prop")"
[[ "$RODIN_MODID" =~ ^[a-zA-Z][a-zA-Z0-9._-]+$ ]] || {
    echo "Invalid KernelSU module id: $RODIN_MODID" >&2
    exit 1
}
[[ "$RODIN_VERSION_CODE" =~ ^[0-9]+$ ]] || {
    echo "Invalid KernelSU versionCode: $RODIN_VERSION_CODE" >&2
    exit 1
}

RODIN_APK_BADGING="$("$RODIN_AAPT2" dump badging "$RODIN_STAGE/app/RodinEssential.apk")"
RODIN_APK_HEADER="$(printf '%s\n' "$RODIN_APK_BADGING" | sed -n '1p')"
RODIN_APK_PACKAGE="$(printf '%s\n' "$RODIN_APK_HEADER" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
RODIN_APK_VERSION_CODE="$(printf '%s\n' "$RODIN_APK_HEADER" | sed -n "s/^package: name='[^']*' versionCode='\([^']*\)'.*/\1/p")"
RODIN_APK_VERSION_NAME="$(printf '%s\n' "$RODIN_APK_HEADER" | sed -n "s/^package: name='[^']*' versionCode='[^']*' versionName='\([^']*\)'.*/\1/p")"

[ "$RODIN_APK_PACKAGE" = "io.github.neeschal.rodinessential" ] || {
    echo "Unexpected APK package: $RODIN_APK_PACKAGE" >&2
    exit 1
}
[ "$RODIN_APK_VERSION_CODE" = "$RODIN_VERSION_CODE" ] || {
    echo "APK/module versionCode mismatch: $RODIN_APK_VERSION_CODE / $RODIN_VERSION_CODE" >&2
    exit 1
}
[ "$RODIN_APK_VERSION_NAME" = "${RODIN_VERSION#v}" ] || {
    echo "APK/module version mismatch: $RODIN_APK_VERSION_NAME / $RODIN_VERSION" >&2
    exit 1
}

"$RODIN_APKSIGNER" verify --verbose "$RODIN_STAGE/app/RodinEssential.apk" >/dev/null
RODIN_CERT_DIGEST="$("$RODIN_APKSIGNER" verify --print-certs \
    "$RODIN_STAGE/app/RodinEssential.apk" \
    | sed -n 's/^.*certificate SHA-256 digest: //p' | head -n 1 \
    | tr '[:upper:]' '[:lower:]')"
RODIN_EXPECTED_CERT_DIGEST="$(tr -d '[:space:]:' \
    <"$RODIN_PROJECT_ROOT/android/package/release-cert.sha256" \
    | tr '[:upper:]' '[:lower:]')"
[[ "$RODIN_CERT_DIGEST" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Unable to read APK signing certificate" >&2
    exit 1
}
[ "$RODIN_CERT_DIGEST" = "$RODIN_EXPECTED_CERT_DIGEST" ] || {
    echo "Official release certificate mismatch" >&2
    echo "expected=$RODIN_EXPECTED_CERT_DIGEST" >&2
    echo "actual=$RODIN_CERT_DIGEST" >&2
    exit 1
}
"$RODIN_ZIPALIGN" -c -P 16 -v 4 "$RODIN_STAGE/app/RodinEssential.apk" >/dev/null
if unzip -Z1 "$RODIN_STAGE/app/RodinEssential.apk" | grep -Eq '(^|/)classes([0-9]*)?\.dex$'; then
    echo "DEX is not allowed in the Rodin Essential APK" >&2
    exit 1
fi

file "$RODIN_STAGE/bin/rodin_daemon" | grep -q 'ARM aarch64'
file "$RODIN_STAGE/bin/rodin_ctl" | grep -q 'ARM aarch64'
readelf -lW "$RODIN_STAGE/bin/rodin_daemon" | grep -q '/system/bin/linker64'
readelf -lW "$RODIN_STAGE/bin/rodin_ctl" | grep -q '/system/bin/linker64'

for RODIN_BINARY in "$RODIN_STAGE/bin/rodin_daemon" "$RODIN_STAGE/bin/rodin_ctl"; do
    RODIN_LOAD_COUNT=0
    while read -r RODIN_ALIGNMENT; do
        [ -n "$RODIN_ALIGNMENT" ] || continue
        RODIN_LOAD_COUNT=$((RODIN_LOAD_COUNT + 1))
        if [ "$((RODIN_ALIGNMENT))" -lt 16384 ]; then
            echo "ELF alignment below 16 KB: $RODIN_BINARY ($RODIN_ALIGNMENT)" >&2
            exit 1
        fi
    done < <(readelf -lW "$RODIN_BINARY" | awk '$1 == "LOAD" { print $NF }')

    [ "$RODIN_LOAD_COUNT" -gt 0 ] || {
        echo "No ELF LOAD segments found: $RODIN_BINARY" >&2
        exit 1
    }
done

(
    cd "$RODIN_STAGE"
    zip -X -9 "$RODIN_ZIP" \
        module.prop customize.sh service.sh action.sh uninstall.sh skip_mount \
        app/RodinEssential.apk bin/rodin_daemon bin/rodin_ctl >/dev/null
)

unzip -tq "$RODIN_ZIP"
RODIN_ENTRIES="$(unzip -Z1 "$RODIN_ZIP")"
for RODIN_REQUIRED in \
    module.prop customize.sh service.sh action.sh uninstall.sh skip_mount \
    app/RodinEssential.apk bin/rodin_daemon bin/rodin_ctl; do
    echo "$RODIN_ENTRIES" | grep -Fxq "$RODIN_REQUIRED" || {
        echo "Missing module entry: $RODIN_REQUIRED" >&2
        exit 1
    }
done

if echo "$RODIN_ENTRIES" | grep -Eq '(^|/)system/'; then
    echo "Unexpected system overlay in the root module" >&2
    exit 1
fi
if echo "$RODIN_ENTRIES" | grep -Eq '(^|/)(sepolicy\.rule|apply-sepolicy\.sh)$'; then
    echo "Unexpected SELinux patch payload in the root module" >&2
    exit 1
fi

RODIN_STAGE_APK_SHA="$(sha256sum "$RODIN_STAGE/app/RodinEssential.apk" | awk '{print $1}')"
RODIN_ZIP_APK_SHA="$(unzip -p "$RODIN_ZIP" app/RodinEssential.apk | sha256sum | awk '{print $1}')"
[ "$RODIN_STAGE_APK_SHA" = "$RODIN_ZIP_APK_SHA" ] || {
    echo "APK payload checksum mismatch" >&2
    exit 1
}

cp -f "$RODIN_ZIP" "$RODIN_STABLE_ZIP"
sha256sum "$RODIN_ZIP" | tee "$RODIN_ZIP.sha256"

echo "ROOT_MODULE=PASS"
echo "MANAGERS=KernelSU Next, Magisk"
echo "APK_PACKAGE=$RODIN_APK_PACKAGE"
echo "APK_VERSION=$RODIN_APK_VERSION_NAME ($RODIN_APK_VERSION_CODE)"
echo "APK_CERT_SHA256=$RODIN_CERT_DIGEST"
echo "ZIP=$RODIN_ZIP"
echo "STABLE_ZIP=$RODIN_STABLE_ZIP"
