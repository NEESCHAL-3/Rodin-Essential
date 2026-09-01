#!/system/bin/sh

MODDIR=${0%/*}
RODIN_ROOT=/data/adb/rodin-essential
RODIN_WATCHDOG_LOCK="$RODIN_ROOT/watchdog.lock"
RODIN_WATCHDOG_PID="$(cat "$RODIN_ROOT/watchdog.pid" 2>/dev/null)"
RODIN_PACKAGE=io.github.neeschal.rodinessential
RODIN_NATIVE_MODE=0
[ -f "$MODDIR/rom-native-mode" ] && RODIN_NATIVE_MODE=1

case "$RODIN_WATCHDOG_PID" in
    ''|*[!0-9]*) ;;
    *) kill "$RODIN_WATCHDOG_PID" 2>/dev/null ;;
esac

for RODIN_PROCESS_NAME in rodin_daemon rodin_essentiald; do
    for RODIN_PID in $(pidof "$RODIN_PROCESS_NAME" 2>/dev/null); do
        kill "$RODIN_PID" 2>/dev/null
    done
done
sleep 1
for RODIN_PROCESS_NAME in rodin_daemon rodin_essentiald; do
    for RODIN_PID in $(pidof "$RODIN_PROCESS_NAME" 2>/dev/null); do
        kill -9 "$RODIN_PID" 2>/dev/null
    done
done

rm -f "$RODIN_ROOT/watchdog.pid" "$RODIN_WATCHDOG_LOCK/pid" "$RODIN_WATCHDOG_LOCK/boot_id"
rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null
rm -f "$RODIN_ROOT/bin/rodin_daemon" "$RODIN_ROOT/bin/rodin_ctl"
rmdir "$RODIN_ROOT/bin" 2>/dev/null
rm -f "$RODIN_ROOT/backend.log" "$RODIN_ROOT/backend.log.1"

if [ "$RODIN_NATIVE_MODE" -eq 1 ]; then
    # The module APK is an Android package-manager update over the matching ROM
    # system app. Revert only that update, keep package data, and return daemon
    # ownership to init. The native state directory is never removed.
    /system/bin/cmd package uninstall-system-updates "$RODIN_PACKAGE" \
        >"$RODIN_ROOT/native-app-rollback.log" 2>&1 || true
    /system/bin/pm enable --user 0 "$RODIN_PACKAGE" >/dev/null 2>&1 || true
    for RODIN_NATIVE_SERVICE in rodin_daemon rodin_essentiald; do
        if [ -n "$(getprop "init.svc.$RODIN_NATIVE_SERVICE" 2>/dev/null)" ]; then
            /system/bin/setprop ctl.start "$RODIN_NATIVE_SERVICE" 2>/dev/null || true
        fi
    done
fi

# Standalone installations keep state.conf and the ordinary Android app so
# removing the root module does not erase user data. The app can be uninstalled
# normally from Android.
exit 0
