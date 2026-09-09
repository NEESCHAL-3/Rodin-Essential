/// Cached Android palette readback. Color values are opaque 24-bit RGB, not
/// generated previews. Loading this model never queries an Android service.
final class RodinSystemColorsState {
  const RodinSystemColorsState({
    this.operationState = 0,
    this.supported = false,
    this.mode = -1,
    this.seed = -1,
    this.style = -1,
    this.primary = -1,
    this.secondary = -1,
    this.tertiary = -1,
    this.neutral = -1,
    this.neutralVariant = -1,
    this.sdk = -1,
    this.user = -1,
    this.outcome = 0,
    this.error = 0,
    this.revision = 0,
  });

  factory RodinSystemColorsState.fromNative(int Function(int) read) {
    return RodinSystemColorsState(
      operationState: read(81),
      mode: read(82),
      seed: read(83),
      style: read(84),
      primary: read(85),
      secondary: read(86),
      tertiary: read(87),
      neutral: read(88),
      neutralVariant: read(89),
      sdk: read(90),
      user: read(91),
      outcome: read(92),
      error: read(93),
      revision: read(94),
      supported: read(95) == 1,
    );
  }

  final int operationState;
  final bool supported;
  // 0: wallpaper, 1: custom seed, 2: an external preset without a readable seed.
  final int mode;
  final int seed;
  final int style;
  final int primary;
  final int secondary;
  final int tertiary;
  final int neutral;
  final int neutralVariant;
  final int sdk;
  final int user;
  // 0: read/already selected, 1: native colors changed, 2: saved but unchanged.
  final int outcome;
  final int error;
  final int revision;

  bool get busy => operationState == 1;
  bool get ready => operationState == 2;
  bool get failed => operationState == -1;
  List<int> get nativeColors => <int>[
    primary,
    secondary,
    tertiary,
    neutral,
    neutralVariant,
  ];
  bool get hasReadback =>
      revision > 0 &&
      nativeColors.every((int rgb) => rgb >= 0 && rgb <= 0xffffff);

  String get errorMessage => switch (error) {
    1 =>
      'Material You control is unavailable. This requires Android 12 or newer, '
          'native dynamic-color resources, and an updated System Colors backend.',
    2 =>
      'Android’s existing theme data could not be read safely. It was left '
          'untouched. Choose a theme in system settings, then refresh.',
    3 => 'The system theme changed while applying. Refresh and try again.',
    4 =>
      'Android denied or did not finish a theme command. Check that the ROM '
          'or module includes the updated backend and its policy.',
    5 =>
      'The change could not be verified. Refresh to check Android’s current '
          'colors before trying again.',
    6 =>
      'Another palette operation is still running. Please try again shortly.',
    8 =>
      'This color or palette style is not supported by this Android version.',
    9 =>
      'The backend returned an incomplete palette. Update the app and '
          'backend together.',
    _ =>
      'The system service could not be reached. Connect the updated Rodin '
          'backend, then refresh.',
  };
}

/// Last confirmed choice for presentation during startup, never native
/// resource readback or authority to write a system setting.
final class RodinSystemColorsSelection {
  const RodinSystemColorsSelection({
    required this.wallpaper,
    required this.seed,
    required this.style,
  });

  final bool wallpaper;
  final int seed;
  final int style;

  static RodinSystemColorsSelection? fromNative(RodinSystemColorsState state) {
    if (!state.ready ||
        !state.hasReadback ||
        (state.mode != 0 && state.mode != 1) ||
        state.style < 0 ||
        state.style > 6) {
      return null;
    }
    if (state.mode == 1 && (state.seed < 0 || state.seed > 0xffffff))
      return null;
    return RodinSystemColorsSelection(
      wallpaper: state.mode == 0,
      seed: state.seed >= 0 ? state.seed : 0x008577,
      style: state.style,
    );
  }

  static RodinSystemColorsSelection? fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['schema'] != 1) return null;
    final Object? wallpaper = value['wallpaper'];
    final Object? seed = value['seed'];
    final Object? style = value['style'];
    if (wallpaper is! bool ||
        seed is! int ||
        style is! int ||
        seed < 0 ||
        seed > 0xffffff ||
        style < 0 ||
        style > 6)
      return null;
    return RodinSystemColorsSelection(
      wallpaper: wallpaper,
      seed: seed,
      style: style,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'schema': 1,
    'wallpaper': wallpaper,
    'seed': seed,
    'style': style,
  };

  @override
  bool operator ==(Object other) =>
      other is RodinSystemColorsSelection &&
      other.wallpaper == wallpaper &&
      other.seed == seed &&
      other.style == style;

  @override
  int get hashCode => Object.hash(wallpaper, seed, style);
}
