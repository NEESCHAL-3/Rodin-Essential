# Rodin Essential

Rodin Essential is a native-first privileged device-control application for Xiaomi Rodin.

## Product goals

- Preserve the established Rodin Essential UI design and feature behavior.
- Deliver launcher-grade motion quality and consistently smooth 120 Hz interaction.
- Ship the application with zero app DEX.
- Use a self-contained runtime with no dependency on HyperOS 4 private Rust/Flutter libraries.
- Compile the UI to Flutter/Dart AOT machine code.
- Implement the native host, application core, state handling, and privileged IPC in Rust.
- Keep privileged hardware access outside the UI process.
- Preserve thermal and hardware safety mechanisms.
- Remain portable across compatible ARM64 Android port ROMs.

## Architecture direction

`NativeActivity -> Rust host -> bundled Flutter engine -> Dart AOT UI -> Rust core -> privileged daemon`

The legacy Xiaomi Parts codebase is not compiled, vendored, or included in this repository.
It remains only as an external migration reference until feature parity is complete.
