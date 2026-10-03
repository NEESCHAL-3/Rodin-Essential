# Bypass charging

Rodin uses a compatible kernel charge-pause power path. It does not emulate
bypass by writing `input_suspend`, suppress battery measurements, or disable
charger protections. Battery-neutral measurements do not prove physical battery
isolation; under an inadequate adapter or high load, the battery can supplement
system power.

## Kernel interface

The battery power-supply directory must expose all of the following:

- `bypass_charging_supported`: a readable true value.
- `bypass_charging` (or `bypass_charge`): a readable/writable request boolean.
- `bypass_charging_active`: a separately measured confirmation boolean.

An enabled request alone is not evidence that bypass is active. Rodin checks
external-power presence, the kernel confirmation, and measured battery current.
Unavailable telemetry, charging current, or battery supplementation is reported
explicitly rather than presenting a false direct-power state.

## Thresholds and persistence

`SET charging.bypass 1` enables the saved policy; `0` disables it.
`SET charging.bypass_threshold VALUE` selects `0` (Immediately), `20`, `40`,
`80`, or `90`. Below a percentage threshold, charging remains OEM-managed.
At the threshold, the daemon requests charge pause. A two-percentage-point
release band prevents repeated transitions at a rounded battery-level boundary.
Existing settings without a threshold retain the previous immediate behavior.

The enabled selection and threshold are persisted together in daemon state.
They do not depend on the Flutter page, foreground app, or app process staying
open. Normal charging-profile controls are unavailable while this policy is
enabled, including while charging toward its threshold. Disabling bypass returns
control to the saved charging profile. Reset clears bypass and its threshold.

## Monitoring and UI

Power-supply events handle connection and policy transitions. A separate,
read-only telemetry worker samples while bypass is enabled and external power
is connected, so unrelated device-control work cannot interrupt the kernel's
verification interval. Without external power it waits, with connection events
waking it. Requests are written only when the live node differs from the target;
bounded retries handle conflicts without continually rewriting an unchanged
request. Reopening a page, refreshing telemetry, or restoring an unchanged
setting must not restart hardware verification.

The threshold slider previews locally while dragging and submits once on release.
It does not issue a stream of hardware commands. Initial charger negotiation and
fuel-gauge settling still take real time; neither an instantaneous zero-current
reading nor zero battery current under every load is guaranteed.

Both ROM-native integration and root-module packaging use this same daemon and
app implementation. ROM integration needs the existing daemon service and
SELinux access to the supported power-supply nodes; the app itself does not need
root access when that integration is present.
