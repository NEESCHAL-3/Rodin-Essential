class AudioCodecCapability {
  const AudioCodecCapability({
    required this.codec,
    required this.sampleRates,
    required this.bitDepths,
    required this.channelModes,
  });

  final int codec;
  final int sampleRates;
  final int bitDepths;
  final int channelModes;

  static const Map<int, String> codecNames = {
    0: 'SBC',
    1: 'AAC',
    2: 'aptX',
    3: 'aptX HD',
    4: 'LDAC',
    5: 'LC3',
  };

  static const Map<int, String> sampleRateNames = {
    1: '44.1 kHz',
    2: '48 kHz',
    4: '88.2 kHz',
    8: '96 kHz',
    16: '176.4 kHz',
    32: '192 kHz',
  };

  static const Map<int, String> bitDepthNames = {
    1: '16-bit',
    2: '24-bit',
    4: '32-bit',
  };

  String get name => codecNames[codec] ?? 'Codec $codec';

  List<int> get availableSampleRates =>
      sampleRateNames.keys.where((value) => sampleRates & value != 0).toList();

  List<int> get availableBitDepths =>
      bitDepthNames.keys.where((value) => bitDepths & value != 0).toList();
}

class AudioCodecSnapshot {
  const AudioCodecSnapshot({
    required this.codec,
    required this.sampleRate,
    required this.bitDepth,
    required this.capabilities,
    this.codecSpecific1,
  });

  final int codec;
  final int sampleRate;
  final int bitDepth;
  final int? codecSpecific1;
  final List<AudioCodecCapability> capabilities;

  AudioCodecCapability? capabilityFor(int codecType) {
    for (final capability in capabilities) {
      if (capability.codec == codecType) {
        return capability;
      }
    }
    return null;
  }

  static AudioCodecSnapshot? parse(String diagnostic) {
    if (!diagnostic.startsWith('OK;')) return null;

    final fields = <String, String>{};
    final capabilities = <AudioCodecCapability>[];

    for (final part in diagnostic.split(';').skip(1)) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;

      final key = part.substring(0, separator);
      final value = part.substring(separator + 1);

      if (key == 'cap') {
        final values = value.split(',');
        if (values.length != 4) continue;

        final numbers = values.map(int.tryParse).toList();

        if (numbers.any((number) => number == null)) {
          continue;
        }

        capabilities.add(
          AudioCodecCapability(
            codec: numbers[0]!,
            sampleRates: numbers[1]!,
            bitDepths: numbers[2]!,
            channelModes: numbers[3]!,
          ),
        );
      } else {
        fields[key] = value;
      }
    }

    final codec = int.tryParse(fields['codec'] ?? '');
    final sampleRate = int.tryParse(fields['sampleRate'] ?? '');
    final bitDepth = int.tryParse(fields['bits'] ?? '');

    if (codec == null || sampleRate == null || bitDepth == null) {
      return null;
    }

    return AudioCodecSnapshot(
      codec: codec,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      codecSpecific1: int.tryParse(fields['codecSpecific1'] ?? ''),
      capabilities: List.unmodifiable(capabilities),
    );
  }
}
