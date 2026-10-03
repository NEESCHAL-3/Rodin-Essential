# Unpacked ROM integration

For the prepared stock EEA test kit, follow
[the step-by-step porter guide](STOCK_ROM_PORTER_GUIDE.md). It distinguishes
runtime files from ROM-kitchen metadata and explains why the kit does not
replace `vendor_sepolicy.cil`.

This workflow is for porters editing extracted Rodin ROM images on a PC. It is
separate from AOSP source integration and from the KernelSU/Magisk module.
The resulting ROM uses an init-managed daemon; the user does not grant root to
the APK and does not need a root manager. The daemon itself is a privileged
system component, confined by a dedicated enforcing SELinux domain.

EROFS is read-only by design. Extract, edit and rebuild the affected images
with the ROM kitchen. Do not attempt a writable remount, an MT Manager edit on
the mounted EROFS partition, or a `/data/adb` service as a permanent ROM bake.
The same offline workflow applies to ext4. No data wipe is an installation step.

## 1. Inputs required for a target-specific ZIP

Provide the following from the **same ROM build being repacked**:

- Extracted `system`, `system_ext`, `product`, `vendor` and `odm` SELinux
  directories, including CIL, mappings, version files, contexts, MAC permissions
  and precompiled-cache metadata. Include the boot policy if this ROM does not
  use Android's ordinary split-policy loader.
- The kitchen's file-context and fs-config metadata for each affected image,
  its mount-point convention, and the partition size/group information.
- Target Android version, build fingerprint, and the actual vendor HAL/sysfs
  labels. Source templates assume Xiaomi Rodin labels; ports can rename them.
- One synchronized, signed APK + daemon + public certificate set. Do not mix
  an old daemon with a newer APK, or copy a root-module policy into a ROM.

A ZIP made for one ROM's labels, mappings or certificate is not a universal
Android 12–17 policy. Do not reuse the previous baked-policy binary after a
ROM update. The current source integration is described in
[ROM_INTEGRATION.md](ROM_INTEGRATION.md).

## 2. Permanent file layout

Prefer product unless the target ROM requires another system partition:

```text
product/app/RodinEssential/RodinEssential.apk
product/bin/rodin_daemon
product/etc/init/rodin_daemon.rc
```

Use the current `android/aosp/rodin_daemon.rc` without changing its startup or
state directory. Its executable is `/product/bin/rodin_daemon`. If installing
under system_ext or system instead, change the service executable, restorecon
path and executable file-context rule **together**. Do not install duplicate
service definitions or binaries in multiple partitions.

The kitchen's extraction directory is not necessarily the runtime path. For
example, an extracted `system/system/bin` may become `/system/bin`. Resolve
this using the kitchen's mount point, not by guessing.

Required ownership and modes for new files/directories:

| Runtime path | Owner | Mode | Label |
| --- | --- | --- | --- |
| `/product/app/RodinEssential` | root:root | 0755 | target ROM's normal system-app directory type |
| `/product/app/RodinEssential/RodinEssential.apk` | root:root | 0644 | target ROM's normal system-app APK type |
| `/product/bin/rodin_daemon` | root:root | 0755 | `rodin_daemon_exec` |
| `/product/etc/init/rodin_daemon.rc` | root:root | 0644 | target ROM's normal init configuration file type |
| `/data/system/rodin-essential` | root:root | 0700 | `rodin_daemon_data_file` |

Init creates the data directory after data is mounted. Do not include a data
partition, users' state or a private signing key in the bake ZIP.

For kitchens using Android fs-config text, merge these entries once, with the
kitchen's exact path-prefix convention:

```text
product/app/RodinEssential 0 0 0755
product/app/RodinEssential/RodinEssential.apk 0 0 0644
product/bin/rodin_daemon 0 0 0755
product/etc/init/rodin_daemon.rc 0 0 0644
```

Do not replace the original full fs-config with this four-line fragment.

## 3. Labels, app identity and compiled policy

These runtime file-context additions are required:

```text
/product/bin/rodin_daemon                     u:object_r:rodin_daemon_exec:s0
/data/system/rodin-essential(/.*)?            u:object_r:rodin_daemon_data_file:s0
```

Merge them into the target's product file contexts and the kitchen's labeling
input. Merely writing a contexts text file does not set the daemon executable's
on-disk `security.selinux` xattr: the image builder must apply it. Adding a label
also does not declare its type; the compiled SELinux policy must contain it.

The following parts must be merged as one coherent target-policy change:

1. Dedicated daemon, executable, data and app type declarations, domain
   attributes, init transition and owned-state access.
2. The certificate-bound package entry in the product MAC-permissions XML.
   `@RODIN_ESSENTIAL` is a **source-build placeholder**, not a usable signature
   in an extracted ROM. Replace it with the exact APK signer's DER X.509
   certificate encoded as hexadecimal, not its SHA-256 fingerprint. Preserve
   all existing XML entries. Inspect existing entries for this package/signing
   certificate and reconcile conflicts rather than duplicating them.
3. This exact app assignment in the target product seapp contexts:

   ```text
   user=_app seinfo=rodin_essential name=io.github.neeschal.rodinessential domain=rodin_app type=app_data_file levelFrom=all
   ```

4. Only `rodin_app` can connect to the daemon's production socket; the daemon
   has the MLS attribute needed to accept the app's user categories.
5. Framework Binder requests **and reply pipe/FD access**, hardware/HAL rules,
   charging uevent access and exact sysfs genfs labels.
6. The native touch backend's cross-UID capabilities and narrowly scoped THP
   access. See the explicit platform-policy review in the source-build guide.
   Existing OEM compiled policy may impose different restrictions. Do not
   delete neverallows or disable enforcement to force a pass.

To extract a public certificate from a verified APK using Android build tools:

```bash
apksigner verify --print-certs-pem RodinEssential.apk \
  | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
  > RodinEssential.x509.pem
openssl x509 -in RodinEssential.x509.pem -outform DER \
  | od -An -v -tx1 | tr -d ' \n'
```

This recipe assumes a single signing certificate. Multiple signers or signing
rotation require explicit certificate mapping review. Existing installations
also need a compatible APK signing identity; no policy change bypasses Android's
signature checks.

`.te` files contain source macros; they cannot be pasted into CIL. A new
`rodin_essential.cil` placed beside the policy files is **not automatically
loaded**. The reviewed CIL must be merged into canonical policy files selected
by this ROM's init, normally `product_sepolicy.cil` and `vendor_sepolicy.cil`
with any required platform changes. Avoid duplicate type/genfs declarations.

## 4. Compile before repacking

Compile the complete edited policy with the target-compatible `secilc` and the
same inputs/options as that ROM's init/build. Include the platform CIL, vendor
policy-version mapping and compatibility files, vendor public-versioned CIL,
and every present system_ext/product/odm policy and mapping. The vendor mapping
version comes from `vendor/etc/selinux/plat_sepolicy_vers.txt`; it is not the
Android marketing version.

Compile the unmodified baseline first, then the edited set. Both must succeed
with neverallow checking enabled. A standalone platform probe is insufficient.
Do not flash when the baseline is incomplete, a type is unresolved, the compiler
fails, or an AVC workaround has not been reviewed. Validate the contexts and
seapp assignment against the resulting policy as well.

### Precompiled policy cache

#### Stock Rodin EEA OS3.0.302.0.WOJEUXM

Inspection of this stock `super.img` found exactly these three cache files in
ODM. After the replacement policy has been validated, remove these files from
the **extracted ROM tree before copying the prepared integration and rebuilding
the images**:

```text
odm/etc/selinux/precompiled_sepolicy
odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256
odm/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256
```

These are runtime-relative paths; use the kitchen's extracted ODM directory.
Do not remove `odm_sepolicy.cil`, the context files or the `selinux` directory.
Do not delete the separate system/system_ext policy hash files in their own
partitions.
Other ROM versions may have a vendor cache or an additional product companion;
inspect their actual cache set instead of assuming the same three files.

Android init may load `odm/etc/selinux/precompiled_sepolicy` before the vendor
copy when its companion hashes match the system/system_ext/product hash files.
Editing CIL without invalidating this cache can leave the old policy active.

After the **complete edited CIL set has compiled successfully**, choose one:

- Rebuild the precompiled policy and companion hashes using the target ROM's
  build procedure; or
- Remove the stale `precompiled_sepolicy` binary and its
  `precompiled_sepolicy.*.sha256` companions from the **extracted** odm/vendor
  directories wherever present, so init compiles the validated split policy.

Do not delete `odm/etc/selinux` itself, the canonical CIL, mapping files, policy
version files or context databases. Do not remove unrelated policy caches.
On-device compilation requires the target init loader, complete split inputs
and `/system/bin/secilc`; confirm them before using the second option.

## 5. Rebuild EROFS and package

Use the ROM kitchen's EROFS builder with the original mount points, compression,
ownership, modes, symlinks, SELinux xattrs, partition budgets and fs-config.
Inspect the rebuilt image to confirm the APK and executable have the labels
and permissions above. Do not run a bare `mkfs.erofs` over a Windows folder and
assume Android metadata has survived.

Rebuild each affected partition, respecting dynamic-super group sizes. Handle
AVB/vbmeta and signing using the port's established procedure. This guide does
not authorize disabling verification, changing fstab, replacing recovery,
flashing vendor_boot or formatting user data.

A target-ready porter ZIP should contain the synchronized payload, only the
reviewed changed policy/context/XML files, fs-config additions, SHA-256 hashes,
and an exact replacement/merge manifest listing the target ROM fingerprint.
It must state whether it is a copy-into-extracted-tree package or a flashable
installer. Never describe a templates-only archive as ready to flash.

## 6. Enforcing validation after boot

On a development build with an authorized root shell, collect:

```bash
adb shell getenforce
adb shell getprop init.svc.rodin_daemon
adb shell ls -lZ /product/bin/rodin_daemon
adb shell ps -AZ | grep -E 'rodin_daemon|rodinessential'
adb shell dumpsys package io.github.neeschal.rodinessential
adb shell logcat -b all -d > rodin-bake-logcat.txt
```

Expect enforcing SELinux, a running init service, `rodin_daemon_exec` on the
binary, `rodin_daemon` on its process, and `rodin_app` on the APK process.
Do not toggle a permissive development ROM to enforcing without its owner's
approval and a complete ROM policy test. A permissive-only boot does not verify
the integration.

Test hardware readback for every supported domain, reset/master disable, app
force-stop, screen off/on, cable reconnect and reboot restoration. Check bypass
with the actual supported kernel and real charger. Unsupported nodes must stay
unsupported. Daemon online status alone does not prove every feature works.

No boot-time shell command should be needed from the user. If manually launching
the daemon makes it online but the baked service does not, inspect init import,
executable path/mode/label, domain transition and startup denials first.

## References

- [Android init split-policy loader](https://android.googlesource.com/platform/system/core/+/android16-release/init/selinux.cpp)
- [Android SELinux build workflow](https://source.android.com/docs/security/features/selinux/build)
- [EROFS image builder options](https://android.googlesource.com/platform/external/erofs-utils/+/refs/heads/master/man/mkfs.erofs.1)
