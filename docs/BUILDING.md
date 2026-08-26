# Building and verification

## Host requirements

- Linux x86_64
- Flutter SDK on `PATH`
- A matching Flutter engine checkout
- Rust and the `aarch64-linux-android` target
- Android SDK with platform 36, current build-tools, and an NDK
- JDK 17 or newer
- `ninja`, `readelf`, `file`, `zip`, and `unzip`

Set `ANDROID_SDK_ROOT` when the SDK is not at `$HOME/Android/Sdk`.

## Prepare Rust and Flutter

```bash
rustup target add aarch64-linux-android
flutter pub get --directory ui/flutter
```

The custom embedder must use a Flutter engine built from the framework's pinned
engine revision. If the engine checkout is not under the Flutter SDK, point the
engine build script at it:

```bash
RODIN_FLUTTER_ENGINE_SRC=/absolute/path/to/engine/src \
  ./tools/build-flutter-engine.sh
```

The script installs ignored local artifacts at:

```text
runtime/flutter-engine/prebuilt/android-arm64/libflutter_engine.so
runtime/flutter-engine/prebuilt/android-arm64/icudtl.dat
```

## Build the application and daemon

```bash
RODIN_BUILD_ONLY=1 ./build-and-install.sh
```

The output directory contains:

```text
Rodin-Essential.apk
host-cargo/aarch64-linux-android/release/rodin_daemon
host-cargo/aarch64-linux-android/release/rodin_ctl
apk-files.txt
```

Without `RODIN_BUILD_ONLY=1`, the script installs the APK on the connected
device and updates the development root-module backend. ROM release automation
should always use build-only mode or `tools/export-aosp-bundle.sh`.

## Signing

An omitted `RODIN_KEYSTORE` creates a stable local development key at
`out/signing/rodin-essential-development.jks`. The ignored key is generated
once and reused so repeated local builds remain update-compatible. Nothing
under `android/package` contains private signing material.

Supply release credentials through environment variables:

```bash
RODIN_KEYSTORE=/absolute/path/release.jks \
RODIN_KEY_ALIAS=release \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
RODIN_BUILD_ONLY=1 ./build-and-install.sh
```

AOSP exports require an explicit persistent key. The imported APK remains
presigned with that certificate, and the exported public PEM binds its exact
package name to the dedicated `rodin_app` domain. The private key remains with
the ROM maintainer.

## Local checks

Run before committing:

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test -p rodin-essential-daemon
dart format --output=none --set-exit-if-changed ui/flutter/lib
(cd ui/flutter && flutter analyze)
bash -n build-and-install.sh
bash -n tools/build-flutter-engine.sh
bash -n tools/build-kernelsu-next-module.sh
bash -n tools/export-aosp-bundle.sh
bash -n tools/integrate-aosp-rom.sh
./tools/test-kernelsu-watchdog-lock.sh
./tools/test-root-module-contract.sh
./tools/test-aosp-integration.sh
git diff --check
```

The NativeActivity host intentionally links Android system libraries and is not
linked as a Linux test executable. `build-and-install.sh` cross-compiles it with
the Android NDK and verifies the resulting ARM64 shared object.

Build verification additionally checks:

- `classes*.dex` is absent.
- APK signature verification succeeds.
- ZIP entries satisfy 16 KB page alignment.
- Every native ELF LOAD segment has at least 16 KB alignment.
- Every Dart FFI lookup resolves to an exported ARM64 host symbol.
- Daemon and control binaries target ARM64 Android.
- The packaged runtime stamp covers every Flutter asset and `icudtl.dat`, so
  application updates cannot reuse an incompatible extraction cache.

## AOSP export

```bash
RODIN_KEYSTORE=/absolute/path/rom-app.jks \
RODIN_KEY_ALIAS=rodin-essential \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/export-aosp-bundle.sh
```

The export fails rather than replacing an existing destination. Pass a new
absolute or relative destination as its first argument when required.

To build and stage the integration directly in an AOSP checkout:

```bash
RODIN_KEYSTORE=/absolute/path/rom-app.jks \
RODIN_KEY_ALIAS=rodin-essential \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/integrate-aosp-rom.sh /absolute/path/to/aosp
```

The helper does not modify existing device or product makefiles. It prints the
two required include lines after staging succeeds.

## KernelSU Next and Magisk module

```bash
RODIN_KEYSTORE=/absolute/path/release.jks \
RODIN_KEY_ALIAS=release \
RODIN_KEYSTORE_PASS='store-password' \
RODIN_KEY_PASS='key-password' \
  ./tools/build-kernelsu-next-module.sh
```

This builds the application and daemon together, then creates one ZIP for
KernelSU Next Manager and the Magisk app. The build validates module metadata,
shell syntax, the authenticated reverse-IPC contract, the official APK signing
certificate, package/version/zero-DEX/16 KB alignment, ARM64 daemon binaries,
Android dynamic linker, archive contents, and checksum. It also rejects any
SELinux patch payload or system overlay in the resulting ZIP.

The module installs the bundled APK through Android's package manager as a
normal user application. It does not mount an APK into a system partition, so
KernelSU does not need a metamodule. The daemon exposes an outward connection
for policies that block the authenticated direct path; the module neither
patches live SELinux policy nor converts the APK into a privileged application.
A policy that already permits the direct connection may use it. Installation
from recovery is not supported.

The builder requires a persistent `RODIN_KEYSTORE`; it never creates a
disposable module signing identity. Reuse the same key for all published module
versions so Android can update the bundled application without removing user
data.
