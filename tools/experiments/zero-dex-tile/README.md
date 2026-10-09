# Zero-DEX tile lab — native callback experiment

This is a separate local test app (`io.github.neeschal.rodinessential.tilelab`).
It is **not** a bypass charging implementation and is not included in Rodin
Essential's normal build. Its only state is a harmless in-memory test flag.
It does not connect to the daemon, request root, write charger nodes, change
SELinux, patch SystemUI, redefine managed classes, or generate/load DEX.

## Hypothesis

Declare Android's boot-classpath `android.service.quicksettings.TileService`
directly in a zero-DEX APK. Load a native JVMTI agent into **this lab's own
debuggable process**. Place breakpoints on the framework
service's `onClick` and `onStartListening` methods; use the receiver object to
update the test tile through JNI.

Compilation is not proof that callbacks work on a device. Neither an icon in
the tile picker nor a successful service bind is proof of a working toggle.

The initial 0.1 prototype attached from NativeActivity. The 0.2 prototype uses
Android's app-local `wrap.sh` startup mechanism instead. Its native agent waits
for VM initialization before installing the callbacks. The activity remains
an attachment fallback, not a requirement for the successful cold-start test.

## Known boundary

Without the wrapper, cold-starting only the framework service does not execute
NativeActivity's native entry point, and callbacks fail after process death.
The wrapper fixes that bootstrap failure on the tested phone. However, the
wrapper and supported JVMTI attachment require a debuggable app. Wrapping also
starts a fresh runtime rather than using normal zygote preloading, adding
startup work. These are release concerns, not details to hide or work around
with a polling watchdog. The real application's manifest remains non-debuggable.

Android documents these restrictions in
[ART TI](https://source.android.com/docs/core/runtime/art-ti) and
[wrap scripts](https://developer.android.com/ndk/guides/wrap-script). The callback path
is visible in
[TileService.java](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/service/quicksettings/TileService.java).

## Build

Run `build.sh` in the configured Ubuntu/NDK environment with the existing local
development `RODIN_KEYSTORE` and `RODIN_KEY_ALIAS`. It signs a separate APK and
checks that no DEX/JAR/ODEX/VDEX payload is packaged. It does not install it.
The JVMTI ABI header comes from the local JDK; JNI types come from the NDK.

The manifest defaults to `debuggable=false`. Set `RODIN_TILE_LAB_MODE=debug`
(the default build mode) for the working debug experiment, or `release` for
the non-debuggable negative control. The builder uses `aapt2 --debug-mode`
only in debug mode and checks the resulting APK's debuggable flag. Artifacts
are separated under `out/zero-dex-tile-lab/debug/` and `release/`.

## Device test protocol

1. Record the device's original Quick Settings tile list.
2. Install only the selected lab-mode APK from `out/zero-dex-tile-lab/`.
3. For the activity-fallback test, open Rodin Tile Lab; it immediately closes.
   For the wrapper test, do not open the activity at all.
4. Add **Rodin Test Only** to Quick Settings. Do not confuse it with bypass.
5. Click repeatedly and verify `RodinTileLab` logs report `TEST_CLICK` and the
   visible tile state changes. No battery state should change from this test.
6. Close the activity normally and repeat; then kill only the lab process and
   repeat without reopening the activity. Compare warm and cold results.
7. Remove the test tile and uninstall only the lab package when finished.

Do not merge into the real app or advertise cross-ROM compatibility based on
one warm-process test. Never change the real app to debuggable for this feature.

## Device results — 2026-10-07

- Local ARM64 compilation, APK signature, zero-DEX payload and 16 KB ZIP
  alignment checks passed.
- On the connected Rodin/HyperOS Android 16 (API 36) phone with SELinux Enforcing,
  the 0.1 warm-process test produced native click callbacks and visible state
  changes. Repeated agent attachment initially produced duplicate callbacks;
  an idempotency guard fixed that bug. One subsequent tap produced one callback.
- The 0.1 process-death test failed: the framework service restarted but had
  no native callback handler. No hardware writes occurred.
- The 0.2 startup wrapper loaded the native agent without opening the activity.
  Two commanded clicks in PID 26198 produced exactly two callbacks and ON/OFF
  state updates. After killing that process, PID 27421 initialized its own agent
  and handled two clicks. After force-stopping and rebinding, PID 27634 also
  initialized the agent and handled a click without an activity launch.
- APK contents: manifest, compiled vector resource, resource table, one ARM64
  shared library, app-local wrap script, and signatures; no application DEX.
- An install-path bug was fixed: ART splits agent options at '=', also present
  in Android install directories. The wrapper changes into its own directory
  and passes a relative agent-library path instead.
- This proves the test callback path on one ROM, not real bypass integration,
  reboot reliability, release-mode support, or cross-ROM compatibility.

## Release-mode follow-up — 2026-10-07

Both build modes passed signature, zero-DEX and 16 KB ZIP alignment checks.
The release control installed on the same Android 16/API 36 Enforcing phone.
Package Manager confirmed no DEBUGGABLE flag. Binding and a commanded click
started the framework TileService in PID 10717, but there were no native
startup/click logs: the wrapper was not invoked. Opening NativeActivity
attempted the documented agent attachment and returned:

```text
java.lang.SecurityException: Can't attach agent, process is not debuggable.
JNI_EXCEPTION stage=attachJvmtiAgent
ACTIVITY_ATTACHED success=0
```

This route is rejected for production. The lab tile/package were removed and
the original Quick Settings list restored. No charging commands were executed.
The production APK manifest and daemon were not changed for this experiment.

## Android 17 native-service investigation

The NDK 30 header `android/native_service.h` and the official
[NativeService reference](https://developer.android.com/ndk/reference/group/native-service)
introduce `ANativeService` in API 37. It is a real native service bootstrap,
so the broad statement that Android has no native service API is outdated.
It does not establish a working native Quick Settings integration:

- `onBind` exposes a numeric binding token, action and data URI, not Intent extras.
- SystemUI's
  [TileLifecycleManager](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/packages/SystemUI/src/com/android/systemui/qs/external/TileLifecycleManager.java)
  supplies the IQSService Binder and tile token through `EXTRA_SERVICE` and
  `EXTRA_TOKEN` extras.
- Framework
  [TileService.onBind](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/service/quicksettings/TileService.java)
  consumes those Binder extras to fetch/update the tile and acknowledge startup.
- The native numeric binding token is not the Quick Settings Binder tile token.
  Implementing only IQSTileService click transactions would not provide the
  missing update/startup connection. Do not report such a stub as a working tile.
- The connected phone is API 36, so API 37 runtime behavior was not tested.

Conclusion: there is no verified release-mode solution under the current
zero-DEX, app-only, unchanged-ROM requirements. Do not ship the debug agent,
turn the real application debuggable, modify global runtime properties, or
add a background polling workaround to conceal this boundary.
