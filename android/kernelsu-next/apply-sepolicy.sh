#!/system/bin/sh

MODDIR=${0%/*}
RODIN_ROOT=${RODIN_STATE_DIR:-/data/adb/rodin-essential}
RODIN_POLICY="$MODDIR/sepolicy.rule"
RODIN_STATUS=${1:-$RODIN_ROOT/ipc-policy.status}
RODIN_CONTEXT=${2:-}

umask 077
mkdir -p "$RODIN_ROOT"

rodin_write_status() {
    RODIN_STATUS_RESULT=$1
    RODIN_STATUS_METHOD=$2
    RODIN_STATUS_ATTEMPT=$3
    RODIN_STATUS_TMP="$RODIN_STATUS.$$"

    {
        printf 'result=%s\n' "$RODIN_STATUS_RESULT"
        printf 'domain=%s\n' "$RODIN_DOMAIN"
        printf 'context=%s\n' "$RODIN_CONTEXT"
        printf 'method=%s\n' "$RODIN_STATUS_METHOD"
        printf 'attempt=%s\n' "$RODIN_STATUS_ATTEMPT"
    } >"$RODIN_STATUS_TMP"
    mv -f "$RODIN_STATUS_TMP" "$RODIN_STATUS"
}

rodin_try_policy_tool() {
    RODIN_TOOL_METHOD=$1
    shift
    RODIN_TOOL_ATTEMPT=1

    while [ "$RODIN_TOOL_ATTEMPT" -le 3 ]; do
        if "$@" >/dev/null 2>&1; then
            rodin_write_status applied "$RODIN_TOOL_METHOD" "$RODIN_TOOL_ATTEMPT"
            return 0
        fi
        RODIN_TOOL_ATTEMPT=$((RODIN_TOOL_ATTEMPT + 1))
        sleep 1
    done
    return 1
}

if [ -z "$RODIN_CONTEXT" ]; then
    RODIN_CONTEXT="$(cat /proc/$$/attr/current 2>/dev/null | tr -d '\000')"
fi
if [ -z "$RODIN_CONTEXT" ]; then
    RODIN_CONTEXT="$(id -Z 2>/dev/null)"
fi

RODIN_DOMAIN="$(printf '%s\n' "$RODIN_CONTEXT" \
    | sed -n 's/^u:r:\([^:][^:]*\):s0.*$/\1/p')"
case "$RODIN_DOMAIN" in
    su|ksu|magisk) ;;
    *)
        RODIN_DOMAIN=unknown
        rodin_write_status rejected none 0
        exit 1
        ;;
esac

RODIN_RULE="allow appdomain $RODIN_DOMAIN unix_stream_socket connectto"
printf '%s\n' "$RODIN_RULE" >"$RODIN_POLICY" || {
    rodin_write_status write-failed none 0
    exit 1
}
chmod 0644 "$RODIN_POLICY" 2>/dev/null

rodin_try_ksu_policy() {
    if [ -n "${RODIN_KSUD:-}" ] && [ -x "$RODIN_KSUD" ]; then
        rodin_try_policy_tool "ksud:$RODIN_KSUD" \
            "$RODIN_KSUD" sepolicy patch "$RODIN_RULE" && return 0
    fi
    for RODIN_KSUD_CANDIDATE in /data/adb/ksud /data/adb/ksu/bin/ksud; do
        [ -x "$RODIN_KSUD_CANDIDATE" ] || continue
        rodin_try_policy_tool "ksud:$RODIN_KSUD_CANDIDATE" \
            "$RODIN_KSUD_CANDIDATE" sepolicy patch "$RODIN_RULE" && return 0
    done
    return 1
}

rodin_try_magisk_policy() {
    if [ -n "${RODIN_MAGISKPOLICY:-}" ] && [ -x "$RODIN_MAGISKPOLICY" ]; then
        rodin_try_policy_tool "magiskpolicy:$RODIN_MAGISKPOLICY" \
            "$RODIN_MAGISKPOLICY" --live "$RODIN_RULE" && return 0
    fi
    for RODIN_MAGISK_CANDIDATE in \
        /data/adb/magisk/magiskpolicy \
        /debug_ramdisk/magiskpolicy \
        /sbin/magiskpolicy; do
        [ -x "$RODIN_MAGISK_CANDIDATE" ] || continue
        rodin_try_policy_tool "magiskpolicy:$RODIN_MAGISK_CANDIDATE" \
            "$RODIN_MAGISK_CANDIDATE" --live "$RODIN_RULE" && return 0
    done
    RODIN_MAGISK_CANDIDATE="$(command -v magiskpolicy 2>/dev/null)"
    if [ -n "$RODIN_MAGISK_CANDIDATE" ] && [ -x "$RODIN_MAGISK_CANDIDATE" ]; then
        rodin_try_policy_tool "magiskpolicy:$RODIN_MAGISK_CANDIDATE" \
            "$RODIN_MAGISK_CANDIDATE" --live "$RODIN_RULE" && return 0
    fi
    return 1
}

# KernelSU Next commonly runs module services as ksu or su; Magisk uses
# magisk. Try the matching policy engine first, then the other engine for
# manager forks and coexistence setups.
case "$RODIN_DOMAIN" in
    magisk)
        rodin_try_magisk_policy || rodin_try_ksu_policy
        ;;
    *)
        rodin_try_ksu_policy || rodin_try_magisk_policy
        ;;
esac
RODIN_RESULT=$?

if [ "$RODIN_RESULT" -ne 0 ]; then
    # The root manager may already have loaded sepolicy.rule successfully.
    # Keep the daemon available, but expose the missing fallback in Action.
    rodin_write_status unavailable none 0
fi
exit "$RODIN_RESULT"
