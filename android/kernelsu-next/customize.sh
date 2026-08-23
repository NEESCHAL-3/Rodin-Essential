#!/system/bin/sh

ui_print "***************************************"
ui_print "        Rodin Essential Backend"
ui_print "          KernelSU Next module"
ui_print "***************************************"

if [ "$KSU" != "true" ]; then
    abort "! Install this ZIP from KernelSU Next Manager"
fi

if [ "$BOOTMODE" != "true" ]; then
    abort "! Recovery installation is not supported"
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

touch "$MODPATH/skip_mount"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "- Device: $RODIN_PRODUCT"
ui_print "- KernelSU Next: $KSU_VER"
ui_print "- Root daemon installed separately from the app"
ui_print "- Reboot later to activate this module"
