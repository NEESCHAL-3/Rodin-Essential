# Commit Convention

Use concise Conventional Commit messages with meaningful scopes.

Examples:

- `chore: initialize Rodin Essential native workspace`
- `feat(host): boot zero-DEX NativeActivity runtime`
- `feat(render): add Vulkan-backed Flutter embedder`
- `feat(ui): reproduce Rodin Essential home surface`
- `feat(core): add persistent asynchronous command state`
- `feat(daemon): migrate charging control to Rust`
- `perf(ui): eliminate rebuilds during telemetry updates`
- `perf(render): stabilize 120 Hz frame pacing`
- `fix(touch): preserve selected sampling mode after reboot`
- `test(runtime): verify APK contains no DEX`
- `build(android): package signed ARM64 release APK`

Do not mix unrelated subsystems in one commit.
Every migration commit should leave the tree buildable.
