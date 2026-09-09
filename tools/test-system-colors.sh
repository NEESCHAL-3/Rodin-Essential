#!/usr/bin/env bash
set -euo pipefail

RODIN_PALETTE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_PALETTE_TEST_DIR="$(mktemp -d -t rodin-system-colors.XXXXXXXX)"
trap 'rm -f "$RODIN_PALETTE_TEST_DIR/host-tests"; rmdir "$RODIN_PALETTE_TEST_DIR"' EXIT

cargo test --manifest-path "$RODIN_PALETTE_ROOT/Cargo.toml" \
    -p rodin-essential-daemon system_colors::tests
rustc --edition=2024 --test "$RODIN_PALETTE_ROOT/tools/tests/system-colors-host.rs" \
    -o "$RODIN_PALETTE_TEST_DIR/host-tests"
"$RODIN_PALETTE_TEST_DIR/host-tests"

cd "$RODIN_PALETTE_ROOT/ui/flutter"
flutter test test/system_colors_test.dart test/system_colors_preview_test.dart \
    test/system_colors_monitor_test.dart test/backend_connection_test.dart
