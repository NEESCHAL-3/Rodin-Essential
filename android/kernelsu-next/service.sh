#!/system/bin/sh

MODDIR=${0%/*}
RODIN_ROOT=/data/adb/rodin-essential
RODIN_DAEMON="$MODDIR/bin/rodin_daemon"
RODIN_LOG="$RODIN_ROOT/backend.log"
RODIN_LOG_OLD="$RODIN_ROOT/backend.log.1"
RODIN_WATCHDOG_PID="$RODIN_ROOT/watchdog.pid"
RODIN_WATCHDOG_LOCK="$RODIN_ROOT/watchdog.lock"
RODIN_WATCHDOG_BOOT_ID="$RODIN_WATCHDOG_LOCK/boot_id"
RODIN_SERVICE_PATH="$MODDIR/service.sh"
RODIN_CURRENT_BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
RODIN_PACKAGE=io.github.neeschal.rodinessential

export RODIN_STATE_DIR="$RODIN_ROOT"
export RODIN_REVERSE_IPC=1
export RODIN_LOOPBACK_IPC=1
export RODIN_TOUCH_PRIVATE_TARGET=1

umask 077
mkdir -p "$RODIN_ROOT"
chmod 0700 "$RODIN_ROOT" 2>/dev/null

# A ROM update can add the native backend after this module was installed.
# Never start a second supervisor or kill the ROM-owned daemon in that case.
if [ -x /product/bin/rodin_daemon ] \
    || [ -x /system_ext/bin/rodin_daemon ] \
    || [ -n "$(getprop init.svc.rodin_daemon 2>/dev/null)" ]; then
    echo "RODIN_MODULE_DISABLED rom_native_backend_detected" >>"$RODIN_LOG"
    exit 0
fi

RODIN_LOG_BYTES=0
if [ -f "$RODIN_LOG" ]; then
    RODIN_LOG_BYTES="$(wc -c <"$RODIN_LOG" 2>/dev/null)"
fi
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
    RODIN_EXISTING_BOOT_ID="$(cat "$RODIN_WATCHDOG_BOOT_ID" 2>/dev/null)"
    RODIN_EXISTING_CMDLINE=""
    if [ -n "$RODIN_CURRENT_BOOT_ID" ] \
        && [ "$RODIN_EXISTING_BOOT_ID" = "$RODIN_CURRENT_BOOT_ID" ] \
        && [ "$RODIN_EXISTING_PID" != "$$" ] \
        && kill -0 "$RODIN_EXISTING_PID" 2>/dev/null; then
        RODIN_EXISTING_CMDLINE="$(tr '\000' ' ' <"/proc/$RODIN_EXISTING_PID/cmdline" 2>/dev/null)"
    fi
    case "$RODIN_EXISTING_CMDLINE" in
        *"$RODIN_SERVICE_PATH"*) exit 0 ;;
    esac

    rm -f "$RODIN_WATCHDOG_LOCK/pid" "$RODIN_WATCHDOG_BOOT_ID"
    rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null || exit 0
    mkdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null || exit 0
fi

printf '%s\n' "$$" >"$RODIN_WATCHDOG_PID"
printf '%s\n' "$$" >"$RODIN_WATCHDOG_LOCK/pid"
printf '%s\n' "$RODIN_CURRENT_BOOT_ID" >"$RODIN_WATCHDOG_BOOT_ID"

# Remove watchdogs left by older development packages of this same module.
for RODIN_PROC in /proc/[0-9]*; do
    RODIN_PID="${RODIN_PROC##*/}"
    [ "$RODIN_PID" = "$$" ] && continue
    RODIN_CMDLINE="$(tr '\000' ' ' <"$RODIN_PROC/cmdline" 2>/dev/null)"
    case "$RODIN_CMDLINE" in
        *"$RODIN_SERVICE_PATH"*)
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
        rm -f "$RODIN_WATCHDOG_PID" "$RODIN_WATCHDOG_LOCK/pid" "$RODIN_WATCHDOG_BOOT_ID"
        rmdir "$RODIN_WATCHDOG_LOCK" 2>/dev/null
    fi
}

trap rodin_cleanup EXIT
trap 'exit 0' HUP INT TERM

rodin_resolve_app_uid() {
    RODIN_PACKAGE_ENTRY="$(/system/bin/pm list packages -U "$RODIN_PACKAGE" 2>/dev/null \
        | sed -n "s/^package:$RODIN_PACKAGE[[:space:]]*uid:\([0-9][0-9]*\).*$/\1/p" \
        | head -n 1)"
    case "$RODIN_PACKAGE_ENTRY" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$RODIN_PACKAGE_ENTRY" -ge 10000 ] 2>/dev/null; then
                printf '%s\n' "$RODIN_PACKAGE_ENTRY"
                return 0
            fi
            ;;
    esac

    RODIN_PACKAGE_ENTRY="$(/system/bin/dumpsys package "$RODIN_PACKAGE" 2>/dev/null \
        | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' \
        | head -n 1)"
    case "$RODIN_PACKAGE_ENTRY" in
        ''|*[!0-9]*) return 1 ;;
        *)
            [ "$RODIN_PACKAGE_ENTRY" -ge 10000 ] 2>/dev/null || return 1
            printf '%s\n' "$RODIN_PACKAGE_ENTRY"
            ;;
    esac
}

# KernelSU/Magisk late-start scripts may run while framework/vendor services
# are still publishing their boot defaults. Start the backend only after the
# completed Android boot so every persisted Rodin setting wins that race.
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    sleep 1
done

# Pin the daemon to the UID Android assigned to this exact APK. The daemon
# validates Unix peers with SO_PEERCRED and privileged-loopback peers against
# the kernel TCP table, so no app-to-root SELinux relaxation is required and no
# other ordinary application can issue hardware commands.
RODIN_UID_WAIT_LOGGED=0
while true; do
    RODIN_APP_UID="$(rodin_resolve_app_uid)"
    if [ -n "$RODIN_APP_UID" ]; then
        break
    fi
    if [ "$RODIN_UID_WAIT_LOGGED" -eq 0 ]; then
        echo "RODIN_MODULE_APP_UID_WAIT package=$RODIN_PACKAGE" >>"$RODIN_LOG"
        RODIN_UID_WAIT_LOGGED=1
    fi
    sleep 2
done
export RODIN_APP_UID
echo "RODIN_MODULE_APP_UID uid=$RODIN_APP_UID" >>"$RODIN_LOG"

while true; do
    if [ -x "$RODIN_DAEMON" ] && ! pidof rodin_daemon >/dev/null 2>&1; then
        echo "RODIN_MODULE_DAEMON_START path=$RODIN_DAEMON" >>"$RODIN_LOG"
        "$RODIN_DAEMON" >>"$RODIN_LOG" 2>&1
        RODIN_EXIT=$?
        echo "RODIN_MODULE_DAEMON_EXIT code=$RODIN_EXIT" >>"$RODIN_LOG"
    fi
    sleep 2
done
