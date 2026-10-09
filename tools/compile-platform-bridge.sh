#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?output directory required}"
SDK="${ANDROID_SDK_ROOT:?Android SDK required}"
TOOLS="$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
mkdir -p "$OUT/platform-classes" "$OUT/platform-dex"
mapfile -d '' SOURCES < <(find "$ROOT/android/platform" -name '*.java' -print0)
javac --release 8 -classpath "$SDK/platforms/android-36/android.jar" -d "$OUT/platform-classes" "${SOURCES[@]}"
mapfile -d '' CLASSES < <(find "$OUT/platform-classes" -name '*.class' -print0)
java -cp "$TOOLS/lib/d8.jar" com.android.tools.r8.D8 --release --min-api 31 --lib "$SDK/platforms/android-36/android.jar" --output "$OUT/platform-dex" "${CLASSES[@]}"
DEXDUMP="$TOOLS/dexdump"
if [ ! -x "$DEXDUMP" ]; then
    DEXDUMP="$(find "$SDK/build-tools" -type f -name dexdump | sort -V | tail -1)"
fi
"$DEXDUMP" "$OUT/platform-dex/classes.dex" | awk -F "'" '/Class descriptor/ {print $2}' > "$OUT/platform-dex/classes.txt"
if grep -Ev '^Lio/github/neeschal/rodinessential/(RodinActivity|BypassTileService)(;|\$)' "$OUT/platform-dex/classes.txt"; then
    echo 'Unexpected managed class in platform bridge' >&2; exit 1
fi
test "$(wc -c < "$OUT/platform-dex/classes.dex")" -le 32768
