# AOSP ROM integration

This guide integrates Rodin Essential into an Android 12 or newer source build
for Xiaomi Rodin. The installed application remains a normal Android app. A
separate init service runs the hardware daemon as root under its own SELinux
domain, so the finished ROM needs no Magisk, KernelSU, root prompt, or root
manager.

The template targets `/product` and Android's split product/vendor SELinux
policy. It is a source-build integration, not a script for modifying a mounted
dynamic partition on a running phone.

## 1. Choose and retain the APK signing key

The APK is imported with `presigned: true` and `preprocessed: true`, preserving
the verified APK without a Soong rewrite. The same certificate is also used to
assign only this package to the dedicated `rodin_app` SELinux domain. Choose one
ROM-owned signing key and retain it for the full lifetime of this package.

The private key is used only while exporting the bundle. It is never copied to
the bundle or committed to the ROM source tree. The bundle contains only the
public X.509 certificate required by SELinux policy generation.

Android will not install an update signed by a different certificate. If a ROM
previously shipped Rodin Essential with another key, keep that key or plan an
explicit uninstall/data migration. Do not work around Android's signature
check by automatically deleting the user's app data.

## 2. Export a self-contained bundle

From the repository root:

```bash
RODIN_KEYSTORE=/absolute/path/rom-app.jks \
RODIN_KEY_ALIAS=rodin-essential \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/export-aosp-bundle.sh
```

All four signing variables are forwarded to the normal verified release build.
The export stops if the key is missing, the APK is not signed, a binary is not
ARM64, or the APK contains DEX.

The generated directory has this layout:

```text
RodinEssential-<timestamp>/
├── Android.bp
├── BoardConfigRodinEssential.mk
├── README.md
├── SHA256SUMS
├── SIGNING-CERTIFICATE.txt
├── docs/
│   └── ROM_INTEGRATION.md
├── prebuilt/
│   ├── RodinEssential.apk
│   ├── RodinEssential.x509.pem
│   ├── rodin_ctl
│   └── rodin_daemon
├── rodin-essential.mk
├── rodin_daemon.rc
└── sepolicy/
    ├── product/
    │   ├── public/
    │   │   └── rodin_daemon.te
    │   └── private/
    │       ├── file_contexts
    │       ├── keys.conf
    │       ├── mac_permissions.xml
    │       ├── rodin_app.te
    │       ├── rodin_daemon.te
    │       └── seapp_contexts
    └── vendor/
        ├── genfs_contexts
        └── rodin_daemon.te
```

Verify the export before staging it:

```bash
cd dist/aosp/RodinEssential-<timestamp>
sha256sum -c SHA256SUMS
openssl x509 -in prebuilt/RodinEssential.x509.pem -noout -fingerprint -sha256
```

## 3. Stage the bundle in the ROM tree

The helper can build, verify, and stage the bundle in one command:

```bash
RODIN_KEYSTORE=/absolute/path/rom-app.jks \
RODIN_KEY_ALIAS=rodin-essential \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/integrate-aosp-rom.sh /absolute/path/to/aosp
```

It creates `vendor/rodin-essential`, refuses to replace an existing directory,
and does not edit the device tree automatically. For manual integration, copy
the complete exported directory to the same path.

Add the product fragment to the Rodin product makefile:

```makefile
$(call inherit-product, vendor/rodin-essential/rodin-essential.mk)
```

Add the policy fragment to `device/xiaomi/rodin/BoardConfig.mk`:

```makefile
include vendor/rodin-essential/BoardConfigRodinEssential.mk
```

The resulting modules are installed as follows:

```text
/product/app/RodinEssential/RodinEssential.apk
/product/bin/rodin_daemon
/product/etc/init/rodin_daemon.rc
```

`rodin_ctl` is added through `PRODUCT_PACKAGES_DEBUG`, so it is installed only
on `userdebug` and `eng` builds.

The APK is not platform-signed, privileged, or assigned UID 1000. Preserving its
own certificate is intentional: `keys.conf`, `mac_permissions.xml`, and
`seapp_contexts` bind that certificate and exact package name to `rodin_app`.

## 4. SELinux ownership model

The policy is split by responsibility:

- Product public policy exports the `rodin_daemon` domain and executable type
  so the vendor policy can reference them.
- Product private policy owns the init transition, daemon state labels,
  certificate-bound app domain, system-service access, and private control
  socket rule.
- Vendor policy owns access to Rodin kernel nodes and Xiaomi/MediaTek services.

Production socket access is intentionally limited to:

```text
rodin_app -> rodin_daemon:unix_stream_socket connectto
```

Do not replace it with an `appdomain` or `untrusted_app` allow. That would let
unrelated applications issue hardware commands. `rodin_ctl` access from the
shell is compiled only for `userdebug` and `eng` builds.

The bundled policy assigns dedicated types only to the generic sysfs paths that
Rodin Essential must write:

```text
/sys/devices/platform/soc/13000000.mali/devfreq/13000000.mali
/sys/devices/platform/13000000.mali/devfreq/13000000.mali
/sys/devices/platform/goodix_ts.0/switch_report_rate
```

The first two cover the Mali devfreq layouts seen across Rodin vendor bases.
The Goodix path is a fallback for ROMs that omit Xiaomi's TouchFeature AIDL
service. FocalTech and other supported Rodin panels use the vendor AIDL path;
they do not depend on the Goodix sysfs node.

Never grant the coredomain generic `sysfs:file` write access. If the target
device tree already labels one of these exact paths, reconcile the duplicate
`genfscon` entry and grant only that existing dedicated type.

## 5. Validate the target vendor policy

The template matches the labels observed on Rodin's vendor stack, including:

```text
hal_touchfeature_xiaomi_default
vendor_hal_displayfeature_xiaomi_default
hal_touchfeature_xiaomi_service
vendor_hal_displayfeature_xiaomi_service
sysfs_battery_supply
sysfs_blockio
sysfs_devices_block
sysfs_ged
sysfs_mali_power_policy
sysfs_memory
sysfs_therm
sysfs_usb_supply
sysfs_zram
vendor_sysfs_displayfeature
proc_powerhal_cpu_ctrl
proc_touch_boost
proc_tp_file
```

OEM ports can rename policy types while keeping the same kernel path. Inspect
the exact vendor image used by the ROM:

```bash
adb shell ps -AZ | grep -E 'touchfeature|displayfeature'
adb shell ls -lZ \
  /sys/class/devfreq/13000000.mali/governor \
  /sys/class/misc/mali0/device/power_policy \
  /sys/kernel/ged/hal/gpu_boost_level \
  /sys/module/ged/parameters/ged_boost_enable \
  /proc/powerhal_cpu_ctrl/perfserv_freq \
  /proc/touch_boost/enable \
  /proc/tp_fw_version
```

Update only target types that differ on that ROM. Do not make the daemon
permissive, grant generic hardware access, or paste denial-generated policy
without reviewing the path and operation.

### CPU exact-lock policy

CPU frequency ranges require Rodin's `thermal_message/sconfig` and
`thermal_message/cpu_limits` nodes through `sysfs_therm`, plus
`powerhal_cpu_ctrl/perfserv_freq` through `proc_powerhal_cpu_ctrl`. The daemon
uses OEM mode 6 only while a custom CPU range exists and restores the previous
mode after the last reset. Thermal daemons remain running; these permissions
belong only to `rodin_daemon`.

### Touch policy

Native 240/480 Hz timing uses Xiaomi's public TouchFeature AIDL service. The
1000 Hz output path keeps that native calibration and opens the detected Rodin
multitouch event directly with the daemon's narrow `input_device` permission.
The AOSP init service sets `RODIN_DIRECT_INPUT_ONLY=1`, which also prevents the
daemon from inspecting touch-service memory or duplicating another process's
file descriptors. Do not add `SYS_PTRACE` or touch-HAL process access. Android
16 reserves that capability for a fixed set of platform diagnostics, and the
supplied neverallow contract intentionally rejects it.

## 6. Build and policy validation

Run the repository contract check before exporting or updating the template:

```bash
./tools/test-aosp-integration.sh
```

For an additional platform neverallow probe, point it at the target ROM's
compiled platform CIL:

```bash
RODIN_PLAT_SEPOLICY_CIL=/absolute/path/to/plat_sepolicy.cil \
  ./tools/test-aosp-integration.sh
```

This probe is not a substitute for building the target device policy. In the
ROM tree, run:

```bash
m RodinEssential rodin_daemon rodin_ctl
m selinux_policy
m sepolicy_tests
m treble_sepolicy_tests
```

Confirm the generated product MAC-permissions file contains the Rodin
certificate mapping and that the APK certificate matches the exported PEM.
Keep ELF dependency checks enabled; do not use `check_elf_files: false` to hide
a mismatched prebuilt.

## 7. State and process lifetime

At `post-fs-data`, init creates and labels:

```text
/data/system/rodin-essential
```

After `sys.boot_completed=1`, init starts `rodin_daemon` and restarts it after
an unexpected exit. The daemon loads its saved state, reapplies every persisted
domain after framework and vendor services settle, and continuously corrects
owned settings that drift.

The UI process is not the owner of active settings. Swiping it from recents,
force-stopping it, or restarting System UI does not stop the daemon. Normal OTA
updates retain the state file because it lives on `/data`.

Do not ship or install the KernelSU/Magisk module on a ROM with the native
integration. Two supervisors would compete for the socket and hardware state;
the module installer intentionally rejects a detected ROM-native daemon.

## 8. Device verification

On a freshly flashed `userdebug` build:

```bash
adb root
adb shell getenforce
adb shell ps -AZ | grep -E 'rodin_(app|daemon)|rodin_daemon'
adb shell /product/bin/rodin_ctl PING
adb shell /product/bin/rodin_ctl GET snapshot
adb shell dumpsys package io.github.neeschal.rodinessential \
  | grep -E 'userId=|seInfo=|versionCode='
adb shell ls -ldZ /data/system/rodin-essential
```

Expected results:

- SELinux is `Enforcing`.
- App domain is `u:r:rodin_app:s0` with an ordinary `_app` UID.
- Daemon domain is `u:r:rodin_daemon:s0` and daemon UID is root.
- Ping returns `OK PONG 13.4`.
- State directory type is `rodin_daemon_data_file`.

Verify the installed APK remains zero-DEX:

```bash
adb pull /product/app/RodinEssential/RodinEssential.apk /tmp/RodinEssential.apk
unzip -Z1 /tmp/RodinEssential.apk \
  | grep -E '(^|/)classes([0-9]*)?\.dex$' && exit 1 || true
```

Perform a full persistence pass:

1. Apply representative GPU, CPU, UFS, touch, display, charging, and ZRAM
   settings.
2. Compare the UI and `rodin_ctl GET snapshot` with live kernel/vendor readback.
3. Force-stop the package and verify the settings remain active.
4. Reboot, wait for boot completion and the vendor settling window, then verify
   every saved setting again.
5. Repeat critical GPU and touch readback after screen off/on.
6. Review enforcing denials after the complete pass:

```bash
adb shell logcat -b all -d | grep 'avc: denied'
```

The shell control-client rule is absent from a production `user` build. Test
the final user build through the normal application and daemon telemetry.

## 9. Updating or removing the integration

For every update, export and replace the APK, daemon, control client, public
certificate, build files, and policy together. Never mix protocol versions or
certificates from separate exports.

To remove the integration, remove the `PRODUCT_PACKAGES` and BoardConfig include
lines, then delete `vendor/rodin-essential`. A clean ROM build will omit the
components. Retain `/data/system/rodin-essential` for a future reinstall or
remove it only through an explicit user-visible migration.

Direct writes to a live `/product`, `/system_ext`, or `/odm` partition are not a
supported release method. Dynamic partitions, AVB, snapshots, split SELinux
policy, and OTA slot changes make that installation non-reproducible. Use this
source integration for a rootless ROM or the script-only root module for an
existing rooted ROM.
