#!/usr/bin/env bash

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
MIN_SDK=31
PKG="io.github.neeschal.rodinessential"

BT="$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -1)"
PLATFORM="36"
NDK_VER="$(find "$SDK/ndk" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -1)"

AAPT2="$SDK/build-tools/$BT/aapt2"
ZIPALIGN="$SDK/build-tools/$BT/zipalign"
APKSIGNER="$SDK/build-tools/$BT/apksigner"
ANDROID_JAR="$SDK/platforms/android-$PLATFORM/android.jar"
NDK="$SDK/ndk/$NDK_VER"
CLANG="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android${MIN_SDK}-clang"
READELF="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"

OUT="$ROOT/out/native-proof"
STAGE="$OUT/stage"
UNSIGNED="$OUT/Rodin-Essential-native-proof-unsigned.apk"
ALIGNED="$OUT/Rodin-Essential-native-proof-aligned.apk"
SIGNED="$OUT/Rodin-Essential-native-proof.apk"
KEYSTORE="$ROOT/android/package/rodin-essential-dev.jks"

mkdir -p "$OUT" "$STAGE/lib/arm64-v8a"
rm -f "$UNSIGNED" "$ALIGNED" "$SIGNED"
rm -rf "$STAGE/lib/arm64-v8a"
mkdir -p "$STAGE/lib/arm64-v8a"

export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CLANG"
export RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"

echo "===== BUILD RUST HOST ====="
cargo build \
    --manifest-path "$ROOT/Cargo.toml" \
    -p rodin-essential-host \
    --target aarch64-linux-android \
    --release || {
        echo "ERROR: Rust host build failed."
        return 1 2>/dev/null || true
    }

SO="$ROOT/target/aarch64-linux-android/release/librodin_essential_host.so"

if [ ! -f "$SO" ]; then
    echo "ERROR: native host library missing."
    return 1 2>/dev/null || true
else
    cp "$SO" "$STAGE/lib/arm64-v8a/"
fi

echo
echo "===== ELF ====="
file "$SO"
"$READELF" -lW "$SO" | grep -E 'LOAD|GNU_RELRO'

echo
echo "===== PACKAGE ZERO-DEX APK ====="

"$AAPT2" link \
    -I "$ANDROID_JAR" \
    --manifest "$ROOT/android/package/AndroidManifest.xml" \
    -o "$UNSIGNED" || {
        echo "ERROR: aapt2 packaging failed."
        return 1 2>/dev/null || true
    }

(
    cd "$STAGE" || return 1
    zip -0 -q "$UNSIGNED" lib/arm64-v8a/librodin_essential_host.so
) || {
    echo "ERROR: native library injection failed."
    return 1 2>/dev/null || true
}

"$ZIPALIGN" -P 16 -f 4 "$UNSIGNED" "$ALIGNED" || {
    echo "ERROR: zipalign failed."
    return 1 2>/dev/null || true
}

if [ ! -f "$KEYSTORE" ]; then
    echo
    echo "===== CREATE DEVELOPMENT SIGNING KEY ====="
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storepass android \
        -keypass android \
        -alias rodin-essential-dev \
        -keyalg RSA \
        -keysize 4096 \
        -validity 10000 \
        -dname "CN=Rodin Essential Development,O=Nees,C=NP" >/dev/null 2>&1 || {
            echo "ERROR: development key creation failed."
            return 1 2>/dev/null || true
        }
fi

"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-key-alias rodin-essential-dev \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$SIGNED" \
    "$ALIGNED" || {
        echo "ERROR: APK signing failed."
        return 1 2>/dev/null || true
    }

echo
echo "===== VERIFY ====="

if unzip -Z1 "$SIGNED" | grep -Eq '(^|/)classes[0-9]*\.dex$'; then
    echo "ZERO_DEX=FAIL"
    return 1 2>/dev/null || true
else
    echo "ZERO_DEX=PASS"
fi

"$ZIPALIGN" -c -P 16 -v 4 "$SIGNED" >/dev/null 2>&1
if [ "$?" -eq 0 ]; then
    echo "ZIPALIGN_16K=PASS"
else
    echo "ZIPALIGN_16K=FAIL"
    return 1 2>/dev/null || true
fi

"$APKSIGNER" verify --verbose "$SIGNED" | head -20

echo
echo "===== APK CONTENT ====="
unzip -l "$SIGNED" | grep -E 'AndroidManifest.xml|lib/arm64-v8a|classes.*\.dex'

echo
sha256sum "$SIGNED"
ls -lh "$SIGNED"

echo
echo "APK=$SIGNED"
