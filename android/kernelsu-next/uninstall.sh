#!/system/bin/sh

RODIN_ROOT=/data/adb/rodin-essential
RODIN_WATCHDOG_LOCK="$RODIN_ROOT/watchdog.lock"
RODIN_WATCHDOG_PID="$(cat "$RODIN_ROOT/watchdog.pid" 2>/dev/null)"

case "$RODIN_WATCHDOG_PID" in
    ''|*[!0-9]*) ;;
    *) kill "$RODIN_WATCHDOG_PID" 2>/dev/null ;;
esac

for RODIN_PID in $(pidof rodin_daemon 2>/dev/null); do
    kill "$RODIN_PID" 2>/dev/null
done
sleep 1
for RODIN_PID in $(pidof rodin_daemon 2>/dev/null); do
    kill -9 "$RODIN_PID" 2>/dev/null
done

rm -f "$RODIN_ROOT/watchdog.pid" "$RODIN_WATCHDOG_LOCK/pid" "$RODIN_WATCHDOG_LOCK/boot_id"
rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null
rm -f "$RODIN_ROOT/bin/rodin_daemon" "$RODIN_ROOT/bin/rodin_ctl"
rmdir "$RODIN_ROOT/bin" 2>/dev/null
rm -f "$RODIN_ROOT/backend.log" "$RODIN_ROOT/backend.log.1"

# Keep state.conf and the ordinary Android app so removing the root module does
# not erase user data. The app can be uninstalled normally from Android.
exit 0
