#!/usr/bin/env bash
# Isolated lab build; never packages or edits the real Rodin Essential APK.
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SOURCE/../../.." && pwd)"
MODE="${RODIN_TILE_LAB_MODE:-debug}"
case "$MODE" in
    debug) LINK_FLAGS=(--debug-mode) ;;
    release) LINK_FLAGS=() ;;
    *) echo 'RODIN_TILE_LAB_MODE must be debug or release' >&2; exit 1 ;;
esac
OUT="$ROOT/out/zero-dex-tile-lab/$MODE"
SDK="${ANDROID_SDK_ROOT:-/home/neeschal/Android/Sdk}"
NDK="$SDK/ndk/30.0.16248370/toolchains/llvm/prebuilt/linux-x86_64"
TOOLS="$SDK/build-tools/35.0.0"
KEYSTORE="${RODIN_KEYSTORE:?Set existing local development keystore}"
ALIAS="${RODIN_KEY_ALIAS:?Set existing local development key alias}"
mkdir -p "$OUT/lib/arm64-v8a"
cp "$SOURCE/wrap.sh" "$OUT/lib/arm64-v8a/wrap.sh"
chmod 0755 "$OUT/lib/arm64-v8a/wrap.sh"
# Use Android JNI types with the standard JVMTI ABI header, not desktop JNI.
"$NDK/bin/aarch64-linux-android31-clang++" -std=c++17 -O2 -fPIC -shared \
    -include "$NDK/sysroot/usr/include/jni.h" -D_JAVASOFT_JNI_H_ \
    -I /usr/lib/jvm/java-21-openjdk-amd64/include \
    "$SOURCE/tile_lab.cpp" -o "$OUT/lib/arm64-v8a/librodin_tile_lab.so" \
    -static-libstdc++ -llog -landroid -Wl,-z,max-page-size=16384 \
    -Wall -Wextra -Werror
"$TOOLS/aapt2" compile --dir "$SOURCE/res" -o "$OUT/resources.zip"
"$TOOLS/aapt2" link -o "$OUT/unsigned.apk" --manifest "$SOURCE/AndroidManifest.xml" \
    -I "$SDK/platforms/android-36/android.jar" "${LINK_FLAGS[@]}" "$OUT/resources.zip"
( cd "$OUT"; zip -0 -r unsigned.apk lib >/dev/null )
"$TOOLS/zipalign" -P 16 -f 4 "$OUT/unsigned.apk" "$OUT/Rodin-Zero-DEX-Tile-Lab.apk"
"$TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$ALIAS" \
    --ks-pass "pass:${RODIN_KEYSTORE_PASS:-android}" "$OUT/Rodin-Zero-DEX-Tile-Lab.apk"
"$TOOLS/apksigner" verify "$OUT/Rodin-Zero-DEX-Tile-Lab.apk"
"$TOOLS/zipalign" -c -P 16 4 "$OUT/Rodin-Zero-DEX-Tile-Lab.apk"
if unzip -Z1 "$OUT/Rodin-Zero-DEX-Tile-Lab.apk" | grep -Eq '\.(dex|jar|odex|vdex)$'; then
    echo 'Managed code detected: experiment rejected' >&2; exit 1
fi
BADGING="$("$TOOLS/aapt2" dump badging "$OUT/Rodin-Zero-DEX-Tile-Lab.apk")"
if [[ "$MODE" == release ]] && grep -q 'application-debuggable' <<<"$BADGING"; then
    echo 'Release control unexpectedly debuggable: rejected' >&2; exit 1
fi
if [[ "$MODE" == debug ]] && ! grep -q 'application-debuggable' <<<"$BADGING"; then
    echo 'Debug lab missing debuggable flag: rejected' >&2; exit 1
fi
echo "Lab mode: $MODE (not a production bypass tile)"
echo "$OUT/Rodin-Zero-DEX-Tile-Lab.apk"
