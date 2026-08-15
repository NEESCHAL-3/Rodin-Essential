# Rodin Essential Architecture

## Hard requirements

1. Final APK contains no `classes.dex` files.
2. Manifest uses `android:hasCode="false"`.
3. No Java or Kotlin application implementation.
4. No dependency on HyperOS 4 private runtime libraries.
5. Native runtime is bundled with Rodin Essential.
6. Flutter UI is AOT compiled for ARM64.
7. Rust owns the native host, state, validation, IPC, and asynchronous backend work.
8. UI/render work must never block on sysfs, procfs, Binder, socket, file, or daemon I/O.
9. The existing visual design remains the product specification during migration.
10. Existing working features must reach parity before the legacy implementation is retired.
11. 120 Hz is the primary interaction target on Rodin.
12. Thermal and device safety controls are never disabled to achieve performance.

## Planned runtime layers

- `runtime/host-rust`: Android NativeActivity lifecycle, window, input, vsync, renderer/embedder host.
- `runtime/flutter-engine`: pinned self-contained Flutter engine artifacts.
- `runtime/core-rust`: application state, persistence, validation, telemetry, command queue, IPC.
- `ui/flutter`: Rodin Essential Flutter UI, matching the established design.
- `android/package`: DEX-free Android manifest/resources/packaging.
- `tests/performance`: frame pacing, startup, navigation, scrolling, and touch-latency validation.
- `tests/integration`: runtime/backend/daemon feature validation.

## Migration policy

Legacy source is never copied into this repository as production code.
Features are reimplemented one subsystem at a time and validated against the working reference.
