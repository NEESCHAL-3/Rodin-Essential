# AOSP integration assets

This directory is a source template. Run `tools/export-aosp-bundle.sh` with a
persistent APK signing keystore to build the ARM64 APK and daemon binaries and
create a self-contained directory for an Android ROM source tree.

The APK uses an ordinary application UID. The `rodin_daemon` init service is the
only root process, and SELinux permits only Rodin Essential's dedicated app
domain to reach its abstract control socket on production builds. The APK is
imported as `presigned` and `preprocessed`; the export includes only its public
certificate, while the private key remains with the ROM maintainer.

See `docs/ROM_INTEGRATION.md` for complete build, signing, policy, validation,
and OTA instructions.

For a checked-out ROM tree, `tools/integrate-aosp-rom.sh <aosp-root>` builds and
stages the bundle under `vendor/rodin-essential`. It prints the two makefile
include lines required by the device tree and does not modify existing product
files automatically. Both helpers require the `RODIN_KEYSTORE`,
`RODIN_KEY_ALIAS`, `RODIN_KEYSTORE_PASS`, and `RODIN_KEY_PASS` environment used
for that ROM's future updates.
