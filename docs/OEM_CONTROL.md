# OEM-controlled touch and display

Fresh installations and missing settings leave touch sampling, display colour,
temperature and display enhancements under ROM control. A value
of `-1` in the saved state means no Rodin Essential override; it does not mean the hardware
feature is disabled.

Existing explicit choices are preserved. Selecting a fixed touch profile or a
colour/temperature mode stores that choice in the daemon's persistent state and
restores it when the daemon starts, independently of the app's lifecycle.

## Returning touch timing to the ROM

Select **OEM Control**. The daemon stops custom event output, releases its vendor
game/super-report requests, restores the captured touch timing and driver values,
and relinquishes their restore journal entries. Subsequent wake checks and daemon
starts do not apply a fixed touch profile. Wake restoration is serialized with
this release so an older queued request cannot resurrect the previous mode.

The fixed profiles are unchanged: native 240 Hz and 480 Hz targets are labelled
250 and 500 to match common tester rounding; 1000 is resampled Android output,
not a claim of 1000 physical panel scans per second. Available control paths
depend on the panel and vendor services.

## Returning colour modes to the ROM

Select **OEM Control** separately for colour and temperature. This removes that
Rodin Essential override from persistence without forcing Vivid, Normal or another guessed
stock mode. The vendor display interface does not provide a portable original
profile getter or ownership-release transaction. The current appearance can
remain until the ROM reapplies its display settings. Expert calibration is
restored only when Original PRO is explicitly selected.

Switches marked **OEM** report no Rodin Essential selection, rather than pretending the
hardware feature is off. Explicitly selecting a switch still saves an override.

These controls use the same daemon logic in ROM-native and root-module builds.
They do not grant support for a missing vendor HAL and do not require repeated
app-side writes while OEM Control is selected.
