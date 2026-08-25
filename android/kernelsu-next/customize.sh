#!/system/bin/sh

ui_print "***************************************"
ui_print "           Rodin Essential"
ui_print "      KernelSU Next / Magisk"
ui_print "***************************************"

if [ "${KSU:-false}" = "true" ]; then
    RODIN_MANAGER="KernelSU Next"
    RODIN_MANAGER_VERSION="${KSU_VER:-unknown}"
    RODIN_FALLBACK_DOMAIN=ksu
elif [ -n "${MAGISK_VER_CODE:-}" ]; then
    RODIN_MANAGER="Magisk"
    RODIN_MANAGER_VERSION="${MAGISK_VER:-unknown}"
    RODIN_FALLBACK_DOMAIN=magisk
else
    abort "! Install from KernelSU Next Manager or the Magisk app"
fi

if [ "$BOOTMODE" != "true" ]; then
    abort "! Install from the root manager while Android is running"
fi

if [ "$ARCH" != "arm64" ]; then
    abort "! Rodin Essential requires an arm64 device"
fi

RODIN_PRODUCT="$(getprop ro.product.device)"
RODIN_VENDOR="$(getprop ro.product.vendor.device)"
case "$RODIN_PRODUCT $RODIN_VENDOR" in
    *rodin*) ;;
    *) abort "! Unsupported device: $RODIN_PRODUCT / $RODIN_VENDOR" ;;
esac

[ -f "$MODPATH/bin/rodin_daemon" ] || abort "! Missing Rodin daemon"
[ -f "$MODPATH/bin/rodin_ctl" ] || abort "! Missing Rodin control client"
[ -f "$MODPATH/app/RodinEssential.apk" ] || abort "! Missing Rodin Essential APK"
[ -x /system/bin/pm ] || abort "! Android package manager is unavailable"

RODIN_INSTALL_CONTEXT="$(id -Z 2>/dev/null)"
RODIN_DAEMON_DOMAIN="$(printf '%s\n' "$RODIN_INSTALL_CONTEXT" \
    | sed -n 's/^u:r:\([^:][^:]*\):s0.*$/\1/p')"
case "$RODIN_DAEMON_DOMAIN" in
    su|ksu|magisk) ;;
    *) RODIN_DAEMON_DOMAIN="$RODIN_FALLBACK_DOMAIN" ;;
esac

# Root managers and ROM ports do not all use the same daemon SELinux type.
# Generate the single rule that matches the domain executing service.sh.
# The daemon additionally authenticates the APK's Linux UID with SO_PEERCRED.
printf 'allow appdomain %s unix_stream_socket connectto\n' "$RODIN_DAEMON_DOMAIN" \
    >"$MODPATH/sepolicy.rule"

# The APK is installed as an ordinary user application. No system overlay or
# KernelSU metamodule is required; only the separate daemon runs as root.
touch "$MODPATH/skip_mount"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/app" 0 0 0755 0644
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/sepolicy.rule" 0 0 0644

ui_print "- Installing the unprivileged Android app"
RODIN_INSTALL_RESULT="$(/system/bin/pm install --user 0 -r "$MODPATH/app/RodinEssential.apk" 2>&1)"
case "$RODIN_INSTALL_RESULT" in
    *Success*) ;;
    *)
        ui_print "$RODIN_INSTALL_RESULT"
        abort "! APK install failed; remove a differently signed copy and retry"
        ;;
esac

/system/bin/pm path io.github.neeschal.rodinessential >/dev/null 2>&1 || \
    abort "! Android did not register Rodin Essential"

ui_print "- Device: $RODIN_PRODUCT"
ui_print "- Root manager: $RODIN_MANAGER $RODIN_MANAGER_VERSION"
ui_print "- App: installed as a normal Android application"
ui_print "- Daemon: isolated privileged module service"
ui_print "- SELinux IPC domain: $RODIN_DAEMON_DOMAIN"
ui_print "- Reboot once when you are ready to activate the daemon"
