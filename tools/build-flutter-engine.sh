#!/usr/bin/env bash
set -euo pipefail

RODIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_FLUTTER_BIN="$(command -v flutter 2>/dev/null || true)"

[ -n "$RODIN_FLUTTER_BIN" ] || {
    echo "Flutter is not in PATH" >&2
    exit 1
}

RODIN_FLUTTER_BIN="$(readlink -f "$RODIN_FLUTTER_BIN")"
RODIN_FLUTTER_ROOT="$(cd "$(dirname "$RODIN_FLUTTER_BIN")/.." && pwd)"
RODIN_ENGINE_SRC="${RODIN_FLUTTER_ENGINE_SRC:-$RODIN_FLUTTER_ROOT/engine/src}"
RODIN_ENGINE_OUT="$RODIN_ENGINE_SRC/out/android_release_arm64"
RODIN_PREBUILT="$RODIN_ROOT/runtime/flutter-engine/prebuilt/android-arm64"

[ -x "$RODIN_ENGINE_SRC/flutter/tools/gn" ] || {
    echo "Flutter engine checkout not found: $RODIN_ENGINE_SRC" >&2
    echo "Set RODIN_FLUTTER_ENGINE_SRC to the engine src directory" >&2
    exit 1
}

command -v ninja >/dev/null 2>&1 || {
    echo "ninja is required" >&2
    exit 1
}

RODIN_EXPECTED_REVISION="$(tr -d '[:space:]' <"$RODIN_FLUTTER_ROOT/bin/internal/engine.version")"
RODIN_ACTUAL_REVISION="$(git -C "$RODIN_ENGINE_SRC" rev-parse HEAD 2>/dev/null || true)"

if [ -n "$RODIN_ACTUAL_REVISION" ] && [ "$RODIN_ACTUAL_REVISION" != "$RODIN_EXPECTED_REVISION" ]; then
    echo "Flutter framework and engine revisions do not match" >&2
    echo "framework engine: $RODIN_EXPECTED_REVISION" >&2
    echo "engine checkout:  $RODIN_ACTUAL_REVISION" >&2
    exit 1
fi

(
    cd "$RODIN_ENGINE_SRC"
    ./flutter/tools/gn \
        --android \
        --android-cpu arm64 \
        --runtime-mode release \
        --no-lto
)

ninja -C "$RODIN_ENGINE_OUT" \
    flutter/shell/platform/embedder:flutter_engine_library

for RODIN_ARTIFACT in \
    "$RODIN_ENGINE_OUT/libflutter_engine.so" \
    "$RODIN_ENGINE_OUT/icudtl.dat" \
    "$RODIN_ENGINE_SRC/flutter/shell/platform/embedder/embedder.h"; do
    [ -f "$RODIN_ARTIFACT" ] || {
        echo "Missing engine artifact: $RODIN_ARTIFACT" >&2
        exit 1
    }
done

mkdir -p "$RODIN_PREBUILT" "$RODIN_ROOT/runtime/flutter-engine/include"
install -m 0644 "$RODIN_ENGINE_OUT/libflutter_engine.so" "$RODIN_PREBUILT/libflutter_engine.so"
install -m 0644 "$RODIN_ENGINE_OUT/icudtl.dat" "$RODIN_PREBUILT/icudtl.dat"
install -m 0644 \
    "$RODIN_ENGINE_SRC/flutter/shell/platform/embedder/embedder.h" \
    "$RODIN_ROOT/runtime/flutter-engine/include/embedder.h"

echo "FLUTTER_ENGINE_BUILD=PASS"
echo "ENGINE_REVISION=$RODIN_EXPECTED_REVISION"
echo "PREBUILT_DIR=$RODIN_PREBUILT"
