import 'dart:convert';

/// A configuration explicitly saved for one Bluetooth audio device.
///
/// This represents stored preferences, not the currently negotiated codec.
final class AudioDeviceProfile {
  const AudioDeviceProfile({
    required this.name,
    required this.codec,
    required this.sampleRate,
    required this.bits,
    required this.autoRestore,
    this.ldacQuality,
  });

  final String name;
  final int codec;
  final int sampleRate;
  final int bits;
  final bool autoRestore;
  final int? ldacQuality;

  static AudioDeviceProfile? parse(String response) {
    const prefix = 'PROFILE_FOUND;';

    if (!response.startsWith(prefix)) return null;

    try {
      final decoded = jsonDecode(response.substring(prefix.length));
      if (decoded is! Map<String, dynamic>) return null;

      final version = decoded['version'];
      final name = decoded['name'];
      final codec = decoded['codec'];
      final sampleRate = decoded['sampleRate'];
      final bits = decoded['bits'];
      final autoRestore = decoded['autoRestore'];
      final ldacQuality = decoded['ldacQuality'];

      if ((version != 1 && version != 2) ||
          name is! String ||
          codec is! int ||
          sampleRate is! int ||
          bits is! int ||
          autoRestore is! bool) {
        return null;
      }

      if (codec < 0 || sampleRate <= 0 || bits <= 0 || name.length > 256) {
        return null;
      }

      if (version == 2 &&
          ldacQuality != null &&
          (ldacQuality is! int ||
              codec != 4 ||
              ldacQuality < 1000 ||
              ldacQuality > 1003)) {
        return null;
      }

      return AudioDeviceProfile(
        name: name,
        codec: codec,
        sampleRate: sampleRate,
        bits: bits,
        autoRestore: autoRestore,
        ldacQuality: version == 2 ? ldacQuality as int? : null,
      );
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
