#!/usr/bin/env bash

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UI="$ROOT/ui/flutter"
FLUTTER_BIN="$(command -v flutter 2>/dev/null)"

if [ -z "$FLUTTER_BIN" ]; then
    echo "ERROR: flutter is not in PATH."
else
    FLUTTER_BIN="$(readlink -f "$FLUTTER_BIN")"
    FLUTTER_ROOT="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
    OUT="$ROOT/out/flutter-aot-proof"

    mkdir -p "$OUT"

    (
        cd "$UI" || return 1

        flutter pub get &&

        flutter \
            assemble \
            --output="$OUT" \
            -dTargetPlatform=android-arm64 \
            -dBuildMode=release \
            -dTargetFile=lib/main.dart \
            -dTrackWidgetCreation=false \
            android_aot_bundle_release_android-arm64
    )

    rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "FLUTTER_AOT_BUILD=FAIL rc=$rc"
    else
        APP_SO="$OUT/arm64-v8a/app.so"

        ASSETS="$OUT/flutter_assets"

        echo
        echo "===== AOT ARTIFACTS ====="
        echo "app_so=$APP_SO"
        echo "assets=$ASSETS"

        ok=1

        if [ -f "$APP_SO" ]; then
            file "$APP_SO"
            ls -lh "$APP_SO"
            sha256sum "$APP_SO"

            MACHINE="$(readelf -h "$APP_SO" 2>/dev/null | awk -F: '/Machine:/ {gsub(/^[ \t]+/, "", $2); print $2}')"
            echo "machine=$MACHINE"

            if echo "$MACHINE" | grep -qi 'AArch64'; then
                echo "AOT_ARM64=PASS"
            else
                echo "AOT_ARM64=FAIL"
                ok=0
            fi

            echo "--- AOT SYMBOLS ---"
            nm -D "$APP_SO" 2>/dev/null |
                grep -E '_kDart(Vm|Isolate)Snapshot(Data|Instructions)' |
                head -20 || true
        else
            echo "AOT_APP_SO=MISSING"
            ok=0
        fi

        if [ -d "$ASSETS" ]; then
            echo
            echo "===== FLUTTER ASSETS ====="
            find "$ASSETS" -type f -printf '%P %s bytes\n' | sort | head -120
            COUNT="$(find "$ASSETS" -type f | wc -l)"
            echo "asset_file_count=$COUNT"

            if [ "$COUNT" -gt 0 ]; then
                echo "FLUTTER_ASSETS=PASS"
            else
                echo "FLUTTER_ASSETS=FAIL"
                ok=0
            fi
        else
            echo "FLUTTER_ASSETS=MISSING"
            ok=0
        fi

        echo
        if [ "$ok" -eq 1 ]; then
            echo "FLUTTER_AOT_BUILD=PASS"
        else
            echo "FLUTTER_AOT_BUILD=FAIL"
        fi
    fi
fi
