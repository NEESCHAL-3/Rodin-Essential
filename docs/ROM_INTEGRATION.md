# AOSP ROM integration

This guide integrates Rodin Essential into an Android 12–17 ROM for Xiaomi
Rodin. The result does not require Magisk, KernelSU, a root prompt, or a root
manager. The APK remains an ordinary app process; Android init owns the separate
root daemon.

The supplied layout targets `/product` and modern split SELinux policy. It is
intended for ROM source builds, not direct mutation of a running dynamic
partition.

## 1. Build a self-contained bundle

From the repository root:

```bash
./tools/export-aosp-bundle.sh
```

The generated directory contains:

```text
RodinEssential-<timestamp>/
    ├── Android.bp
    ├── BoardConfigRodinEssential.mk
    ├── README.md
    ├── SHA256SUMS
├── prebuilt/
│   ├── RodinEssential.apk
│   ├── rodin_daemon
    │   └── rodin_ctl
    ├── rodin-essential.mk
    ├── rodin_daemon.rc
└── sepolicy/
    ├── product/
    │   ├── public/rodin_daemon.te
    │   └── private/
    │       ├── file_contexts
    │       ├── rodin_app.te
    │       ├── rodin_daemon.te
    │       └── seapp_contexts
    └── vendor/rodin_daemon.te
```

Verify the bundle before copying it:

```bash
cd dist/aosp/RodinEssential-<timestamp>
sha256sum -c SHA256SUMS
```

## 2. Add it to the ROM tree

The integration helper performs the build, verification, and staging step:

```bash
./tools/integrate-aosp-rom.sh /absolute/path/to/aosp
```

It refuses to replace an existing `vendor/rodin-essential` directory and never
edits device-tree files automatically. This keeps updates reviewable in the ROM
repository.

For manual integration, copy the entire generated directory to this source
path:

```text
vendor/rodin-essential/
```

Add the supplied product fragment to `device/xiaomi/rodin/device.mk` or the
Rodin product makefile:

```makefile
$(call inherit-product, vendor/rodin-essential/rodin-essential.mk)
```

`RodinEssential` is installed in `/product/app`, and the native tools are
installed in `/product/bin`. The daemon module installs `rodin_daemon.rc` into
`/product/etc/init` through its `init_rc` property.

The imported APK is re-signed with the ROM platform certificate. It still uses
a normal application UID because the manifest has no shared UID and the module
is not privileged.

## 3. Include split SELinux policy

Include the supplied policy fragment from the device `BoardConfig.mk`:

```makefile
include vendor/rodin-essential/BoardConfigRodinEssential.mk
```

The split is intentional:

- Product public policy exports the `rodin_daemon` type so vendor policy can
  grant access to Rodin hardware labels.
- Product private policy owns the init transition, state files, dedicated app
  domain, Android service-manager access, and private socket rule.
- Vendor policy owns GPU, CPU, GED, charging, thermal, touch, ZRAM, block, and
  Xiaomi HAL access.

Do not replace the dedicated `rodin_app` rule with an `appdomain` allow. That
would let every installed application send hardware commands to the daemon.

## 4. Validate vendor labels

The vendor policy template matches the labels observed on Rodin's current
vendor stack, including:

```text
hal_touchfeature_xiaomi_default
vendor_hal_displayfeature_xiaomi_default
hal_touchfeature_xiaomi_service
vendor_hal_displayfeature_xiaomi_service
sysfs_ged
sysfs_mali_power_policy
sysfs_therm
sysfs_usb_supply
sysfs_zram
proc_powerhal_cpu_ctrl
proc_touch_boost
proc_tp_file
```

OEM ports sometimes rename a type without changing the node. On the exact
vendor image shipped with the ROM, inspect the labels rather than guessing:

```bash
adb shell ps -AZ | grep -E 'touchfeature|displayfeature'
adb shell ls -lZ \
  /sys/class/devfreq/13000000.mali/governor \
  /sys/class/misc/mali0/device/power_policy \
  /sys/kernel/ged/hal/gpu_boost_level \
  /sys/module/ged/parameters/ged_boost_enable \
  /proc/touch_boost/enable \
  /proc/tp_fw_version
```

Update only the mismatched target types. Do not make the daemon permissive, add
global allow rules, or blindly paste generated policy. Rodin's Mali devfreq and
Goodix fallback nodes currently use the generic `sysfs` label; if the ROM tree
already defines a dedicated type, use it and remove the generic rule.

### 1000 Hz touch policy

The native 240/480 Hz paths use the touch AIDL service. The 1000 Hz output path
also reads the touch service timing block and duplicates its event descriptor,
so it requires the narrowly scoped `process ptrace`, `fd use`, and input-device
rules included in the vendor template.

If the ROM has an additional neverallow for this vendor domain, review that rule
with the device security maintainer. Removing the 1000 Hz block leaves native
240/480 Hz available but intentionally makes the 1000 Hz command fail instead
of reporting a false success.

## 5. State, boot, and process lifetime

The init service sets:

```text
RODIN_STATE_DIR=/data/system/rodin-essential
```

At `post-fs-data`, init creates and relabels that directory. At
`sys.boot_completed=1`, it starts the daemon; init restarts it after an unexpected
exit. The daemon loads `state.conf`, reapplies the saved configuration, and then
guards against vendor drift.

The UI process is not the owner of active settings. Force-closing the app,
swiping it from recents, or restarting System UI does not stop the daemon.
Regular OTA updates retain the state file because it lives on `/data`.

Do not ship the KernelSU backend module in the same build. Two daemon
supervisors would compete for the same abstract socket and hardware state.

## 6. Why there is no privileged-permission XML

The manifest requests only ordinary Android permissions. All privileged work is
performed by `rodin_daemon`, not by the APK. A `privapp-permissions` file would
therefore be empty and would not help the application.

This design also means:

- The APK does not run as root.
- The APK does not run as UID 0 or UID 1000.
- The APK cannot open protected sysfs nodes directly.
- Removing the daemon or its SELinux policy disables tuning even if the APK is
  still installed.

## 7. Build the ROM

Run a focused build first:

```bash
m RodinEssential rodin_daemon rodin_ctl
m selinux_policy
```

Then build the normal target. If product artifact-path enforcement is enabled,
allow these three modules through the ROM's existing product-partition policy;
do not move the daemon between partitions without updating its init path, file
contexts, and policy ownership together.

## 8. Verification on a userdebug build

After flashing:

```bash
adb root
adb shell ps -AZ | grep rodin
adb shell /product/bin/rodin_ctl PING
adb shell /product/bin/rodin_ctl GET snapshot
adb shell dumpsys package io.github.neeschal.rodinessential | grep userId
adb shell ls -ldZ /data/system/rodin-essential
```

Expected properties:

- App domain: `u:r:rodin_app:s0`
- Daemon domain: `u:r:rodin_daemon:s0`
- Daemon user: `root`
- App user: an ordinary `_app` UID, not `root` or `system`
- Ping: `OK PONG 13.1`
- State directory type: `rodin_daemon_data_file`

Verify the installed APK remains zero-DEX:

```bash
adb pull /product/app/RodinEssential/RodinEssential.apk /tmp/RodinEssential.apk
unzip -Z1 /tmp/RodinEssential.apk | grep -E 'classes([0-9]*)?\.dex' && exit 1 || true
```

Then test persistence:

1. Select a touch mode, UFS scheduler, and performance profile.
2. Force-stop the package and verify the live hardware values remain active.
3. Reboot and wait for boot completion.
4. Confirm the selected values and daemon snapshot match.
5. Repeat after screen off/on because vendor services can rewrite touch and GPU
   state during display transitions.

The `rodin_ctl` socket rule is restricted to `userdebug` and `eng`. Its failure
from `shell` on a production `user` build is expected; the `rodin_app` domain
remains authorized.

## 9. SELinux release checks

Before shipping:

```bash
m sepolicy_tests
m treble_sepolicy_tests
```

Boot enforcing and review denials from a complete feature pass:

```bash
adb shell getenforce
adb shell logcat -b all -d | grep 'avc: denied'
```

Every grant should correspond to a path or HAL used by the daemon. Keep the UI
domain free of direct hardware access.

## 10. Updates and removal

For an update, replace all three prebuilts from the same export so the APK host,
daemon protocol, and control client stay synchronized.

To remove the integration, delete the `PRODUCT_PACKAGES` entries and policy
directory references, then remove `vendor/rodin-essential`. The next clean ROM
build omits the binaries. `/data/system/rodin-essential` can be retained for a
future reinstall or removed by an explicit migration step in the ROM updater.

## Direct live-partition installation

Direct writes to a running `/product` or `/system_ext` image are not an official
installation method. Dynamic partitions, AVB, snapshots, SELinux labels, and OTA
slot changes make that path unreliable. Use the AOSP source integration for a
rootless ROM release or the backend-only KernelSU Next module for development on
an existing ROM.
