#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_MODULE_SOURCE="$RODIN_PROJECT_ROOT/android/kernelsu-next"
RODIN_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
RODIN_STAMP="$(date +%Y%m%d-%H%M%S)"
RODIN_BUILD_ROOT="$RODIN_PROJECT_ROOT/out/kernelsu-next/$RODIN_STAMP"
RODIN_STAGE="$RODIN_BUILD_ROOT/module"
RODIN_CARGO_TARGET="$RODIN_BUILD_ROOT/cargo"

RODIN_VERSION="$(sed -n 's/^version=//p' "$RODIN_MODULE_SOURCE/module.prop")"
RODIN_ZIP_NAME="Rodin-Essential-KernelSU-Next-${RODIN_VERSION}.zip"
RODIN_ZIP="$RODIN_BUILD_ROOT/$RODIN_ZIP_NAME"
RODIN_STABLE_ZIP="$RODIN_PROJECT_ROOT/out/Rodin-Essential-KernelSU-Next.zip"

RODIN_NDK_VERSION="$(find "$RODIN_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)"
RODIN_NDK="$RODIN_SDK_ROOT/ndk/$RODIN_NDK_VERSION"
RODIN_TOOLCHAIN="$RODIN_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
RODIN_LINKER="$RODIN_TOOLCHAIN/aarch64-linux-android31-clang"
RODIN_STRIP="$RODIN_TOOLCHAIN/llvm-strip"

[ -x "$RODIN_LINKER" ] || {
    echo "Missing Android arm64 linker: $RODIN_LINKER" >&2
    exit 1
}

mkdir -p "$RODIN_STAGE/bin" "$RODIN_CARGO_TARGET"

echo "===== RODIN ESSENTIAL — KERNELSU NEXT MODULE ====="
echo "version=$RODIN_VERSION"
echo "ndk=$RODIN_NDK_VERSION"
echo "output=$RODIN_ZIP"

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$RODIN_LINKER"
export CARGO_TARGET_DIR="$RODIN_CARGO_TARGET"
export RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"

cargo build \
    --locked \
    --release \
    --target aarch64-linux-android \
    --manifest-path "$RODIN_PROJECT_ROOT/runtime/daemon-rust/Cargo.toml"

install -m 0644 "$RODIN_MODULE_SOURCE/module.prop" "$RODIN_STAGE/module.prop"
install -m 0755 "$RODIN_MODULE_SOURCE/customize.sh" "$RODIN_STAGE/customize.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/service.sh" "$RODIN_STAGE/service.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/action.sh" "$RODIN_STAGE/action.sh"
install -m 0755 "$RODIN_MODULE_SOURCE/uninstall.sh" "$RODIN_STAGE/uninstall.sh"
install -m 0644 "$RODIN_MODULE_SOURCE/skip_mount" "$RODIN_STAGE/skip_mount"
install -m 0755 "$RODIN_CARGO_TARGET/aarch64-linux-android/release/rodin_daemon" "$RODIN_STAGE/bin/rodin_daemon"
install -m 0755 "$RODIN_CARGO_TARGET/aarch64-linux-android/release/rodin_ctl" "$RODIN_STAGE/bin/rodin_ctl"

"$RODIN_STRIP" --strip-unneeded "$RODIN_STAGE/bin/rodin_daemon"
"$RODIN_STRIP" --strip-unneeded "$RODIN_STAGE/bin/rodin_ctl"

for RODIN_SCRIPT in customize.sh service.sh action.sh uninstall.sh; do
    bash -n "$RODIN_STAGE/$RODIN_SCRIPT"
    if LC_ALL=C grep -q $'\r' "$RODIN_STAGE/$RODIN_SCRIPT"; then
        echo "CRLF line endings are not allowed: $RODIN_SCRIPT" >&2
        exit 1
    fi
done

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
        bin/rodin_daemon bin/rodin_ctl >/dev/null
)

unzip -tq "$RODIN_ZIP"
RODIN_ENTRIES="$(unzip -Z1 "$RODIN_ZIP")"
for RODIN_REQUIRED in \
    module.prop customize.sh service.sh action.sh uninstall.sh skip_mount \
    bin/rodin_daemon bin/rodin_ctl; do
    echo "$RODIN_ENTRIES" | grep -Fxq "$RODIN_REQUIRED" || {
        echo "Missing module entry: $RODIN_REQUIRED" >&2
        exit 1
    }
done

if echo "$RODIN_ENTRIES" | grep -Eq '(^|/)(system/|.*\.apk$|.*\.dex$)'; then
    echo "Unexpected APK, DEX, or system overlay in backend-only module" >&2
    exit 1
fi

cp -f "$RODIN_ZIP" "$RODIN_STABLE_ZIP"
sha256sum "$RODIN_ZIP" | tee "$RODIN_ZIP.sha256"

echo "KERNELSU_NEXT_MODULE=PASS"
echo "ZIP=$RODIN_ZIP"
echo "STABLE_ZIP=$RODIN_STABLE_ZIP"
