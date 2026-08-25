# Rodin Essential

Rodin Essential is a native hardware-control application for Xiaomi Rodin
(POCO X7 Pro / Redmi Turbo 4) and its MediaTek Dimensity 8400-Ultra platform.
It combines a zero-DEX Android `NativeActivity`, a Flutter AOT interface, a
Rust host runtime, and a separately privileged Rust daemon.

The APK never runs as root, does not use the system UID, and does not request
privileged Android permissions. Kernel and vendor controls are owned by the
daemon and reached through a private abstract Unix socket.

## Supported target

- Device codename: `rodin`
- SoC: MediaTek MT6899 / Dimensity 8400-Ultra
- CPU: 8× Cortex-A725 (4+3+1 policies), up to 3.25 GHz
- GPU: Mali-G720, 7 cores, up to 1300 MHz
- ABI: ARM64
- Android: API 31 or newer
- Kernel userspace: 16 KB page-compatible native binaries
- Vendor dependencies: Rodin touch and display AIDL services plus MediaTek GED

This is device-specific software. Other devices are rejected by the root-module
installer and are not supported by the included AOSP policy.

## Main features

- Four persistent CPU/GPU performance profiles with live hardware readback.
- Mali devfreq range, governor, GED boost, power-policy, and OPP controls.
- CPU core mask, independent cluster governors, and validated per-cluster
  minimum/maximum or sustained exact-lock controls sourced from the live kernel
  OPP table.
- UFS scheduler selection across every detected UFS logical unit.
- Touch profiles for 240 Hz native timing, 480 Hz native timing, and a 1 ms
  Android output stream generated from the native 480 Hz source.
- Xiaomi touch/display AIDL integration, DT2W, color modes, expert calibration,
  sunlight mode, HDR/video controls, resolution, and density controls.
- ZRAM size, algorithm, swappiness, compaction, charging, and power telemetry.
- Daemon-owned persistence and background reassertion after boot, screen wake,
  vendor resets, app force-close, or removal from recents.
- Configurable in-app motion timing with native 120 Hz frame pacing.

## Performance profiles

| Profile | GPU range and governor | GED / power policy | CPU behavior |
| --- | --- | --- | --- |
| Stock Balanced | Vendor-managed 260–1300 MHz, `dummy` | GED off, `coarse_demand` | Unchanged; controlled separately |
| Gaming Dynamic | 260–1300 MHz, `simple_ondemand` | GED on, `always_on` | Unchanged; controlled separately |
| Battery Saver | 260–598 MHz, `powersave` | GED off, `coarse_demand` | Unchanged; controlled separately |
| Extreme Beast | Fixed 1300 MHz, `performance`, DVFS off | GED on, `always_on` | Unchanged; controlled separately |

GPU profiles never modify CPU governors, CPU clock ranges, or CPU core state.
Vendor CPU and platform thermal services remain running in every mode. Gaming
Dynamic and Extreme Beast override the Mali cooling constraint and can still
cause extreme heat, rapid battery drain, instability, or an emergency hardware
shutdown.

Custom CPU ranges remain separate from GPU profiles and governors. While at
least one custom CPU range is active, the daemon selects Rodin's OEM
`thermal-nolimits` configuration so Xiaomi's userspace policy cannot replace an
exact lock with a lower ceiling. It keeps the thermal services alive, remembers
the configuration that was active beforehand, and restores it when the final
custom CPU range is reset.

## Integration choices

| Method | APK privilege | Backend | Persistence |
| --- | --- | --- | --- |
| AOSP ROM integration | Normal app UID | Root init daemon | `/data/system/rodin-essential/state.conf` |
| KernelSU Next or Magisk | Normal app UID | Root module daemon | `/data/adb/rodin-essential/state.conf` |
| Standalone APK | Normal app UID | None | Hardware controls unavailable |

For a ROM release, use the AOSP integration. It installs the APK and daemon in
`/product`, creates a dedicated app SELinux domain, restricts the control socket
to that domain, starts the daemon after boot, and restores saved state without a
root manager.

See [AOSP ROM integration](docs/ROM_INTEGRATION.md) for the complete maintainer
workflow and [Architecture](docs/ARCHITECTURE.md) for runtime details.

## Build from source

Required tools:

- Linux host
- Flutter SDK and revision-matched Flutter engine checkout
- Rust toolchain with `aarch64-linux-android`
- Android SDK, platform 36, build-tools, and NDK r27 or newer
- JDK 17 or newer, `ninja`, `zip`, `unzip`, and standard ELF tools

Build the pinned engine once:

```bash
rustup target add aarch64-linux-android
./tools/build-flutter-engine.sh
```

Build without touching a connected device:

```bash
RODIN_BUILD_ONLY=1 ./build-and-install.sh
```

Output is written under `out/release/<timestamp>/`. The build verifies
Flutter analysis, ARM64 AOT output, zero DEX, APK signing, 16 KB ZIP alignment,
16 KB ELF segment alignment, and a content stamp covering the packaged Flutter
assets and ICU data. If no signing key is supplied, a development key is
created inside that ignored output directory.

For release signing, set:

```bash
RODIN_KEYSTORE=/absolute/path/release.jks \
RODIN_KEY_ALIAS=release \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
RODIN_BUILD_ONLY=1 ./build-and-install.sh
```

## Export for an AOSP tree

```bash
./tools/export-aosp-bundle.sh
```

The generated `dist/aosp/RodinEssential-<timestamp>/` directory contains the
APK, daemon, control client, `Android.bp`, init service, split product/vendor
SELinux policy, and checksums.

To build and stage the integration directly in an existing ROM source tree:

```bash
./tools/integrate-aosp-rom.sh /absolute/path/to/aosp
```

The helper creates `vendor/rodin-essential` and prints the product and
BoardConfig include lines. It does not overwrite an existing integration or
edit device-tree files automatically.

## KernelSU Next and Magisk module

For an existing rooted ROM, build the combined application and daemon module:

```bash
RODIN_KEYSTORE=/absolute/path/release.jks \
RODIN_KEY_ALIAS=release \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/build-kernelsu-next-module.sh
```

Install the ZIP from KernelSU Next Manager or the Magisk app while Android is
running. The installer registers the bundled APK as an ordinary user app and
the module runs only the separate hardware daemon as root. The installer emits
the socket rule for the root manager's active SELinux domain, and the daemon
accepts commands only from UID 0 or the UID assigned to the bundled package. It
also verifies and reapplies that narrow rule to the live policy after Android
finishes booting, covering manager builds that skip or race early module-policy
loading. The Module Action screen reports the detected daemon domain and live
patch method for diagnosis. It
deliberately uses `skip_mount`, so KernelSU does not require a system-overlay
metamodule. Recovery installation is not supported.

Keep the signing key for every future module update. Android rejects an APK
update signed by a different certificate.

## Repository layout

```text
android/
  aosp/                 AOSP prebuilt, init, and SELinux integration template
  kernelsu-next/        KernelSU Next and Magisk module source
  package/              Zero-DEX manifest and Android resources
docs/                   Architecture, build, and ROM maintainer documentation
runtime/
  daemon-rust/          Privileged hardware backend and control client
  flutter-engine/       Embedder header and ignored pinned engine prebuilts
  host-rust/            NativeActivity, Flutter embedder, JNI, and IPC bridge
tools/                  Engine, AOSP export, and module build scripts
ui/flutter/             Flutter AOT interface
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Building and verification](docs/BUILDING.md)
- [AOSP ROM integration](docs/ROM_INTEGRATION.md)
- [Flutter runtime pin](docs/FLUTTER_RUNTIME.md)
- [Commit convention](docs/COMMITS.md)

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
