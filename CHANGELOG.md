# Changelog

All notable changes are documented here.

## 1.17.0

### Added

- Complete Rust privileged daemon and command-line health client.
- Persistent CPU, GPU, touch, display, charging, ZRAM, UFS, and per-app state.
- Extreme Beast, Gaming Dynamic, Stock Balanced, and Battery Saver transactions.
- Live Mali frequency/load readback, GED state, governor, and power-policy UI.
- Native 240/480 Hz touch timing and 1 ms Android output mode.
- Goodix and FocalTech detection through the Rodin touch vendor stack.
- UFS scheduler application and verification across detected logical units.
- Motion-feel control and refined application transitions.
- Combined KernelSU Next and Magisk module with bundled unprivileged APK.
- AOSP `/product` integration bundle, init service, and split SELinux policy.

### Changed

- The APK remains an ordinary app UID; all privileged operations are isolated in
  the daemon.
- GED is profile-owned: enabled only for Gaming Dynamic and Extreme Beast.
- Profile, touch, storage, CPU, and memory settings are reapplied after boot and
  guarded against vendor drift.
- Persisted GPU profiles recover from late MediaTek power-service overrides;
  fixed-frequency restoration verifies the live target OPP before locking DVFS.
- Build output is zero-DEX, release-mode, ARM64-only, and verified for 16 KB APK
  and ELF alignment.

### Removed

- Direct live-partition mutation scripts.
- Empty privileged-permission allowlist packaging.
- Obsolete migration audits, phase markers, and proof-only build scripts.
