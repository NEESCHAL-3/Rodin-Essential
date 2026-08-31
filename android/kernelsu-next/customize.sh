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

if [ -x /product/bin/rodin_daemon ] \
    || [ -x /system_ext/bin/rodin_daemon ] \
    || [ -n "$(getprop init.svc.rodin_daemon 2>/dev/null)" ]; then
    abort "! ROM-native Rodin Essential detected; do not install the root module too"
fi

# The module changes no system partition files, so KernelSU does not need a
# mounting metamodule. The APK remains an ordinary application; only the
# separate hardware daemon runs in the root manager domain.
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
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
        ui_print "$RODIN_INSTALL_RESULT"
        ui_print "! A differently signed testing/ROM copy is installed"
        ui_print "! Uninstall that app once, then flash this same ZIP again"
        ui_print "! Rodin daemon settings under /data/adb are not deleted"
        abort "! Android correctly refused a cross-signature update"
        ;;
    *)
        ui_print "$RODIN_INSTALL_RESULT"
        abort "! APK installation failed"
        ;;
esac

/system/bin/pm path io.github.neeschal.rodinessential >/dev/null 2>&1 || \
    abort "! Android did not register Rodin Essential"

RODIN_EXPECTED_VERSION_CODE="$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" | head -n 1)"
RODIN_INSTALLED_VERSION_CODE="$(/system/bin/dumpsys package io.github.neeschal.rodinessential 2>/dev/null \
    | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)"
[ -n "$RODIN_EXPECTED_VERSION_CODE" ] || abort "! Module versionCode is missing"
[ "$RODIN_INSTALLED_VERSION_CODE" = "$RODIN_EXPECTED_VERSION_CODE" ] || \
    abort "! App/module version mismatch: $RODIN_INSTALLED_VERSION_CODE / $RODIN_EXPECTED_VERSION_CODE"

ui_print "- Device: $RODIN_PRODUCT"
ui_print "- Root manager: $RODIN_MANAGER $RODIN_MANAGER_VERSION"
ui_print "- App: installed as a normal Android application"
ui_print "- Daemon: isolated privileged module service"
ui_print "- IPC: authenticated Unix and privileged-loopback transports"
ui_print "- System overlay: none; no KernelSU metamodule required"
ui_print "- Reboot once when you are ready to activate the daemon"
