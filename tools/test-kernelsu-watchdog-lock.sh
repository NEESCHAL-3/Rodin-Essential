#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_SERVICE_SOURCE="$RODIN_PROJECT_ROOT/android/kernelsu-next/service.sh"
RODIN_TEST_ROOT="$(mktemp -d)"
RODIN_TEST_RUNNER=""

rodin_test_cleanup() {
    if [ -n "$RODIN_TEST_RUNNER" ]; then
        kill "$RODIN_TEST_RUNNER" 2>/dev/null || true
        wait "$RODIN_TEST_RUNNER" 2>/dev/null || true
    fi
    rm -rf -- "$RODIN_TEST_ROOT"
}
trap rodin_test_cleanup EXIT

RODIN_TEST_MODULE="$RODIN_TEST_ROOT/nees_rodin_essential_backend"
RODIN_TEST_STATE="$RODIN_TEST_ROOT/state"
RODIN_TEST_BOOT_ID="$RODIN_TEST_ROOT/boot_id"
mkdir -p "$RODIN_TEST_MODULE" "$RODIN_TEST_STATE/watchdog.lock"

sed \
    -e "s|RODIN_ROOT=/data/adb/rodin-essential|RODIN_ROOT=$RODIN_TEST_STATE|" \
    -e "s|/proc/sys/kernel/random/boot_id|$RODIN_TEST_BOOT_ID|" \
    "$RODIN_SERVICE_SOURCE" >"$RODIN_TEST_MODULE/service.sh"
chmod 0755 "$RODIN_TEST_MODULE/service.sh"
printf '%s\n' 'current-test-boot' >"$RODIN_TEST_BOOT_ID"

# Reproduce the field failure: a stale lock from the previous boot contains
# the same numeric PID assigned to the newly launched service process.
(
    printf '%s\n' "$BASHPID" >"$RODIN_TEST_STATE/watchdog.lock/pid"
    printf '%s\n' 'previous-test-boot' >"$RODIN_TEST_STATE/watchdog.lock/boot_id"
    exec bash "$RODIN_TEST_MODULE/service.sh"
) &
RODIN_TEST_RUNNER=$!

RODIN_TEST_ATTEMPT=0
while [ "$RODIN_TEST_ATTEMPT" -lt 50 ]; do
    RODIN_TEST_ATTEMPT=$((RODIN_TEST_ATTEMPT + 1))
    RODIN_LOCK_PID="$(cat "$RODIN_TEST_STATE/watchdog.lock/pid" 2>/dev/null || true)"
    RODIN_LOCK_BOOT_ID="$(cat "$RODIN_TEST_STATE/watchdog.lock/boot_id" 2>/dev/null || true)"
    if [ "$RODIN_LOCK_PID" = "$RODIN_TEST_RUNNER" ] \
        && [ "$RODIN_LOCK_BOOT_ID" = 'current-test-boot' ]; then
        echo "WATCHDOG_PID_REUSE_TEST=PASS"
        exit 0
    fi
    sleep 0.02
done

echo "Watchdog did not reclaim a same-PID lock from the previous boot" >&2
exit 1
