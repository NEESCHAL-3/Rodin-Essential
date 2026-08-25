#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_HELPER_SOURCE="$RODIN_PROJECT_ROOT/android/kernelsu-next/apply-sepolicy.sh"
RODIN_TEST_ROOT="$(mktemp -d)"

rodin_test_cleanup() {
    rm -rf -- "$RODIN_TEST_ROOT"
}
trap rodin_test_cleanup EXIT

RODIN_TEST_MODULE="$RODIN_TEST_ROOT/module"
RODIN_TEST_STATE="$RODIN_TEST_ROOT/state"
RODIN_KSU_ARGS="$RODIN_TEST_ROOT/ksu.args"
RODIN_MAGISK_ARGS="$RODIN_TEST_ROOT/magisk.args"
mkdir -p "$RODIN_TEST_MODULE" "$RODIN_TEST_STATE"
cp "$RODIN_HELPER_SOURCE" "$RODIN_TEST_MODULE/apply-sepolicy.sh"
chmod 0755 "$RODIN_TEST_MODULE/apply-sepolicy.sh"

printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\\n" "$@" >"$RODIN_TEST_ARGS"' \
    >"$RODIN_TEST_ROOT/fake-ksud"
chmod 0755 "$RODIN_TEST_ROOT/fake-ksud"

RODIN_TEST_ARGS="$RODIN_KSU_ARGS" \
RODIN_STATE_DIR="$RODIN_TEST_STATE" \
RODIN_KSUD="$RODIN_TEST_ROOT/fake-ksud" \
RODIN_MAGISKPOLICY="$RODIN_TEST_ROOT/missing-magiskpolicy" \
    bash "$RODIN_TEST_MODULE/apply-sepolicy.sh" \
    "$RODIN_TEST_STATE/ksu.status" 'u:r:su:s0'

grep -Fxq 'allow appdomain su unix_stream_socket connectto' \
    "$RODIN_TEST_MODULE/sepolicy.rule"
grep -Fxq 'result=applied' "$RODIN_TEST_STATE/ksu.status"
grep -Fxq 'domain=su' "$RODIN_TEST_STATE/ksu.status"
grep -Fxq 'sepolicy' "$RODIN_KSU_ARGS"
grep -Fxq 'patch' "$RODIN_KSU_ARGS"
grep -Fxq 'allow appdomain su unix_stream_socket connectto' "$RODIN_KSU_ARGS"

printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\\n" "$@" >"$RODIN_TEST_ARGS"' \
    >"$RODIN_TEST_ROOT/fake-magiskpolicy"
chmod 0755 "$RODIN_TEST_ROOT/fake-magiskpolicy"

RODIN_TEST_ARGS="$RODIN_MAGISK_ARGS" \
RODIN_STATE_DIR="$RODIN_TEST_STATE" \
RODIN_KSUD="$RODIN_TEST_ROOT/missing-ksud" \
RODIN_MAGISKPOLICY="$RODIN_TEST_ROOT/fake-magiskpolicy" \
    bash "$RODIN_TEST_MODULE/apply-sepolicy.sh" \
    "$RODIN_TEST_STATE/magisk.status" 'u:r:magisk:s0'

grep -Fxq 'allow appdomain magisk unix_stream_socket connectto' \
    "$RODIN_TEST_MODULE/sepolicy.rule"
grep -Fxq 'result=applied' "$RODIN_TEST_STATE/magisk.status"
grep -Fxq 'domain=magisk' "$RODIN_TEST_STATE/magisk.status"
grep -Fxq -- '--live' "$RODIN_MAGISK_ARGS"
grep -Fxq 'allow appdomain magisk unix_stream_socket connectto' "$RODIN_MAGISK_ARGS"

if RODIN_STATE_DIR="$RODIN_TEST_STATE" \
    bash "$RODIN_TEST_MODULE/apply-sepolicy.sh" \
    "$RODIN_TEST_STATE/invalid.status" 'u:r:init:s0'; then
    echo 'Unsupported daemon domain was accepted' >&2
    exit 1
fi
grep -Fxq 'result=rejected' "$RODIN_TEST_STATE/invalid.status"

echo 'ROOT_MODULE_POLICY_TEST=PASS'
