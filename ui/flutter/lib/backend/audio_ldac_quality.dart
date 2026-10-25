/// LDAC quality preference identifiers used by Android Bluetooth.
///
/// These describe requested quality modes, not measured bitrates.
/// Availability and successful negotiation must be verified separately.
abstract final class AudioLdacQuality {
  static const int qualityPriority = 1000;
  static const int balanced = 1001;
  static const int connectionPriority = 1002;
  static const int adaptive = 1003;

  static const Map<int, String> names = {
    adaptive: 'Adaptive (Best Effort)',
    qualityPriority: 'Quality priority (up to 990 kbps)',
    balanced: 'Balanced (up to 660 kbps)',
    connectionPriority: 'Connection priority (up to 330 kbps)',
  };

  static bool isKnown(int? value) =>
      value != null && names.containsKey(value);
}
