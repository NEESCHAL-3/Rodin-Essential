# Commit convention

Use Conventional Commit subjects:

```text
<type>(<scope>): <imperative summary>
```

Recommended types are `feat`, `fix`, `perf`, `refactor`, `docs`, `test`,
`build`, `ci`, and `chore`.

Common scopes:

- `ui`: Flutter screens, text, layout, motion, and theme.
- `host`: NativeActivity, EGL, Flutter embedder, JNI, and FFI.
- `daemon`: IPC, persistence, telemetry, and hardware controls.
- `gpu`, `cpu`, `touch`, `storage`, `display`, `zram`: feature-specific work.
- `android`: manifest, resources, signing, init, and packaging.
- `aosp`: Soong, product integration, and SELinux.
- `kernelsu`: backend module packaging and service lifecycle.
- `docs`: maintainer and contributor documentation.

Examples:

```text
fix(gpu): persist GED ownership for active profiles
fix(touch): restore selected timing mode after boot
fix(storage): verify scheduler across every UFS LUN
perf(ui): smooth route transitions at 120 Hz
build(aosp): export product prebuilts and split policy
docs(aosp): document rootless ROM integration
```

Keep commits buildable. Combine multiple scopes only for a deliberate release
or repository-wide consolidation where separating them would leave incompatible
protocol, packaging, or version state.
