#!/usr/bin/env bash
# Package an already compiled, matching Flutter AOT/native development build.
# Does not install, flash, alter the signing identity, or publish anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: package-local-aot.sh ABSOLUTE_BUILD_DIRECTORY}"
SDK="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
KEYSTORE="${RODIN_KEYSTORE:?Set the existing signing keystore path}"
ALIAS="${RODIN_KEY_ALIAS:?Set the existing signing alias}"
PASS="${RODIN_KEYSTORE_PASS:-android}"
TOOLS=""
while IFS= read -r VERSION; do
    CANDIDATE="$SDK/build-tools/$VERSION"
    if [ -x "$CANDIDATE/aapt2" ] && [ -x "$CANDIDATE/apksigner" ] && [ -x "$CANDIDATE/zipalign" ]; then
        TOOLS="$CANDIDATE"
        break
    fi
done < <(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -Vr)
[ -n "$TOOLS" ] || { echo 'No complete Android build-tools installation found' >&2; exit 1; }
NATIVE="$OUT/native-cargo/aarch64-linux-android/release"
LIBAPP="$OUT/flutter-aot/arm64-v8a/app.so"
if [ ! -f "$LIBAPP" ]; then LIBAPP="$OUT/flutter-aot/lib/libapp.so"; fi
if [ ! -f "$LIBAPP" ]; then
    LIBAPP="$(find "$OUT/flutter-aot" -type f \( -name app.so -o -name libapp.so \) | head -1)"
fi
for FILE in "$LIBAPP" "$NATIVE/librodin_essential_host.so" "$NATIVE/rodin_daemon" "$KEYSTORE"; do
    [ -f "$FILE" ] || { echo "Missing build input: $FILE" >&2; exit 1; }
done
mkdir -p "$OUT/package/lib/arm64-v8a"
bash "$ROOT/tools/compile-platform-bridge.sh" "$OUT"
"$TOOLS/aapt2" compile --dir "$ROOT/android/package/res" -o "$OUT/package/resources.zip"
"$TOOLS/aapt2" link -o "$OUT/package/unsigned.apk" --manifest "$ROOT/android/package/AndroidManifest.xml" \
    -I "$SDK/platforms/android-36/android.jar" "$OUT/package/resources.zip"
cp "$LIBAPP" "$OUT/package/lib/arm64-v8a/libapp.so"
cp "$NATIVE/librodin_essential_host.so" "$OUT/package/lib/arm64-v8a/"
cp "$ROOT/runtime/flutter-engine/prebuilt/android-arm64/libflutter_engine.so" "$OUT/package/lib/arm64-v8a/"
mkdir -p "$OUT/package/assets/flutter_assets"
cp "$ROOT/runtime/flutter-engine/prebuilt/android-arm64/icudtl.dat" "$OUT/package/assets/"
cp -a "$OUT/flutter-aot/flutter_assets/." "$OUT/package/assets/flutter_assets/"
find "$OUT/flutter-aot/flutter_assets" -type f -printf '%P\n' | LC_ALL=C sort > "$OUT/package/assets/flutter_assets.index"
RODIN_RUNTIME_ASSET_STAMP="$(
    (
        cd "$OUT/package/assets"
        find flutter_assets -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
        sha256sum icudtl.dat
    ) | sha256sum | awk '{print $1}'
)"
printf '%s\n' "$RODIN_RUNTIME_ASSET_STAMP" > "$OUT/package/assets/rodin_runtime.stamp"
(
    cd "$OUT/package"
    zip -0 -r unsigned.apk lib assets >/dev/null
)
(cd "$OUT/platform-dex" && zip -0 "$OUT/package/unsigned.apk" classes.dex >/dev/null)
"$TOOLS/zipalign" -P 16 -f 4 "$OUT/package/unsigned.apk" "$OUT/Rodin-Essential-Per-App-Development.apk"
"$TOOLS/apksigner" sign --ks "$KEYSTORE" --ks-key-alias "$ALIAS" --ks-pass "pass:$PASS" \
    "$OUT/Rodin-Essential-Per-App-Development.apk"
"$TOOLS/apksigner" verify "$OUT/Rodin-Essential-Per-App-Development.apk"
"$TOOLS/zipalign" -c -P 16 4 "$OUT/Rodin-Essential-Per-App-Development.apk"
bash "$ROOT/tools/check-platform-dex.sh" "$OUT/Rodin-Essential-Per-App-Development.apk"
for ELF in "$OUT/package/lib/arm64-v8a/"*.so "$NATIVE/rodin_daemon" "$NATIVE/rodin_ctl"; do
    readelf -lW "$ELF" | awk '$1=="LOAD" && strtonum($NF)<16384 {bad=1} END {exit bad}'
done
echo "$OUT/Rodin-Essential-Per-App-Development.apk"
