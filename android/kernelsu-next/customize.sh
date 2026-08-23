#!/system/bin/sh

ui_print "***************************************"
ui_print "           Rodin Essential"
ui_print "      KernelSU Next / Magisk"
ui_print "***************************************"

if [ "${KSU:-false}" = "true" ]; then
    RODIN_MANAGER="KernelSU Next"
    RODIN_MANAGER_VERSION="${KSU_VER:-unknown}"
elif [ -n "${MAGISK_VER_CODE:-}" ]; then
    RODIN_MANAGER="Magisk"
    RODIN_MANAGER_VERSION="${MAGISK_VER:-unknown}"
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
ui_print "- Reboot once when you are ready to activate the daemon"
