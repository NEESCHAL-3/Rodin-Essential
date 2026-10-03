# Rodin Essential: baking into extracted ROM images

## What this package is

This is a **copy-into-extracted-images kit**, not a recovery-flash ZIP and not
the KernelSU/Magisk module. Its prepared replacement policies target exactly:

```text
Xiaomi Rodin EEA
HyperOS OS3.0.302.0.WOJEUXM
Android 16 / SDK 36
```

The APK, daemon and module are synchronized at v1.18.4, version code 11804,
protocol 13.6. The module and ROM kit use the same v1.18.4 signing certificate.
The signing identity changed in this release; an older differently signed
ROM-native APK cannot accept an in-place update from this module.

After a correct bake, Android init starts the daemon. The user opens the app
normally: no `su` command, root prompt, Magisk, KernelSU or `/data/adb` service
is required. The daemon runs with system privileges; the APK does not run as
root. Saved controls belong to the daemon, not the app's activity process.

**Important for ports:** sharing the stock vendor image does not mean sharing
the stock system policy. Do not replace a ColorOS, AOSP or different HyperOS
port's `plat_sepolicy.cil` with the full stock file in this kit. That port needs
its own policy merge and full split-policy compilation. This guide explains
the installation method; this particular policy payload is not universal.

## Before you start

Use the ROM kitchen that you normally use to extract and rebuild this ROM's
images. Keep its original file-context and filesystem-permission metadata.
EROFS cannot be edited on a writable live mount: work on extracted directories
on the PC and rebuild the images afterward.

The kit has four kinds of contents:

| Kit item | What the porter does with it |
| --- | --- |
| `copy-to-extracted-rom/` | Copy its contents into the extracted partition directories |
| `REMOVE-BEFORE-COPY.txt` | Delete only the listed stale cache files from extracted ODM |
| `metadata/fs_config.additions` | Merge into the kitchen's existing permission metadata |
| `metadata/file_contexts.additions` | Merge into the kitchen's existing image-labeling metadata |

**Do not copy the `metadata` directory to the phone's filesystem.** These files
are instructions for rebuilding the Android images correctly. Windows file
permissions are not Android image permissions.

## Step 1: extract the matching ROM

Extract `super.img`, then extract the affected partition images using the
kitchen. The relevant working directories are:

```text
system
product
odm
```

Keep vendor and system_ext available for complete SELinux policy validation;
the current stock kit does not replace their files.

Check the system-directory layout before copying. In this stock system-as-root
image, the runtime `/system/etc` is extracted as `system/system/etc`. Some
kitchens flatten this to `system/etc`. Use whichever directory already contains
your ROM's `plat_sepolicy.cil`; do not create a second nested `system` directory.

## Step 2: remove the three stale ODM cache files

From the extracted ODM directory, remove exactly:

```text
odm/etc/selinux/precompiled_sepolicy
odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256
odm/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256
```

Keep `odm_sepolicy.cil`, every context/mapping file and the `selinux` directory.
Keep the separate policy hashes in system and system_ext. The three removed
files are cached compiled policy, not the full policy source. Removing them
ensures init uses the edited split policy rather than the old cached policy.

Only do this for the validated target package before rebuilding. Do not remove
these files from a live device or remove policy caches while the replacement
policy is incomplete.

## Step 3: copy the prepared files

Copy the **contents** of `copy-to-extracted-rom/product/` into your extracted
`product/` directory. Merge directories and replace the supplied matching files;
do not replace the entire product directory.

The following are runtime destinations; the extracted paths use your kitchen's
layout:

| Runtime destination | Purpose |
| --- | --- |
| `/product/app/RodinEssential/RodinEssential.apk` | App |
| `/product/bin/rodin_daemon` | Hardware-control service |
| `/product/bin/rodin_ctl` | Local diagnostic client; not required for normal app operation |
| `/product/etc/init/rodin_daemon.rc` | Automatic startup and process restart |
| `/product/etc/selinux/product_sepolicy.cil` | Rodin app/daemon types, transitions, socket, framework and hardware rules |
| `/product/etc/selinux/product_file_contexts` | Executable and state-directory labels |
| `/product/etc/selinux/product_seapp_contexts` | Exact package-to-app-domain assignment |
| `/product/etc/selinux/product_mac_permissions.xml` | Actual APK certificate mapped to `rodin_essential` |

Then copy the supplied `plat_sepolicy.cil` to the existing file at runtime:

```text
/system/etc/selinux/plat_sepolicy.cil
```

In this stock kit, that file comes from
`copy-to-extracted-rom/system/system/etc/selinux/plat_sepolicy.cil`. This
replacement preserves the inspected stock platform policy and adds only the
reviewed daemon-specific capability exceptions. It is why matching the exact
stock base matters.

Do not install another Rodin service in system, system_ext or vendor at the
same time. Do not copy root-module `service.sh` or module files into the ROM.

### Where is vendor_sepolicy.cil?

The correct filename is **`vendor_sepolicy.cil`**, not `.cli`.

**For this prepared stock kit, leave the original vendor file untouched.** The
Rodin rules have already been merged into `product_sepolicy.cil`. Android
compiles platform, product, system_ext, vendor, ODM and matching mapping files
together, so these rules can resolve the vendor types in the complete policy.
The complete stock split-policy compile has checked that resolution.

This includes CPU, GPU/GED, charging, supported bypass interfaces, touch, UFS,
ZRAM, display and framework permissions. The source AOSP layout splits some
of those rules into vendor policy; the offline kit puts them in the loaded
product contribution. There is no missing vendor fragment to paste.

Do not add `rodin-native.cil` as an extra file beside the canonical policy and
expect init to load it automatically. Do not append the rules a second time to
vendor policy: duplicate type declarations or genfs labels can break compilation.

## Step 4: apply the rebuilding metadata

Two different things must be correct:

1. **Permissions/ownership:** can init execute the binary?
2. **SELinux labels:** can init enter the daemon domain and can the daemon perform
   its permitted operations while enforcing?

Copying the executable alone does not guarantee either. The new daemon must be:

```text
Owner: root:root (UID 0, GID 0)
Mode: 0755
SELinux label: u:object_r:rodin_daemon_exec:s0
```

The app and configuration/policy files must be root:root, mode 0644; directories
must be root:root, mode 0755. The daemon-created state directory is mode 0700
and labelled `rodin_daemon_data_file`.

Open the kitchen's original product/system filesystem-permission metadata.
Merge the entries in `metadata/fs_config.additions`, adjusting only the path
prefixes to match that kitchen. Replace conflicting entries for these exact
paths; keep all unrelated entries. If the kitchen has a metadata editor instead
of a text file, set the same owner/mode values there.

Open the kitchen's original image-labeling metadata. Merge
`metadata/file_contexts.additions` so the image builder applies the custom label
to `rodin_daemon`. Keep all unrelated labels. Merely copying the target's
`product_file_contexts` text file into product is not proof that the image
builder has applied the executable's on-disk SELinux xattr.

Do not overwrite the original full metadata with the small additions file.
Do not use Windows Explorer's security/permission dialog to set Android modes.
Do not deploy a host-generated `.bin` file-context database from another
architecture; the kit provides text contexts for the target/kitchen.

## Step 5: rebuild the images

Rebuild **system, product and ODM**, because all three were changed. Keep the
ROM's original EROFS settings, ownership, symlinks, labels, mount points and
partition/group size limits. If your kitchen packs a full super image, include
those rebuilt partitions and preserve all unchanged partitions.

Use the port's established AVB/vbmeta and packaging procedure. Do not guess new
partition sizes, replace recovery/vendor_boot, or format data as part of this
integration. Do not include a data image or users' saved settings in the kit.

Before booting, inspect the rebuilt product image and confirm that the binary
has mode 0755 and the `rodin_daemon_exec` label—not generic `system_file`.
Confirm the copied policy, XML and init files are present at the right paths.

## Step 6: boot and verify

The porter tests the rebuilt ROM; end users do not run setup commands. On an
authorized development shell, check:

```bash
adb shell getenforce
adb shell getprop init.svc.rodin_daemon
adb shell ls -lZ /product/bin/rodin_daemon
adb shell ps -AZ
adb shell dumpsys package io.github.neeschal.rodinessential
adb shell logcat -b all -d > rodin-bake-logcat.txt
```

Expect enforcing SELinux, a running init service, `rodin_daemon` on the daemon
process, and `rodin_app` on the app process. A manual `su` launch must not be
needed. The diagnostic control client is not granted a broad production socket
exception; use the app to verify normal control access.

Test each supported feature against actual hardware/vendor readback. Apply a
selection, close/force-stop the app, reboot, and verify it again. Include screen
off/on, charger reconnect, OEM defaults, master disable and full reset.

If the daemon is offline, collect the commands above and the complete logcat;
inspect startup, path, executable mode/label, transition and socket denials. Do
not “fix” offline status by making SELinux permissive or running a root script.

## Compatibility and saved settings

Use these prepared replacement files only with the stock ROM version listed
above. Bypass charging requires a compatible kernel interface; otherwise the
app shows it as unsupported.

The baked app and service remain installed after a data format. Formatting data
clears saved user selections and restores fresh defaults.

## Updating

Replace the app, daemon, init and policy as one reviewed integration set. Keep
the signing certificate consistent. A public APK signed by a different key
cannot update a baked system APK in place. This local ROM kit and its matching
local module share a certificate; the old public-release certificate is
different. Test the native/module takeover and removal flow separately before
distributing that update method.
