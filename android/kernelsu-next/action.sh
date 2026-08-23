#!/system/bin/sh

MODDIR=${0%/*}
RODIN_CTL="$MODDIR/bin/rodin_ctl"

echo "Rodin Essential Backend"
echo ""

RODIN_PIDS="$(pidof rodin_daemon 2>/dev/null)"
if [ -z "$RODIN_PIDS" ]; then
    echo "Status: waiting for activation"
    echo "Install the module and reboot when you are ready."
    exit 0
fi

RODIN_PING="$($RODIN_CTL PING 2>&1)"
case "$RODIN_PING" in
    "OK PONG "*)
        echo "Status: healthy"
        echo "Daemon PID: $RODIN_PIDS"
        echo "Protocol: ${RODIN_PING#OK PONG }"
        ;;
    *)
        echo "Status: daemon is running but did not answer"
        echo "$RODIN_PING"
        exit 1
        ;;
esac

RODIN_SNAPSHOT="$($RODIN_CTL GET snapshot 2>/dev/null)"
echo "$RODIN_SNAPSHOT" | tr ';' '\n' | grep -E '^(io|touch|touch_ack|touch_resampler_ready|perf)=' 2>/dev/null
