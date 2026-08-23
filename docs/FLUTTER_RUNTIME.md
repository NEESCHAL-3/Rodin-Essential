# Flutter runtime pin

Rodin Essential ships its own custom Flutter embedder runtime and does not load
Flutter libraries from the ROM.

The framework engine revision is read from the active Flutter SDK at:

```text
bin/internal/engine.version
```

`tools/build-flutter-engine.sh` compares that value with the engine checkout
before building. A mismatch is a hard failure because the AOT snapshot,
`embedder.h`, and `libflutter_engine.so` must share an ABI revision.

Local engine artifacts are deliberately ignored by Git:

```text
runtime/flutter-engine/prebuilt/android-arm64/libflutter_engine.so
runtime/flutter-engine/prebuilt/android-arm64/icudtl.dat
```

An engine update is complete only after rebuilding the APK and validating zero
DEX, ARM64 loading, 16 KB alignment, first frame, EGL lifecycle, input,
choreographer pacing, foreground/background transitions, and all backend FFI
entry points on Rodin hardware.
