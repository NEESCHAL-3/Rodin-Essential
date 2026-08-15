# Flutter Runtime Pin

Rodin Essential uses a self-contained custom Flutter embedder and must not depend on
HyperOS-private Flutter runtime libraries.

## Toolchain pin

- Flutter SDK: `/home/neeschal/development/flutter`
- Engine revision: `0cd610717bde95fd88343c64f81c11ba4e5c0010`

## Rule

The Flutter framework used to compile Rodin Essential and the custom engine/embedder
must remain revision-compatible. Engine upgrades are explicit repository changes and
must be validated again for zero DEX, ARM64 loading, 16 KB alignment, frame pacing,
input, lifecycle, semantics, and feature parity.

## Current milestone

Phase 3 audits the installed Flutter SDK and determines whether its normal Android
engine artifact exposes the generic custom-embedder ABI. If it does not, Rodin
Essential will build and pin its own `libflutter_engine.so` from the matching engine
revision instead of depending on the ordinary Android Flutter embedding.
