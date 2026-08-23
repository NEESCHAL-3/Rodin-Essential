#!/system/bin/sh

MODDIR=${0%/*}
RODIN_ROOT=/data/adb/rodin-essential
RODIN_DAEMON="$MODDIR/bin/rodin_daemon"
RODIN_LOG="$RODIN_ROOT/backend.log"
RODIN_LOG_OLD="$RODIN_ROOT/backend.log.1"
RODIN_WATCHDOG_PID="$RODIN_ROOT/watchdog.pid"
RODIN_WATCHDOG_LOCK="$RODIN_ROOT/watchdog.lock"
RODIN_SERVICE_PATH="$MODDIR/service.sh"

export RODIN_STATE_DIR="$RODIN_ROOT"

umask 077
mkdir -p "$RODIN_ROOT"
chmod 0700 "$RODIN_ROOT" 2>/dev/null

RODIN_LOG_BYTES="$(wc -c <"$RODIN_LOG" 2>/dev/null)"
case "$RODIN_LOG_BYTES" in
    ''|*[!0-9]*) ;;
    *)
        if [ "$RODIN_LOG_BYTES" -gt 1048576 ]; then
            mv -f "$RODIN_LOG" "$RODIN_LOG_OLD"
        fi
        ;;
esac

# mkdir is an atomic early-boot lock and prevents duplicate watchdog loops.
if ! mkdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null; then
    RODIN_EXISTING_PID="$(cat "$RODIN_WATCHDOG_LOCK/pid" 2>/dev/null)"
    RODIN_EXISTING_CMDLINE=""
    if [ -n "$RODIN_EXISTING_PID" ] && kill -0 "$RODIN_EXISTING_PID" 2>/dev/null; then
        RODIN_EXISTING_CMDLINE="$(tr '\000' ' ' <"/proc/$RODIN_EXISTING_PID/cmdline" 2>/dev/null)"
    fi
    case "$RODIN_EXISTING_CMDLINE" in
        *"/nees_rodin_essential_backend/service.sh"*) exit 0 ;;
    esac

    rm -f "$RODIN_WATCHDOG_LOCK/pid"
    rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null || exit 0
    mkdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null || exit 0
fi

echo $$ >"$RODIN_WATCHDOG_PID"
echo $$ >"$RODIN_WATCHDOG_LOCK/pid"

# Remove watchdogs left by older development packages of this same module.
for RODIN_PROC in /proc/[0-9]*; do
    RODIN_PID="${RODIN_PROC##*/}"
    [ "$RODIN_PID" = "$$" ] && continue
    RODIN_CMDLINE="$(tr '\000' ' ' <"$RODIN_PROC/cmdline" 2>/dev/null)"
    case "$RODIN_CMDLINE" in
        *"/nees_rodin_essential_backend/service.sh"*)
            kill -9 "$RODIN_PID" 2>/dev/null
            ;;
    esac
done

# Start the daemon shipped by this module, never an old copied binary.
for RODIN_PID in $(pidof rodin_daemon 2>/dev/null); do
    kill "$RODIN_PID" 2>/dev/null
done
sleep 1
for RODIN_PID in $(pidof rodin_daemon 2>/dev/null); do
    kill -9 "$RODIN_PID" 2>/dev/null
done

rodin_cleanup() {
    RODIN_OWNER="$(cat "$RODIN_WATCHDOG_LOCK/pid" 2>/dev/null)"
    if [ "$RODIN_OWNER" = "$$" ]; then
        rm -f "$RODIN_WATCHDOG_PID" "$RODIN_WATCHDOG_LOCK/pid"
        rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null
    fi
}

trap rodin_cleanup EXIT
trap 'exit 0' HUP INT TERM

while true; do
    if [ -x "$RODIN_DAEMON" ] && ! pidof rodin_daemon >/dev/null 2>&1; then
        echo "RODIN_MODULE_DAEMON_START path=$RODIN_DAEMON" >>"$RODIN_LOG"
        "$RODIN_DAEMON" >>"$RODIN_LOG" 2>&1
        RODIN_EXIT=$?
        echo "RODIN_MODULE_DAEMON_EXIT code=$RODIN_EXIT" >>"$RODIN_LOG"
    fi
    sleep 2
done
