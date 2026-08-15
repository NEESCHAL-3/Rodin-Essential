#!/usr/bin/env bash

FLUTTER_BIN="$(command -v flutter 2>/dev/null)"

if [ -z "$FLUTTER_BIN" ]; then
    echo "ERROR: flutter is not in PATH."
else
    FLUTTER_BIN="$(readlink -f "$FLUTTER_BIN")"
    FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
    ENGINE_SRC="$FLUTTER_ROOT/engine/src"

    (
        cd "$ENGINE_SRC" &&
        ./flutter/tools/gn --runtime-mode release --no-lto &&
        ./flutter/tools/gn \
            --android \
            --android-cpu arm64 \
            --runtime-mode release \
            --no-lto
    )

    rc=$?

    if [ "$rc" -eq 0 ]; then
        ninja -C "$ENGINE_SRC/out/host_release" gen_snapshot &&
        ninja -C "$ENGINE_SRC/out/android_release_arm64" \
            flutter/shell/platform/embedder:flutter_engine_library \
            gen_snapshot
    fi
fi
