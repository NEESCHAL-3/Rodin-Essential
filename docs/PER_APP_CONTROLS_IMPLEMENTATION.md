# Per-App Controls implementation

Status: local development, not released. The daemon runtime and Hubs screen
are implemented and installed on the development phone for testing.

## User-facing contract

Location: Hubs → Performance → Per-App Controls.

Description: “Set individual touch, refresh rate, CPU and GPU controls for each app.”

Each control starts as **Follow global**. This is different from selecting OEM
adaptive explicitly. Profiles apply only to the foreground app and Android user
that owns them. System apps and third-party apps use the same model.

Global preferences remain the baseline. An app profile borrows selected controls;
it does not rewrite saved global choices. Leaving a profiled app restores that
baseline, including custom GPU and CPU preferences, not an assumed stock profile.

The master switch defaults OFF on a fresh installation. Saving a profile never
turns it on implicitly. Selected controls take precedence while their app is
focused; all unselected controls keep following the global/ROM setup. On exit
or disable, restore the captured global controls and ROM display preferences,
including any existing OEM refresh-rate values. Thermal/display safety limits
are not disabled and an app's rendered FPS is not fabricated.

CPU ranges and governors are separate controls. GPU profiles never own CPU
controls. ZRAM and swap stay global: resetting live swap on app transitions is
not an acceptable per-app operation.

Turning off Per-App Controls preserves its saved profiles but releases active
overrides. Resetting an app removes its profile and releases its controls if
active. Reset all clears profiles and releases overrides. Disabling Rodin
Essential takes priority over every profile.

## Implemented foundation

`runtime/daemon-rust/src/app_controls.rs` contains:

- Versioned, bounded profile configuration and private atomic file replacement.
- Strict package/user identity, input and field validation.
- Capability validation against detected CPU frequency/governor tables and
  supported touch/GPU/refresh modes. No guessed CPU frequencies.
- Independent CPU range, governor and core targets.
- Resumed-app event parsing for Android/vendor event-log formats.
- Ownership transitions that capture originals before writing, deduplicate
  unchanged targets, restore dropped controls and roll back failed application.
- Recovery state that retains originals when restoration fails. It must not be
  shown as an active, successfully applied profile.

`app_runtime.rs` supplies Android adapters, event-driven foreground detection,
serialized transitions and a durable original-value recovery journal. Temporary
overrides are kept out of saved global preferences. The foreground resolver
uses the focused activity summary, not the first floating/resumed window.

## Runtime and UI

- Passive activity-event listening wakes an authoritative foreground query.
  No continuous activity-dump polling or repeated display preference writes.
- Authenticated, bounded IPC owns profile storage and acknowledges runtime state.
- Installed system/third-party apps use native PackageManager labels and actual
  drawable icons without DEX. Icons are rasterized off the rendering isolate in
  bounded batches and cached across screen visits. System apps start hidden;
  the switch reveals them without deleting profiles or changing controls.
  The complete app list loads progressively as you scroll, with no Show More
  button. Metadata is refreshed on each visit; cached rows appear first.
- Editor controls use detected frequencies, governors and supported refresh modes.
  Mode selection uses animated inline cards, not dropdown menus. CPU frequencies
  use discrete sliders over the detected table; governor selection is separate.
  Taps save immediately, while slider drags preview and save on release. Pending
  changes coalesce to the latest draft, not a backlog of stale selections.
  App-editor navigation uses short fade/offset transitions, respects reduced
  motion, and Back returns to the preserved app list before leaving the section.
- Global writes are rejected only for the controls currently owned by a profile.
- Private `app-profiles.json` stores selections; `app-recovery.json` records
  originals before writes. Recovery runs before applying profiles after restart.
- Refresh restoration preserves original values or their absence, including
  framework replies that describe an unset display mode as `null`.
- Existing numeric `user_refresh_rate` / `miui_refresh_rate` settings are
  captured per namespace and restored exactly. Missing vendor settings are not
  created on other ROMs. The standard Android display-mode/min/peak path remains.
  On detected MIUI refresh configurations, an existing boolean `is_smart_fps`
  setting is temporarily switched out of adaptive mode and restored on exit.
- Foreground transitions get bounded read-only settling checks after activity
  events; pause/stop events also release stale ownership. Identical targets
  still avoid redundant hardware writes. Editors clearly distinguish saved-only,
  disabled and active states; packages without launcher entries are identified.
- The last released CPU override restores the journaled original thermal mode,
  including after daemon restart. Governors remain independently selected.
- ROM policy adds scoped package-service lookup and activity-log reading.
  Existing module daemon startup is reused; no extra privileged UI service.
- Reset per app, reset all, and profile disable restore owned controls.
  Switch notifications are not exposed in this development build.

## Development verification

94 daemon unit tests and 101 Flutter tests passed. Flutter analysis passed. The
local APK passed signing, zero-DEX and
16 KB alignment checks.

The opt-in `tools/test-per-app-device.py --apply` test passed on the development
Rodin: Settings profile activation, touch/GPU/CPU-range acknowledgement, unchanged
CPU governor, conflicting-global-write rejection, force-closed UI, daemon restart
and saved-profile recovery, launcher restoration, original thermal-mode recovery,
active-profile reset, and preservation of saved global selections. It removes
only its temporary profile and leaves Per-App Controls disabled afterwards.

On the current development phone, the saved DevCheck CPU mask `249` was also
verified: CPU1/CPU2 offline (`0,3-7`) while DevCheck is foreground, unchanged
after force-closing Rodin Essential, and restored to `0-7` when leaving DevCheck.
CPU hotplug skips redundant writes and retries only transient EBUSY failures
twice (20/40 ms); permanent failures remain errors and trigger rollback.

A full phone reboot, additional ROMs, ROM-native policy compilation against a
target platform, and sustained multi-app/split-screen testing remain necessary
before release. Daemon-restart testing is not a substitute for a reboot test.

Fixed refresh choices request supported panel modes; they do not manufacture app
FPS or guarantee that a ROM will ignore its own display safety/power constraints.
Report unsupported or rejected requests instead of displaying false success.

No version bump, release asset or remote publication is part of this stage.

The October 8 regression also verified CPU core/range, GPU profile and touch
driver acknowledgement, actual 60/90/120 Hz display modes during interaction
in DevCheck, combined overrides, UI force-close independence and restoration
of the original profiles, saved global preferences and ROM refresh settings.
The adaptive-baseline regression confirmed adaptive → fixed app override →
adaptive restoration, plus combined-profile recovery after daemon restart.
These are development-phone results, not an all-ROM certification.
