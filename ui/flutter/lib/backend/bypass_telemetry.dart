/// The kernel owns the settling interval; a page must not restart it.
/// Check the current snapshot as well, rather than caching a successful label.
bool isBypassDirectPowerConfirmed({
  required bool ready,
  required bool enabled,
  required bool kernelActive,
  required int usbOnline,
  required double? batteryCurrentA,
}) =>
    ready &&
    enabled &&
    kernelActive &&
    usbOnline == 1 &&
    batteryCurrentA != null &&
    batteryCurrentA.isFinite &&
    batteryCurrentA.abs() <= 0.10;
