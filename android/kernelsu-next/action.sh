#!/system/bin/sh

MODDIR=${0%/*}
RODIN_CTL="$MODDIR/bin/rodin_ctl"
RODIN_POLICY="$MODDIR/sepolicy.rule"
RODIN_POLICY_STATUS=/data/adb/rodin-essential/ipc-policy.status

echo "Rodin Essential"
echo ""

if /system/bin/pm path io.github.neeschal.rodinessential >/dev/null 2>&1; then
    echo "App: installed"
else
    echo "App: missing; flash the module again from your root manager"
fi

RODIN_PIDS="$(pidof rodin_daemon 2>/dev/null)"
if [ -z "$RODIN_PIDS" ]; then
    echo "Daemon: waiting for activation"
    echo "Install the module and reboot when you are ready."
    exit 0
fi

RODIN_PING="$($RODIN_CTL PING 2>&1)"
case "$RODIN_PING" in
    "OK PONG "*)
        echo "Daemon: healthy"
        echo "Daemon PID: $RODIN_PIDS"
        echo "Protocol: ${RODIN_PING#OK PONG }"
        RODIN_PRIMARY_PID="${RODIN_PIDS%% *}"
        RODIN_DAEMON_CONTEXT="$(cat "/proc/$RODIN_PRIMARY_PID/attr/current" 2>/dev/null)"
        [ -n "$RODIN_DAEMON_CONTEXT" ] && echo "Daemon SELinux: $RODIN_DAEMON_CONTEXT"
        ;;
    *)
        echo "Daemon: running but did not answer"
        echo "$RODIN_PING"
        exit 1
        ;;
esac

RODIN_POLICY_DOMAIN="$(sed -n \
    's/^allow appdomain \([^ ][^ ]*\) unix_stream_socket connectto$/\1/p' \
    "$RODIN_POLICY" 2>/dev/null | head -n 1)"
[ -n "$RODIN_POLICY_DOMAIN" ] && echo "App IPC policy: appdomain -> $RODIN_POLICY_DOMAIN"

RODIN_POLICY_RESULT="$(sed -n 's/^result=//p' "$RODIN_POLICY_STATUS" 2>/dev/null | head -n 1)"
RODIN_LIVE_DOMAIN="$(sed -n 's/^domain=//p' "$RODIN_POLICY_STATUS" 2>/dev/null | head -n 1)"
RODIN_POLICY_METHOD="$(sed -n 's/^method=//p' "$RODIN_POLICY_STATUS" 2>/dev/null | head -n 1)"
if [ -n "$RODIN_POLICY_RESULT" ]; then
    echo "Live IPC patch: $RODIN_POLICY_RESULT ($RODIN_LIVE_DOMAIN via $RODIN_POLICY_METHOD)"
else
    echo "Live IPC patch: no boot status"
fi

RODIN_SNAPSHOT="$($RODIN_CTL GET snapshot 2>/dev/null)"
echo "$RODIN_SNAPSHOT" | tr ';' '\n' | grep -E '^(io|touch|touch_ack|touch_resampler_ready|perf)=' 2>/dev/null
