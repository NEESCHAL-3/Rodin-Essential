# System Colors

System Colors is available under **Hubs → Display & Input**. It changes Android's
Material You palette, not the panel's calibration and not Rodin's own app theme.
The APK remains zero-DEX and runs with its ordinary application UID.

## Using the feature

1. Choose **Wallpaper** to let Android manage the palette, or **Custom color**
   to select a seed and style.
2. Tap a seed or style to apply it directly. A slider previews while moving and
   applies after a 280 ms pause following release. Starting another gesture
   cancels that wait and keeps the latest draft, so consecutive adjustments
   produce one write. Fine-tuning is always expanded in Custom mode;
   **Reset** restores the selected starting seed without changing the style.
   Light/dark preview buttons never change the system.
3. Select **Wallpaper** to restore automatic selection. There is no separate
   Apply button. Rapid choices keep only the latest pending selection while
   Android finishes the current transaction; failures do not start a retry loop.
4. Check **Android's current colors** for native resource readback. Its five
   swatches represent the accent and neutral families at tone 500. They are
   not the generated preview.
5. Use **Enter HEX** for an exact six-digit RGB seed. Confirmed custom choices
   appear under **Recent colors** and can be given a local name under
   **Saved palettes**. These shortcuts store only the seed and style in the
   app's private files; selecting one still uses the normal verified Android
   transaction.
6. Expand **Palette Lab** to inspect all thirteen tones in each of Android's
   five generated families. This is a local preview and is never presented as
   native readback.

Selections update immediately and submit without waiting for another frame
or tap. A choice made during initial discovery or a refresh is retained until
that read completes. One light haptic belongs to the tap; asynchronous
completion does not produce another vibration. Seed tiles include their labels
in the touch target. The fine-tune sliders use continuous values and color
tracks; their HSL draft is retained without repeatedly rounding through RGB,
so moving through gray, black or white does not lose hue or intensity.
Slider haptics are sparse and rate-limited. A completed slider edit is flushed
when leaving the screen if the native service is idle; unfinished drags are
not submitted by screen disposal.

Preview generation runs in one on-demand Dart isolate, separate from input and
painting. A bounded cache avoids repeated work, and rapid changes replace the
pending preview with the latest selection instead of building a job backlog.
The worker stops when the screen is closed. Custom instructions and tuning
controls are shown only in Custom mode; Wallpaper has its own guidance.
The system's overlay update and its verified readback remain
asynchronous and can finish after the selected swatch is visible.

Some HyperOS builds create a display-wide transition snapshot for palette
overlay changes. While it covers the screen, Android can reject touches as
obscured. This is a system transition, not a disabled Rodin control. Grouping
slider edits reduces interruptions but does not promise zero-latency global
theme changes. Rodin does not disable obscured-touch protection, change system
animation scales, or patch the ROM to conceal this limitation.

Compatible apps must use dynamic colors. A fixed keyboard or OEM theme, or an
app with its own colors, can ignore the system palette. Very dark or
low-chroma seeds may produce Android's fallback color; use Monochrome for a
grayscale palette where supported. The preview is illustrative because the
installed Android version and OEM implementation determine the final tones.

## Platform support

Android 12 introduced five native tonal families with thirteen values per family.
Android 13 expanded the supported generation styles. See the
[AOSP dynamic-color specification](https://source.android.com/docs/core/display/dynamic-color).

| Android version | Styles exposed by Rodin |
| --- | --- |
| 12 / 12L | Tonal |
| 13 | Tonal, Vibrant, Expressive, Soft, Rainbow, Fruit Salad |
| 14 and newer | All of the above plus Monochrome |

Soft maps to `SPRITZ`; Monochrome maps to `MONOCHROMATIC`. Android 17's
[theme compatibility requirements](https://source.android.com/docs/compatibility/17/android-17-cdd#3_8_6_themes)
retain the same palette-setting mechanism and seven styles. This is a platform
contract, not a claim that every Android 17 OEM build has been device-tested.

On Android 14 and newer, Rodin also exposes Android's native Material contrast
levels when the framework contrast resources are present. **Low**, **Standard**
and **High** map to the platform `contrast_level` range -1.0, 0.0 and 1.0. This
changes Material role contrast, not the physical panel's contrast. The control
is hidden on unsupported builds. A successful change requires both setting
readback and stable regeneration of light and dark container/text roles; a
failed change restores the preceding value.

Rodin does not identify support from overlay package or fabricated-overlay
names. Those identifiers are private to each SystemUI implementation and differ
between AOSP-derived ROMs and OEM builds. On Android 12 or newer, Rodin checks
the native framework palette resources, then verifies both the standard setting
and the resulting native resources after each change. This uses the same AOSP
contract on AOSP, Pixel-style, Lineage-derived, HyperOS, ColorOS/OxygenOS, and
other OEM ROMs without a ROM-name allowlist.

A ROM that removes or disables Android's dynamic-color engine cannot provide a
system-wide Material You palette; on that build Rodin remains preview-only and
does not fabricate a result. A standalone APK or an older backend cannot apply
the setting.

## Ownership and persistence

The daemon resolves the foreground Android user and uses direct `cmd` arguments
to read and update the secure setting `theme_customization_overlay_packages`.
Custom colors set the seed and `preset` source. Android 12 also receives its
required legacy accent field and uses Tonal Spot; Android 13 and newer receive
the selected style without the deprecated accent field. Wallpaper mode removes
the custom seed, records `home_wallpaper` as the source, and selects the default
`TONAL_SPOT` style where styles are supported. The setting remains
a JSON object: deleting it can leave SystemUI's previous style active. Unrelated
font, icon, shape, and OEM values are retained. Malformed existing JSON is
rejected rather than replaced.

SettingsProvider stores the choice and SystemUI generates the overlays. Neither
the APK nor the daemon needs a palette reapply loop or a new boot hook. Closing
Rodin does not remove the choice. Changing it later in another theme picker is
respected. A factory reset clears the Android user's settings normally.

The app stores a small last-confirmed source/seed/style hint for presentation
on the next launch. This avoids briefly selecting Wallpaper before Android's
read completes. It is never used to reapply a setting or fabricate native
resource readback; fresh Android state always replaces it. On a first launch
without a hint, both source tiles remain unselected until the read completes
or the user makes a choice.

The transaction verifies the saved fields and waits through a bounded,
progressive settle window for two matching native color readings, so a partly
updated overlay is not reported as a final palette.
The five resource lookups within each reading run concurrently with bounded
command timeouts. Both complete readings and all saved-setting/conflict checks
are retained. During an operation, the app checks two atomic native cache fields
every 32 ms so a completed selection does not wait for the 500 ms dashboard
cadence. This observer stops on completion, failure or timeout and never polls
hardware or rewrites settings.
If a new custom seed or style is retained in SettingsProvider but the native
resources do not change, the transaction fails and restores the previous
palette rather than reporting false success. Wallpaper mode can legitimately
resolve to the same colors; in that case the interface reports that wallpaper
following was restored without claiming a visible change. A failed transaction
never overwrites a newer palette from another picker. Android does not expose a
compare-and-set operation for this JSON setting; concurrent edits are checked
before and after the write.

System Colors does not enable/disable overlay packages itself, stop SystemUI,
change wallpapers, or alter CPU, GPU, touch, display calibration, or charging.

## ROM and module integration

Both deployment paths build the same app, native host, and daemon sources.
Update them together. The AOSP private daemon policy includes service discovery
for `activity_service` and `overlay_service`, in addition to the existing
SettingsProvider and system-server Binder permissions. No privileged app
permission, platform APK signature, permissive SELinux domain, or root-manager
policy patch is added. ROM-native operation needs no root manager.

Native diagnostic commands, available through the existing authenticated
development client, are:

```text
GET system.colors
SET system.colors <24-bit RGB integer> <style index 0..6>
SET system.colors.wallpaper
GET system.colors.contrast
SET system.colors.contrast <-1000|0|1000>
```

The native host uses extended operations 24–28 and cache fields 81–104. Palette
and contrast results have independent operation state, error and revision
fields. They remain separate from hardware acknowledgements and persistence.
Android commands run off the UI thread with bounded subprocess timeouts.

## Validation

```bash
./tools/test-system-colors.sh
bash tools/test-aosp-integration.sh
bash tools/test-release-sync.sh
bash tools/test-root-module-contract.sh
RODIN_BUILD_ONLY=1 ./build-and-install.sh
```

On Windows, the palette transaction tests can run without compiling the
Unix-only daemon transport:

```powershell
cargo test --manifest-path tools/system-colors-host-tests/Cargo.toml
cd ui/flutter
flutter test
```

Tests cover Android 12 and Android 13+ JSON contracts, JSON preservation, reset,
input/style validation, strict native regeneration readback,
idempotency, rollback, concurrent picker changes, native protocol/cache mapping,
offline/connecting handling, tap-to-apply, settled slider writes, coalesced
selections, HSL endpoints, reset after native readback, complete seed hit targets,
scroll cancellation, pointer-down deferral, completed-edit disposal, bounded
completion observation, concurrent resource reads, background preview parity,
all 65 preview tones, native contrast protocol/capability mapping, and responsive
light/dark layouts.
Native activity configuration
handles overlay asset changes without returning the user to Home. The native
client connects in parallel with startup; an unchecked connection is displayed
as Connecting, not Offline or a fabricated Live status.
Policy contract checks do not replace testing an enforcing production ROM.
