#!/usr/bin/env bash
set -euo pipefail

RODIN_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RODIN_AOSP="$RODIN_PROJECT_ROOT/android/aosp"
RODIN_PRODUCT_PRIVATE="$RODIN_AOSP/sepolicy/product/private"
RODIN_VENDOR_POLICY="$RODIN_AOSP/sepolicy/vendor/rodin_daemon.te"
RODIN_GENFS="$RODIN_AOSP/sepolicy/vendor/genfs_contexts"

for RODIN_REQUIRED in \
    Android.bp BoardConfigRodinEssential.mk rodin-essential.mk rodin_daemon.rc \
    sepolicy/product/public/rodin_daemon.te \
    sepolicy/product/private/file_contexts \
    sepolicy/product/private/keys.conf \
    sepolicy/product/private/mac_permissions.xml \
    sepolicy/product/private/rodin_app.te \
    sepolicy/product/private/rodin_daemon.te \
    sepolicy/product/private/seapp_contexts \
    sepolicy/vendor/genfs_contexts \
    sepolicy/vendor/rodin_daemon.te; do
    [ -s "$RODIN_AOSP/$RODIN_REQUIRED" ] || {
        echo "Missing AOSP integration file: $RODIN_REQUIRED" >&2
        exit 1
    }
done

grep -Fq 'presigned: true' "$RODIN_AOSP/Android.bp"
grep -Fq 'preprocessed: true' "$RODIN_AOSP/Android.bp"
grep -Fq 'dex_preopt:' "$RODIN_AOSP/Android.bp"
grep -Fq '"libbinder_ndk"' "$RODIN_AOSP/Android.bp"
if grep -Eq 'certificate:[[:space:]]*"platform"|check_elf_files:[[:space:]]*false' \
    "$RODIN_AOSP/Android.bp"; then
    echo "AOSP prebuilts must retain their signing identity and ELF checks" >&2
    exit 1
fi

grep -Fq 'PRODUCT_PACKAGES_DEBUG +=' "$RODIN_AOSP/rodin-essential.mk"
if sed -n '/^PRODUCT_PACKAGES +=/,/^$/p' "$RODIN_AOSP/rodin-essential.mk" \
    | grep -Fq 'rodin_ctl'; then
    echo "rodin_ctl must not be installed in production user builds" >&2
    exit 1
fi

grep -Fxq '[@RODIN_ESSENTIAL]' "$RODIN_PRODUCT_PRIVATE/keys.conf"
grep -Fq 'vendor/rodin-essential/prebuilt/RodinEssential.x509.pem' \
    "$RODIN_PRODUCT_PRIVATE/keys.conf"
grep -Fq '<signer signature="@RODIN_ESSENTIAL">' \
    "$RODIN_PRODUCT_PRIVATE/mac_permissions.xml"
grep -Fq '<package name="io.github.neeschal.rodinessential">' \
    "$RODIN_PRODUCT_PRIVATE/mac_permissions.xml"
grep -Fq '<seinfo value="rodin_essential"' \
    "$RODIN_PRODUCT_PRIVATE/mac_permissions.xml"
python3 - "$RODIN_PRODUCT_PRIVATE/mac_permissions.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
if root.tag != "policy":
    raise SystemExit("mac_permissions.xml root must be <policy>")
PY

grep -Fxq \
    'user=_app seinfo=rodin_essential name=io.github.neeschal.rodinessential domain=rodin_app type=app_data_file levelFrom=user' \
    "$RODIN_PRODUCT_PRIVATE/seapp_contexts"
grep -Fq 'untrusted_app_domain(rodin_app)' "$RODIN_PRODUCT_PRIVATE/rodin_app.te"
grep -Fq 'typeattribute rodin_app coredomain;' "$RODIN_PRODUCT_PRIVATE/rodin_app.te"
grep -Fq 'allow rodin_app rodin_daemon:unix_stream_socket connectto;' \
    "$RODIN_PRODUCT_PRIVATE/rodin_daemon.te"
grep -Fq 'settings_service:service_manager find;' \
    "$RODIN_PRODUCT_PRIVATE/rodin_daemon.te"
grep -Fq 'window_service:service_manager find;' \
    "$RODIN_PRODUCT_PRIVATE/rodin_daemon.te"
grep -Fq 'execute_no_trans' "$RODIN_PRODUCT_PRIVATE/rodin_daemon.te"
if grep -Eq 'allow[[:space:]]+(appdomain|untrusted_app)[[:space:]]+rodin_daemon' \
    "$RODIN_PRODUCT_PRIVATE/rodin_daemon.te"; then
    echo "AOSP socket access must remain restricted to rodin_app" >&2
    exit 1
fi

if grep -Eq '(^|[[:space:]])permissive[[:space:]]+rodin_daemon|sysfs_batteryinfo|allow[[:space:]]+rodin_daemon[[:space:]]+sysfs:file|package_service|ctl_(start|stop)_prop|dac_override|dac_read_search|sys_ptrace|:process[[:space:]]+ptrace' \
    "$RODIN_AOSP"/sepolicy/{product/private,product/public,vendor}/*; then
    echo "AOSP policy contains an unsafe or obsolete grant" >&2
    exit 1
fi

grep -Fq 'type sysfs_rodin_mali_devfreq, fs_type, sysfs_type;' "$RODIN_VENDOR_POLICY"
grep -Fq 'type sysfs_rodin_touch_report_rate, fs_type, sysfs_type;' "$RODIN_VENDOR_POLICY"
grep -Fq 'allow rodin_daemon sysfs_battery_supply:file r_file_perms;' "$RODIN_VENDOR_POLICY"
grep -Fq 'allow rodin_daemon vendor_sysfs_displayfeature:file r_file_perms;' "$RODIN_VENDOR_POLICY"
grep -Fq '/devices/platform/soc/13000000.mali/devfreq/13000000.mali' "$RODIN_GENFS"
grep -Fq '/devices/platform/goodix_ts.0/switch_report_rate' "$RODIN_GENFS"

grep -Fq 'user root' "$RODIN_AOSP/rodin_daemon.rc"
grep -Fq 'setenv RODIN_STATE_DIR /data/system/rodin-essential' "$RODIN_AOSP/rodin_daemon.rc"
grep -Fq 'setenv RODIN_DIRECT_INPUT_ONLY 1' "$RODIN_AOSP/rodin_daemon.rc"
grep -Fq 'fn touch_thp_memory_control_enabled()' \
    "$RODIN_PROJECT_ROOT/runtime/daemon-rust/src/lib.rs"
grep -Fq 'std::env::var("RODIN_DIRECT_INPUT_ONLY")' \
    "$RODIN_PROJECT_ROOT/runtime/daemon-rust/src/lib.rs"
grep -Fq 'on property:sys.boot_completed=1' "$RODIN_AOSP/rodin_daemon.rc"
if grep -Eq 'DAC_OVERRIDE|DAC_READ_SEARCH|SYS_PTRACE' "$RODIN_AOSP/rodin_daemon.rc"; then
    echo "AOSP daemon requests a platform-forbidden capability" >&2
    exit 1
fi

RODIN_PLAT_CIL="${RODIN_PLAT_SEPOLICY_CIL:-}"
if [ -n "$RODIN_PLAT_CIL" ]; then
    [ -f "$RODIN_PLAT_CIL" ] || {
        echo "RODIN_PLAT_SEPOLICY_CIL does not exist: $RODIN_PLAT_CIL" >&2
        exit 1
    }
    command -v secilc >/dev/null 2>&1 || {
        echo "secilc is required for the requested platform neverallow check" >&2
        exit 1
    }
    secilc -m -M true -G -c 30 \
        "$RODIN_PLAT_CIL" "$RODIN_PROJECT_ROOT/tools/aosp-policy-contract.cil" \
        -o /dev/null -f /dev/null
    echo 'AOSP_PLATFORM_NEVERALLOW_TEST=PASS'
else
    echo 'AOSP_PLATFORM_NEVERALLOW_TEST=SKIP (set RODIN_PLAT_SEPOLICY_CIL)'
fi

echo 'AOSP_INTEGRATION_CONTRACT_TEST=PASS'
