# Rodin Essential: unpacked-ROM integration

For porters rebuilding ROM images for **Rodin devices**. Not a flashable ZIP.
The package contains the app, daemon, init service and **only Rodin Essential
policy additions**. No complete platform or vendor policy is supplied. Use your
own ROM's policy, whether HyperOS, AOSP or an OEM port. Vendor labels and hardware
interfaces must match that target.

Application/module: 1.18.5 / 11805. IPC protocol: 13.6. The app and native binaries
are identical to the matching module. Android init starts the baked service;
users need no root grant, Magisk, KernelSU or `/data/adb` scripts.

## 1. Extract your ROM

Use your ROM kitchen to extract the partition images from `super.img`, then
extract their files. Keep its permission and file-context metadata. EROFS and
ext4 use the same extract/edit/rebuild workflow. Place the directories under
one root:

```text
rom/
  system/etc/selinux/       # system/system/etc/selinux also supported
  system_ext/etc/selinux/  # if present
  product/etc/selinux/
  vendor/etc/selinux/
  odm/etc/selinux/          # if present
```

Use complete policies, mappings and version files from **that same target
build**. Do not mix policies from different ROMs. Keep precompiled caches until
the merged replacement has passed validation.

## 2. Generate the target-specific policy changes

`policy/rodin-essential.cil` contains only Rodin additions. An extra CIL beside
the canonical policy is not automatically loaded by init. The tool appends it
to your `product_sepolicy.cil`, preserving unrelated rules and resolving vendor
types in the complete split policy. Leave `vendor_sepolicy.cil` untouched unless
a reviewed target label adaptation is needed. The extension is `.cil`, not `.cli`.

On Linux or Ubuntu in WSL, install the host tools:

```bash
sudo apt-get update
sudo apt-get install python3 secilc selinux-utils
```

Use a compiler supporting the target Android policy syntax. Extract this ZIP
into `rodin-integration`, alongside `rom`. From their parent directory run:

```bash
python3 rodin-integration/tools/merge-unpacked-rom-policy.py \
  --rom rom --output rodin-merged \
  --touch-capability-exception
```

The explicit touch flag scopes the required native-touch capability exception
to the daemon; other domains keep their restrictions. SELinux is not disabled.
The tool edits **copies of your ROM files**, never the input tree, compiles the
full target policy and validates file contexts before producing deployable
files. It merges the APK certificate, exact app package mapping and daemon
labels into the target's existing XML/context files.

Proceed only if `rodin-merged/READY.txt` exists. Otherwise read
`rodin-merged/validation/*.log` and do not copy incomplete output.

If vendor types differ, the tool lists missing labels. Confirm their actual
counterparts in that ROM's policy and hardware labels, then supply a JSON
mapping with `--labels labels.json`. Do not map unrelated types merely to make
compilation succeed. Nonstandard layouts can provide the complete CIL list,
relative to `rom`, with `--inputs inputs.json`. `--policy-version` selects the
binary policy version (default 30).

If the **original target policy** already fails strict neverallow checking,
review its baseline log first. `--permit-baseline-neverallows` is an explicit
porter exception requiring successful runtime compilation and no new
neverallow conflicts. It is not a strict-policy or CTS pass and cannot ignore
a conflict introduced by Rodin Essential.

## 3. Copy payloads and generated changes

Merge the **contents** of both directories into the extracted `rom` tree:

```text
rodin-integration/copy-to-extracted-rom/
rodin-merged/copy-to-extracted-rom/
```

Keep unrelated files. The first directory contains only:

```text
product/app/RodinEssential/RodinEssential.apk
product/bin/rodin_daemon
product/bin/rodin_ctl
product/etc/init/rodin_daemon.rc
```

The second contains your own target policy files with Rodin additions. Its
platform file appears only for the requested native-touch exception; its
original policy comes from **your ROM**, not this ZIP.

Do not install a second daemon in system/vendor or add root-module scripts.
Init uses `/product/bin/rodin_daemon`; state lives in
`/data/system/rodin-essential`. A manual `su` launch is not a permanent bake.

## 4. Remove stale caches before rebuilding

**After a successful merge**, remove only paths listed in
`rodin-merged/REMOVE-AFTER-VALIDATION.txt` from the extracted tree. The list is
generated from your ROM's ODM/vendor directories. Typical ODM entries are:

```text
odm/etc/selinux/precompiled_sepolicy
odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256
odm/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256
```

Some ROMs place caches in vendor or include extra cache hashes. Remove the
listed compiled cache and associated hashes, not the SELinux directory, source
CIL, mappings, contexts or separate platform hashes. Init then compiles the
complete edited split policy instead of using a stale binary.

## 5. Apply kitchen permissions and labels

`metadata` is **build input**, not a directory to copy onto the phone. Windows
file copying does not assign Android owners, modes or image SELinux xattrs.
Merge the additions into the kitchen's existing metadata, adapting path
prefixes to its format. Preserve unrelated entries.

| File | Owner | Mode | SELinux label |
| --- | --- | --- | --- |
| `/product/bin/rodin_daemon` | 0:0 | 0755 | `u:object_r:rodin_daemon_exec:s0` |
| `/product/bin/rodin_ctl` | 0:0 | 0755 | `u:object_r:system_file:s0` |
| APK and init file | 0:0 | 0644 | `u:object_r:system_file:s0` |
| New directories | 0:0 | 0755 | appropriate existing directory label |

Use `metadata/fs_config.additions` for payload permissions and
`metadata/file_contexts.additions` for payload/state labels. Retain the original
owners, modes and labels of generated canonical policy/context/XML files
(normally 0:0, 0644). Init creates state as 0:0, 0700 and restores its
`rodin_daemon_data_file` label. Do not replace entire metadata with these additions.

## 6. Rebuild and test

Rebuild product, system if its policy changed, and ODM/vendor if caches were
removed. Preserve the ROM's image format, mount layout, symlinks, xattrs,
partition limits and established AVB/vbmeta procedure. No recovery/vendor_boot
replacement or data format is part of this integration. Inspect the rebuilt
daemon's executable mode and custom label.

On an authorized development shell after boot:

```bash
adb shell getenforce
adb shell getprop init.svc.rodin_daemon
adb shell ls -lZ /product/bin/rodin_daemon
adb shell ps -AZ
adb shell dumpsys package io.github.neeschal.rodinessential
adb shell logcat -b all -d > rodin-integration-logcat.txt
```

Expect a running service, `rodin_daemon` process domain, `rodin_app` app domain
and normal app connectivity under enforcing SELinux. Verify supported controls
against hardware readback, then force-close, screen off/on and reboot to check
restoration. Include OEM defaults, master pause/reset and charger reconnect.
Review startup/AVC logs rather than making SELinux permissive.

Actual feature support depends on the target kernel/vendor interfaces. Bypass
requires a compatible kernel. Compilation does not replace boot/feature tests.

## Updates

### v1.18.5 integration changes

Use the matching v1.18.5 APK and both binaries, not an APK-only replacement.
Keep the complete APK: its small Android framework adapter supplies the bypass
tile and predictive Back. No platform signing or privileged app placement is
required for these components.

The new policy includes foreground-app event access for Per-App Controls and
exact Memory DVFS/UFS devfreq labels. Metadata is read-only; frequency request
writes are restricted to the supported `min_freq`/`max_freq` files.
The existing RAM devfreq parent label is preserved, and the policy retains
MediaTek PowerHAL access on new request/UFS labels. If an exact path is already
labeled differently on your target, reconcile it before compiling; do not
replace a whole vendor policy to resolve a duplicate label.

Charging also needs directory traversal through the vendor's battery-manager
parents. This version includes `sysfs_batteryinfo:dir search`, along with supply
directory and file permissions. Missing parent traversal was the cause of the
reported blank battery section and unsupported bypass on an integrated ROM.
If your vendor labels differ, provide the reviewed `--labels` mapping described
above; do not grant generic sysfs write access or disable SELinux.

After rebuilding, check battery percentage, temperature and current as well as
bypass capability, then test Per-App Controls and Memory DVFS/UFS readback.
Check the tile in Quick Settings; long-press must open Charging Control.

### Replacing an existing bake

Keep APK, daemon and policies synchronized. Replace the old managed Rodin
policy/context/seapp/certificate entries once; do not append them twice. The
merger rejects existing entries for review. Use one installation path and a
consistent signing key. Differently signed ROM-native APKs require a ROM update,
not a forced module overwrite. App/service files survive data formatting;
saved selections in `/data` do not.

For a ROM integrated with the previous version of this merger, work on a backup
of the extracted tree. Replace only the block between `BEGIN RODIN ESSENTIAL
POLICY` and `END RODIN ESSENTIAL POLICY`, the Rodin daemon/state file-context
entries, this package's seapp entry and this package's MAC-permissions entry.
Keep other packages under the same signer. Then rerun the new merger and follow
steps 3–6. Do not remove the surrounding ROM policy or unrelated contexts.
Older manually integrated policies without these markers require a reviewed
removal of their Rodin additions; the tool deliberately refuses a blind merge.

## Loader reference

[Android split-policy loading and cache selection](https://android.googlesource.com/platform/system/core/+/android16-release/init/selinux.cpp).
Use the target ROM's loader behavior if it differs from this standard layout.
