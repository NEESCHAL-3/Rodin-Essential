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

The preserved native touch backend requires a reviewed platform capability
exception. Product/vendor policy alone is insufficient on stock AOSP. Preview
`tools/prepare-aosp-touch-policy.py <aosp-root>` in the original project before
building, and follow the full policy validation steps in the guide.
For offline EROFS/ext4 image porting, see `docs/UNPACKED_ROM_INTEGRATION.md`;
these source `.te` files cannot simply be pasted into a compiled CIL file.

For a checked-out ROM tree,
`tools/integrate-aosp-rom.sh <aosp-root> <product-makefile> <boardconfig>` builds,
stages, and idempotently wires the bundle under `vendor/rodin-essential`.
Passing only `<aosp-root>` performs stage-only integration and prints the two
required lines. Both helpers require the `RODIN_KEYSTORE`,
`RODIN_KEY_ALIAS`, `RODIN_KEYSTORE_PASS`, and `RODIN_KEY_PASS` environment used
for that ROM's future updates.
