# Changelog

All notable changes are documented here.

## 1.18.0

### Added

- CPU Core & Frequency hub with independent frequency control for the efficiency,
  performance, and prime policies.
- Dynamic minimum/maximum ranges and exact `min = max` locks at any frequency
  exposed by the active kernel OPP table.
- Separate saved-target and live-effective readback, per-policy drift status,
  verified writes, and an OEM range reset.
- ROM-native logical-density detection and automatically scaled resolution
  presets instead of a fixed 520 DPI baseline.
- Live/selected refresh-rate telemetry and persisted custom resolution state.

### Changed

- CPU frequency requests are validated against the live driver table instead of
  accepting arbitrary values that the kernel may silently round.
- Frequency targets remain fully independent from CPU governors and GPU modes.
- CPU topology labels now identify the Dimensity 8400's three all-Cortex-A725
  groups instead of the previous generic A520/A720/X4 labels.
- Native host/daemon protocol updated to 13.3 for CPU, display, and touch-path
  telemetry.

### Fixed

- CPU range application now selects Rodin's OEM `thermal-nolimits` policy before
  updating the per-policy Xiaomi thermal ceiling, MediaTek PowerHAL request, and
  cpufreq limits. Exact locks remain at the full 2100/3000/3250 MHz policy
  maxima without changing a governor, and requests fail instead of being saved
  when live verification does not match.
- The previous Xiaomi thermal configuration is saved before the first custom
  CPU range and restored when the last range is reset. `mi_thermald`, AOSP
  `thermald`, and the MediaTek thermal HAL remain running throughout; the boot
  restore and drift guard also verify the live OEM configuration.
- Xiaomi's fresh-boot `sconfig=-1` sentinel is treated as the normal thermal
  configuration, allowing persisted exact CPU locks to restore before any
  explicit vendor mode has been published.
- Frequency cards show the live governor selected elsewhere in the app, provide
  clearer apply/reset guidance, and emit discrete haptic ticks while sliding.
- KernelSU Next and Magisk startup now waits for Android boot completion, then
  repeats the complete persisted-state transaction across the vendor settling
  window. Saved controls remain daemon-owned when the app is force-stopped.
- Touch persistence verifies the active THP timing instead of trusting cached
  state, so late vendor defaults are detected and corrected automatically.
- The 1000 Hz output scheduler now discovers the actual multitouch event among
  every TouchFeature service descriptor and can attach directly to the panel
  event when FocalTech firmware does not retain a compatible service handle.
- Resolution telemetry refreshes after framework startup, distinguishes live
  adaptive refresh from the ROM-selected rate, and no longer reports a false
  hardcoded 60/120 Hz value.
- Cold launches now present a plain application surface instead of exposing an
  oversized launcher-icon transition, while appearance loading and daemon
  startup no longer block the first application frame.
- Extracted Flutter assets and ICU data now use a deterministic content stamp.
  Unchanged runtime files are reused on later cold starts, while APK updates or
  incomplete cache files force a verified refresh before Flutter starts.

## 1.17.1

### Fixed

- GPU performance modes no longer change CPU governors or CPU frequency
  ranges. Existing CPU settings remain independent when switching GPU modes.
- Legacy CPU values written by earlier GPU profiles are migrated once without
  overwriting separately customized CPU settings.
- Vendor CPU and platform thermal services remain running in every GPU mode;
  Gaming Dynamic and Extreme Beast retain ownership only of the Mali cooling
  constraint required by their GPU policy.
- GPU profile transitions are serialized with the maintenance and dynamic
  guards, preventing the previous mode from reasserting stale values during a
  rapid mode switch.

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
