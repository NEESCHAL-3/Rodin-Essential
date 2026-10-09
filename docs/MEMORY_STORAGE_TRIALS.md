# Memory & Storage — initial safety stage

Custom session controls now expose `ACTION subsystem.clocks.level memory HZ`
and `ACTION subsystem.clocks.level storage HZ`, plus per-device
`ACTION subsystem.clocks.oem memory|storage`. Level requests set both
`min_freq` and `max_freq` to an advertised frequency, using ordered writes
and readback. This is an exact **driver policy lock**, not independent proof
of physical clocks overriding thermal protection or suspend. No repeated
reapply loop is used. OEM restores both original bounds; the write-ahead
journal also supports legacy floor-only records. App closure keeps locks;
daemon restart/reboot restores originals. Boot replay is not enabled.
Dynamic ranges use `ACTION subsystem.clocks.range memory|storage MIN_HZ MAX_HZ`.
Both bounds must be supported, ordered and within the original ROM ceiling.
Exact Lock uses equal bounds. The UI now follows the CPU card workflow:
preview sliders locally, then tap Apply. Current readings and live limits
refresh every two seconds while the screen is active, without reapplying
controls. App backgrounding or closing the screen stops those reads. Edited
slider values are not overwritten by telemetry. Status reports the requested
target separately from the observed driver limits.

The authenticated daemon exposes `GET subsystem.clocks`,
`ACTION subsystem.clocks.trial memory`,
`ACTION subsystem.clocks.trial storage`, and
`ACTION subsystem.clocks.reset`. These are additive development commands,
not a release or a persistent performance preset.

Each maximum trial lasts 30 seconds. It raises only the selected driver's
`min_freq` request to the highest entry in its own `available_frequencies`.
It preserves `max_freq`, governors, voltage, storage gears, clock gating and
thermal protection. If an existing ceiling excludes the highest state, the
trial is rejected rather than silently bypassing that ceiling.

Before writing, the daemon atomically records the original request in
`subsystem-clock-originals.json` in its existing state directory, fsyncs it,
and retains it until restoration succeeds. A condition-variable timer restores
the original request even if the UI is closed. There is no sysfs reapply loop.
Reset/Disable restores trials too. On daemon restart, pending originals are
recovered; maximum settings are never replayed at boot. Corrupt recovery data
blocks trials instead of being silently discarded.

DVFSRC uses the OEM userspace governor on the inspected device. Other governors
are not automatically changed. Its driver submits a DRAM performance request;
the reported current frequency is cached, not independent physical telemetry.
UFS exposes 273 and 499.2 MHz on the inspected device. Requests do not guarantee
that clocks stay running while the storage controller is idle/suspended.

The native AOSP/unpacked policy additions label only the two devfreq subtrees
for reading and their `min_freq`/`max_freq` files for writing. They grant no access to the
DVFSRC raw force-DDR or force-voltage controls. Existing module policy is not
globally relaxed by this feature. Unsupported or denied drivers report errors.

No timer can recover a kernel that has hung or lost storage access. Begin with
one subsystem at a time, with working ADB and a known recovery method. Test
lease expiry, app force-close and daemon restart recovery before considering
longer sessions or reboot persistence. Never describe a driver request as a
verified exclusive physical-clock lock.
