# Changelog

All notable changes are documented here.

## 1.18.3

### Fixed

- Restored the complete v1.18.0 Touch Response pipeline: native 240/480 Hz
  timing for the 250/500 profiles and the verified one-millisecond Android
  output scheduler for the 1000 profile.
- Preserved the authenticated reverse and privileged-loopback transports,
  bounded framework startup, transactional persistence, and daemon-first boot
  ordering that prevent a healthy KernelSU Next or Magisk backend from
  appearing Offline.
- ROM-native 1000 Hz output now opens the dedicated Rodin input device directly
  and no longer requests `SYS_PTRACE`, `DAC_OVERRIDE`, or `DAC_READ_SEARCH`.
  This removes the Android 17 platform-neverallow conflicts without granting
  the application root or privileged Android identity.
- AOSP policy validation now distinguishes pre-existing OEM platform-policy
  diagnostics from violations introduced by the Rodin integration while still
  rejecting any Rodin neverallow failure.
- Application, Rust workspace, KernelSU/Magisk module, manifest, interface, and
  release metadata are synchronized at version 1.18.3 / code 11803.
- The KernelSU/Magisk installer now supports signature-compatible ROM-native
  installations as a reversible update layer. It preserves native state, stops
  the init-owned daemon before module takeover, and restores the ROM APK and
  native service when the module is removed. Cross-signature updates still fail
  safely without deleting application data.

## 1.18.2

### Fixed

- KernelSU Next and Magisk communication no longer depends on an
  `untrusted_app` process connecting into a root-manager SELinux domain. The
  daemon now initiates an authenticated reverse socket to the normal APK, and
  both sides verify the peer UID with `SO_PEERCRED`.
- Module Action distinguishes root-only daemon health from a connection that
  was successfully completed by the Android app.
- Root modules now provide an authenticated privileged-loopback transport for
  ROMs whose SELinux policy blocks Unix `connectto` in either direction. The
  app proves the privileged-port boundary from its own sandbox, and the daemon
  resolves the accepted client's exact package UID from `/proc/net/tcp` before
  serving hardware commands. Cached transports and a temporarily occupied
  listener port recover automatically without relaunching the app or rebooting.
- Root-module installation no longer modifies live SELinux policy or depends on
  root-manager domain names. The script-only package uses no system overlay and
  therefore requires no KernelSU metamodule.
- Root-module updates verify the APK version and official signing certificate.
  A differently signed installed copy is reported clearly and is never removed
  automatically.
- Persisted state is committed transactionally with file and directory sync, so
  an applied command cannot be reported as durable when the state write failed.
- The native daemon binds its socket and enters the accept loop before any
  framework telemetry or restore command can wait on `system_server`. Framework
  command execution is bounded, and SELinux permits only the required reply-pipe
  direction, preventing a healthy native service from appearing Offline.
- Display, GPU, CPU, UFS, charging, and ZRAM commands now reject failed or
  mismatched live readback instead of saving a false success. Touch commands
  require an accepted vendor transaction before persistence is committed.
- TouchFeature setter replies now parse both the AIDL status header and vendor
  result instead of mistaking a delivered Binder transaction for an accepted
  panel command.
- Touch Response retains the proven v1.18.0 250, 500, and 1000 profiles. Native
  modes use the 240/480 Hz timing blocks, while 1000 keeps the 480 Hz source and
  restores the verified one-millisecond Android output scheduler.
- The unused per-application profile subsystem and its package-query surface
  have been removed from the daemon, host, manifest, and interface.
- AOSP integration now preserves an explicit APK signing identity, maps that
  certificate and package to the dedicated `rodin_app` domain, labels only the
  required exact generic Mali and Goodix sysfs paths, and keeps the v1.18.0
  touch permissions isolated to the daemon policy for device-tree review.
- ROM-native policy again includes the narrowly scoped touch-HAL process and
  input access required by the v1.18.0 1000 Hz output path.
- Application, module, daemon protocol, documentation, and release metadata
  are synchronized under a new version so different payloads are no longer
  distributed under the same release identity.

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

- KernelSU Next and Magisk installations now generate an app-to-daemon socket
  rule for the root manager's live SELinux domain (`su`, `ksu`, or `magisk`).
  This prevents a healthy daemon from appearing Offline on ROMs that omit the
  corresponding `connectto` allowance.
- Root-module startup now reapplies the detected socket rule to the live policy
  after boot through KernelSU's `ksud` or Magisk's `magiskpolicy`. This covers
  manager builds that skip or race the early `sepolicy.rule` loader, and Module
  Action reports the result and patch engine used.
- The root-module daemon validates every socket peer with `SO_PEERCRED` and
  accepts hardware commands only from UID 0 or the exact Android UID assigned
  to the bundled Rodin Essential package.
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
- Native 250 mode now applies Rodin's dedicated TouchFeature sensitivity latch
  instead of sharing the 500-mode calibration that could silently fall back to
  roughly 135 Hz while the HAL still reported 240 Hz.
- The 1000 Hz output scheduler now discovers the actual multitouch event among
  every TouchFeature service descriptor and can attach directly to the panel
  event when FocalTech firmware does not retain a compatible service handle.
- Repeated boot and watchdog restores no longer reset an already-correct ZRAM
  device; compression, size, and swappiness changes are now idempotent.
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
- Persistent CPU, GPU, touch, display, charging, ZRAM, and UFS state.
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
