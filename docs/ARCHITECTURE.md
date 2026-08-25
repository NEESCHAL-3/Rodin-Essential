# Architecture

Rodin Essential separates the visual application from all privileged hardware
operations. The separation is identical in AOSP and root-module deployments; only
the daemon launcher and state directory change.

## Runtime components

```text
Flutter AOT interface
        │ Dart FFI
        ▼
Rust NativeActivity host
        │ abstract Unix socket, protocol 13.1
        ▼
Rust rodin_daemon
        ├── sysfs / procfs / cgroup / block controls
        ├── Xiaomi touch and display AIDL services
        ├── MediaTek GED and Mali devfreq
        └── persistent state and drift reassertion
```

### Android package

`android/package/AndroidManifest.xml` declares `android.app.NativeActivity` and
`android:hasCode="false"`. The APK contains no `classes.dex`; its executable
payload is ARM64 native code:

- `librodin_essential_host.so`
- `libflutter_engine.so`
- `libapp.so`

The APK uses a regular application UID. It has no shared UID, root launcher,
privileged permission allowlist, or direct sysfs write path.

### Native host

`runtime/host-rust` owns:

- NativeActivity lifecycle, Android window, input queue, and back dispatch.
- EGL/OpenGL/Skia Flutter embedder lifecycle and choreographer frame pacing.
- JNI bridges for permissions, haptics, app catalog, theme, and URL launch.
- Nonblocking Dart FFI calls and cached daemon telemetry.
- Command serialization over the daemon socket.

Hardware I/O is never performed on Flutter's UI thread.

### Flutter interface

`ui/flutter` owns presentation and interaction state. It reads immutable cached
snapshots and submits commands to the native backend. Temporary optimistic state
is replaced by daemon readback as soon as the hardware transaction completes.

### Privileged daemon

`runtime/daemon-rust` owns all root-required operations. It validates commands,
writes hardware nodes, calls vendor AIDL services, verifies readback where the
driver exposes it, persists accepted settings, and reasserts settings when a
vendor component rewrites them.

The daemon listens on a Linux abstract Unix socket. In an AOSP build, SELinux
allows only the dedicated `rodin_app` domain to connect in production. The
`rodin_ctl` client is allowed only on `userdebug` and `eng` builds.

## Persistence

The daemon selects its state directory from `RODIN_STATE_DIR`:

- AOSP init service: `/data/system/rodin-essential`
- KernelSU Next or Magisk service: `/data/adb/rodin-essential`
- Development fallback: `/data/adb/rodin-essential`

State is written atomically through `state.conf.tmp` and rename. The daemon
loads it once at startup, reapplies it after Android boot completes, and keeps
running independently of the application process. Removing the app from recents
or force-stopping it therefore does not stop the active backend configuration.

Persisted domains include performance profile, GPU bounds/governor/GED/power
policy, CPU governors and ranges, online-core mask, UFS scheduler, touch profile,
DT2W, display settings, charging, ZRAM, and per-app assignments.

## Touch paths

Rodin Essential first uses Xiaomi's vendor `ITouchFeature` AIDL service, which
abstracts the supported Goodix and FocalTech panels. A Goodix sysfs path is used
only as a fallback on ports that omit the AIDL service.

- 250 mode requests the native 240 Hz timing block.
- 500 mode requests the native 480 Hz timing block.
- 1000 mode keeps the physical source at 480 Hz and emits a verified 1 ms
  Android event stream through a duplicated vendor event descriptor.

The 1000 path needs `SYS_PTRACE`, input-device access, `pidfd_getfd`, and narrowly
scoped SELinux access to the Rodin touch HAL domain. These permissions belong to
the daemon only.

## Performance ownership

GPU profile changes are isolated transactions: GPU bounds, governor, GED state,
power policy, and the Mali cooling constraint are applied together. CPU
governors, CPU frequency ranges, and CPU core state are controlled independently.
A background guard compares persisted intent with live readback and reapplies
only drifted values owned by each subsystem.

Vendor CPU and platform thermal services remain running in every GPU mode.
Gaming Dynamic and Extreme Beast retain ownership of the Mali cooling constraint
required by their requested GPU policy without stopping those global services.

## Build invariants

Every release must satisfy:

1. No DEX entries in the APK.
2. `android:hasCode="false"` in the manifest.
3. ARM64-only native payload.
4. 16 KB APK and ELF alignment.
5. Flutter framework and engine revision compatibility.
6. No UI-thread filesystem, Binder, socket, or daemon work.
7. No root or privileged Android identity for the APK.
8. A dedicated SELinux daemon domain for AOSP integration.
