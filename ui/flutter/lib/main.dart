import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/material.dart';

import 'backend/rodin_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RodinBackend.instance.start();
  await RodinThemeController.bootstrap();
  runApp(const RodinEssentialApp());
}

enum RodinScreen {
  home,
  hubs,
  support,
  settings,
  charging,
  touchBoost,
  displayStudio,
  perAppProfiles,
  cpuPerformance,
  advancedConfiguration,
  resolution,
  diagnostics,
  zramSwap,
  maliGpu,
}

extension RodinScreenName on RodinScreen {
  String get title {
    switch (this) {
      case RodinScreen.home:
        return 'Rodin Essential';
      case RodinScreen.hubs:
        return 'Control Hubs';
      case RodinScreen.support:
        return 'Community & Support';
      case RodinScreen.settings:
        return 'Settings';
      case RodinScreen.charging:
        return 'Charging';
      case RodinScreen.touchBoost:
        return 'Touch Response';
      case RodinScreen.displayStudio:
        return 'Display Studio';
      case RodinScreen.perAppProfiles:
        return 'Per-app Profiles';
      case RodinScreen.cpuPerformance:
        return 'CPU Performance';
      case RodinScreen.advancedConfiguration:
        return 'Advanced Configuration';
      case RodinScreen.resolution:
        return 'Resolution';
      case RodinScreen.diagnostics:
        return 'Diagnostics';
      case RodinScreen.zramSwap:
        return 'ZRAM & Swap Manager';
      case RodinScreen.maliGpu:
        return 'MediaTek Mali GPU & GED';
    }
  }

  bool get isRoot =>
      this == RodinScreen.home ||
      this == RodinScreen.hubs ||
      this == RodinScreen.support ||
      this == RodinScreen.settings;
}

enum RodinThemePreference { system, light, dark }

class RodinThemeController {
  const RodinThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  static ThemeMode themeMode(RodinThemePreference preference) {
    return switch (preference) {
      RodinThemePreference.system => ThemeMode.system,
      RodinThemePreference.light => ThemeMode.light,
      RodinThemePreference.dark => ThemeMode.dark,
    };
  }

  static RodinThemePreference preferenceFromName(String? name) {
    return RodinThemePreference.values.firstWhere(
      (RodinThemePreference value) => value.name == name,
      orElse: () => RodinThemePreference.system,
    );
  }

  static void setPreference(RodinThemePreference preference) {
    mode.value = themeMode(preference);
  }

  static Future<void> bootstrap() async {
    try {
      final File file = File(
        '${Directory.systemTemp.parent.path}'
        '/files/rodin-appearance.json',
      );

      if (!await file.exists()) {
        return;
      }

      final Object? raw = jsonDecode(await file.readAsString());

      if (raw is! Map<String, dynamic>) {
        return;
      }

      setPreference(preferenceFromName(raw['themeMode']?.toString()));
    } catch (_) {
      mode.value = ThemeMode.system;
    }
  }
}

class RodinEssentialApp extends StatelessWidget {
  const RodinEssentialApp({super.key});

  static const Color _darkBackground = Color(0xFF000000);
  static const Color _darkSurface = Color(0xFF000000);
  static const Color _darkSurfaceVariant = Color(0xFF080808);
  static const Color _darkPrimary = Color(0xFF59BCFF);
  static const Color _darkSecondary = Color(0xFF4CDEB6);
  static const Color _darkTertiary = Color(0xFFFFB95E);
  static const Color _darkOnSurface = Color(0xFFF4F7FB);
  static const Color _darkOnSurfaceVariant = Color(0xFFAEB8C5);
  static const Color _darkOutline = Color(0xFF1C1C1C);

  static const Color _lightBackground = Color(0xFFF4F7FB);
  static const Color _lightSurface = Color(0xFFFCFDFF);
  static const Color _lightSurfaceVariant = Color(0xFFEEF3F8);
  static const Color _lightPrimary = Color(0xFF087AC7);
  static const Color _lightSecondary = Color(0xFF078F79);
  static const Color _lightTertiary = Color(0xFFB8730A);
  static const Color _lightOnSurface = Color(0xFF111925);
  static const Color _lightOnSurfaceVariant = Color(0xFF566477);
  static const Color _lightOutline = Color(0xFFD2DCE7);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: RodinThemeController.mode,
      builder: (BuildContext context, ThemeMode themeMode, Widget? child) {
        return MaterialApp(
          title: 'Rodin Essential',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: _theme(
            brightness: Brightness.light,
            background: _lightBackground,
            surface: _lightSurface,
            surfaceVariant: _lightSurfaceVariant,
            primary: _lightPrimary,
            secondary: _lightSecondary,
            tertiary: _lightTertiary,
            onSurface: _lightOnSurface,
            onSurfaceVariant: _lightOnSurfaceVariant,
            outline: _lightOutline,
          ),
          darkTheme: _theme(
            brightness: Brightness.dark,
            background: _darkBackground,
            surface: _darkSurface,
            surfaceVariant: _darkSurfaceVariant,
            primary: _darkPrimary,
            secondary: _darkSecondary,
            tertiary: _darkTertiary,
            onSurface: _darkOnSurface,
            onSurfaceVariant: _darkOnSurfaceVariant,
            outline: _darkOutline,
          ),
          home: const RodinShell(),
        );
      },
    );
  }

  ThemeData _theme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceVariant,
    required Color primary,
    required Color secondary,
    required Color tertiary,
    required Color onSurface,
    required Color onSurfaceVariant,
    required Color outline,
  }) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
      onSurface: onSurface,
      outline: outline,
    );

    final TextTheme textTheme = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme.copyWith(
        surface: surface,
        surfaceContainer: surfaceVariant,
        surfaceContainerLow: surfaceVariant,
        surfaceContainerHighest: surfaceVariant,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
      ),
      textTheme: textTheme.apply(bodyColor: onSurface, displayColor: onSurface),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: outline.withValues(alpha: 0.50),
        overlayColor: primary.withValues(alpha: 0.10),
      ),
    );
  }
}

class RodinShell extends StatefulWidget {
  const RodinShell({super.key});

  @override
  State<RodinShell> createState() => _RodinShellState();
}

class _RodinShellState extends State<RodinShell> {
  static const List<RodinScreen> _rootOrder = <RodinScreen>[
    RodinScreen.home,
    RodinScreen.hubs,
    RodinScreen.support,
    RodinScreen.settings,
  ];

  final PageController _rootController = PageController(initialPage: 0);
  final ValueNotifier<RodinAppearanceConfig> _appearance =
      ValueNotifier<RodinAppearanceConfig>(
        const RodinAppearanceConfig.defaults(),
      );

  RodinScreen _screen = RodinScreen.home;
  RodinScreen _detailBackTarget = RodinScreen.home;
  RodinScreen? _nestedDetailBackTarget;
  bool _rootSwipeLocked = false;
  bool _rootNavAnimating = false;
  RodinScreen? _rootNavTarget;
  late final VoidCallback _interactionRevisionListener;
  Timer? _nativeBackPoll;

  File get _appearanceFile {
    final Directory parent = Directory.systemTemp.parent;
    return File('${parent.path}/files/rodin-appearance.json');
  }

  int _rootIndex(RodinScreen screen) {
    final int index = _rootOrder.indexOf(screen);
    return index < 0 ? 0 : index;
  }

  RodinScreen _visualRoot() {
    return _screen.isRoot ? _screen : _detailBackTarget;
  }

  @override
  void initState() {
    super.initState();

    _interactionRevisionListener = () {
      if (!mounted) {
        return;
      }

      setState(() {});
    };

    RodinInteractionSettings.revision.addListener(_interactionRevisionListener);

    RodinInteractionSettings.load();
    RodinBackend.instance.setBackIntercept(false);

    _nativeBackPoll = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted || !RodinBackend.instance.consumeBackRequest()) {
        return;
      }

      if (_screen != RodinScreen.home) {
        _back();
      }
    });

    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    try {
      final File file = _appearanceFile;
      if (!await file.exists()) {
        return;
      }

      final String raw = await file.readAsString();
      final Object? decoded = jsonDecode(raw);
      final RodinAppearanceConfig config = RodinAppearanceConfig.fromJson(
        decoded,
      );

      if (!mounted) {
        return;
      }

      _appearance.value = config;
      RodinThemeController.setPreference(config.themePreference);
    } catch (_) {
      // Appearance must never block app boot.
    }
  }

  Future<void> _persistAppearance() async {
    try {
      final File file = _appearanceFile;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(_appearance.value.toJson()),
        flush: false,
      );
    } catch (_) {
      // Appearance persistence is non-critical.
    }
  }

  void _setThemePreference(RodinThemePreference preference) {
    RodinThemeController.setPreference(preference);

    _appearance.value = _appearance.value.copyWith(themePreference: preference);

    _persistAppearance();
  }

  void _setAccentIndex(int index) {
    _appearance.value = _appearance.value.copyWith(accentIndex: index);
    _persistAppearance();
  }

  void _setCardRadius(double radius) {
    _appearance.value = _appearance.value.copyWith(cardRadius: radius);
    _persistAppearance();
  }

  void _setCardStyle(int style) {
    _appearance.value = _appearance.value.copyWith(cardStyle: style);
    _persistAppearance();
  }

  void _setHeroGlow(bool glow) {
    _appearance.value = _appearance.value.copyWith(heroGlow: glow);
    _persistAppearance();
  }

  void _setCoreVisualizerStyle(int style) {
    _appearance.value = _appearance.value.copyWith(coreVisualizerStyle: style);
    _persistAppearance();
  }

  void _setCustomBackgroundPath(String path) {
    _appearance.value = _appearance.value.copyWith(
      backgroundStyle: RodinBackgroundStyle.custom,
      customPath: path,
    );

    _persistAppearance();
  }

  void _setBackgroundStyle(RodinBackgroundStyle style) {
    _appearance.value = _appearance.value.copyWith(backgroundStyle: style);
    _persistAppearance();
  }

  void _setBackgroundBlur(double value) {
    _appearance.value = _appearance.value.copyWith(
      backgroundBlur: value.clamp(0.0, 28.0).toDouble(),
    );
  }

  void _commitBackgroundBlur(double value) {
    _setBackgroundBlur(value);
    _persistAppearance();
  }

  void _resetAppearance() {
    const RodinAppearanceConfig defaults = RodinAppearanceConfig.defaults();

    RodinThemeController.setPreference(defaults.themePreference);

    _appearance.value = defaults;
    _persistAppearance();
  }

  void _setRootSwipeLocked(bool locked) {
    if (_rootSwipeLocked == locked) {
      return;
    }
    setState(() => _rootSwipeLocked = locked);
  }

  void _syncNativeBackInterception() {
    RodinBackend.instance.setBackIntercept(_screen != RodinScreen.home);
  }

  void _selectRoot(RodinScreen screen) {
    if (!screen.isRoot) {
      return;
    }

    final int target = _rootIndex(screen);

    setState(() {
      _screen = screen;
      _detailBackTarget = screen;
      _nestedDetailBackTarget = null;
      _rootNavAnimating = _rootController.hasClients;
      _rootNavTarget = screen;
    });

    if (_rootController.hasClients) {
      unawaited(
        _rootController
            .animateToPage(
              target,
              duration: RodinInteractionSettings.motionDuration(320),
              curve: RodinInteractionSettings.transitionCurve,
            )
            .whenComplete(() {
              if (!mounted || _rootNavTarget != screen) return;
              setState(() {
                _screen = screen;
                _rootNavAnimating = false;
                _rootNavTarget = null;
              });
            }),
      );
    } else {
      _rootNavAnimating = false;
      _rootNavTarget = null;
    }

    _syncNativeBackInterception();
  }

  void _onRootPageChanged(int index) {
    if (index < 0 || index >= _rootOrder.length) {
      return;
    }

    final RodinScreen next = _rootOrder[index];

    if (_rootNavAnimating && _rootNavTarget != null && next != _rootNavTarget) {
      return;
    }

    if (_screen == next) {
      return;
    }

    setState(() {
      _screen = next;
      _detailBackTarget = next;
      _nestedDetailBackTarget = null;
    });

    _syncNativeBackInterception();
  }

  void _openDetail(RodinScreen screen) {
    if (screen.isRoot) {
      _selectRoot(screen);
      return;
    }

    setState(() {
      if (_screen.isRoot) {
        _detailBackTarget = _screen;
      }
      _nestedDetailBackTarget = null;
      _screen = screen;
    });

    _syncNativeBackInterception();
  }

  // ignore: unused_element
  void _openNestedDetail(RodinScreen screen) {
    if (screen.isRoot || _screen.isRoot) {
      _openDetail(screen);
      return;
    }

    final RodinScreen parent = _screen;

    setState(() {
      _nestedDetailBackTarget = parent;
      _screen = screen;
    });

    _syncNativeBackInterception();
  }

  void _back() {
    if (RodinNestedBackController.handleBack()) {
      return;
    }

    final RodinScreen? nestedTarget = _nestedDetailBackTarget;

    if (nestedTarget != null && !_screen.isRoot) {
      setState(() {
        _screen = nestedTarget;
        _nestedDetailBackTarget = null;
      });

      _syncNativeBackInterception();
      return;
    }

    if (_screen.isRoot) {
      if (_screen != RodinScreen.home) {
        _selectRoot(RodinScreen.home);
      }
      return;
    }

    final RodinScreen target = _detailBackTarget;

    if (_rootController.hasClients) {
      _rootController.jumpToPage(_rootIndex(target));
    }

    setState(() {
      _screen = target;
      _nestedDetailBackTarget = null;
    });

    _syncNativeBackInterception();
  }

  @override
  void dispose() {
    RodinBackend.instance.setBackIntercept(false);
    _nativeBackPoll?.cancel();
    _nativeBackPoll = null;
    _rootController.dispose();
    _appearance.dispose();
    RodinInteractionSettings.revision.removeListener(
      _interactionRevisionListener,
    );

    super.dispose();
  }

  Widget _rootPage(RodinScreen screen) {
    switch (screen) {
      case RodinScreen.home:
        return HomeScreen(
          onOpen: _openDetail,
          onHubs: () => _selectRoot(RodinScreen.hubs),
          onSupport: () => _selectRoot(RodinScreen.support),
        );
      case RodinScreen.hubs:
        return HubsScreen(onOpen: _openDetail);
      case RodinScreen.support:
        return const SupportScreen();
      case RodinScreen.settings:
        return ValueListenableBuilder<RodinAppearanceConfig>(
          valueListenable: _appearance,
          builder:
              (
                BuildContext context,
                RodinAppearanceConfig config,
                Widget? child,
              ) {
                return SettingsScreen(
                  config: config,
                  onThemePreferenceChanged: _setThemePreference,
                  onBackgroundStyleChanged: _setBackgroundStyle,
                  onCustomBackgroundSelected: _setCustomBackgroundPath,
                  onBlurChanged: _setBackgroundBlur,
                  onBlurChangeEnd: _commitBackgroundBlur,
                  onHorizontalControlActive: _setRootSwipeLocked,
                  onResetAppearance: _resetAppearance,
                  onAccentChanged: _setAccentIndex,
                  onCardRadiusChanged: _setCardRadius,
                  onCardStyleChanged: _setCardStyle,
                  onHeroGlowChanged: _setHeroGlow,
                  onCoreVisualizerStyleChanged: _setCoreVisualizerStyle,
                );
              },
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _rootPager() {
    return PageView(
      controller: _rootController,
      physics: (_rootSwipeLocked || _rootNavAnimating)
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(parent: BouncingScrollPhysics()),
      onPageChanged: _onRootPageChanged,
      children: _rootOrder.map(_rootPage).toList(growable: false),
    );
  }

  Widget _detailBody(RodinScreen screen) {
    switch (screen) {
      case RodinScreen.charging:
        return ChargingScreen(onBack: _back);
      case RodinScreen.touchBoost:
        return TouchBoostScreen(onBack: _back);
      case RodinScreen.displayStudio:
        return DisplayStudioScreen(onBack: _back);
      case RodinScreen.perAppProfiles:
        return PerAppProfilesScreen(onBack: _back);
      case RodinScreen.cpuPerformance:
        return CpuPerformanceScreen(onBack: _back);
      case RodinScreen.advancedConfiguration:
        return AdvancedConfigurationScreen(onBack: _back);
      case RodinScreen.resolution:
        return ResolutionScreen(onBack: _back);
      case RodinScreen.diagnostics:
        return DiagnosticsScreen(onBack: _back);
      case RodinScreen.zramSwap:
        return ZramSwapScreen(onBack: _back);
      case RodinScreen.maliGpu:
        return MaliGpuScreen(onBack: _back);
      default:
        return _rootPager();
    }
  }

  @override
  Widget build(BuildContext context) {
    final RodinScreen current = _screen;
    final RodinScreen navRoot = _visualRoot();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<RodinAppearanceConfig>(
      valueListenable: _appearance,
      builder:
          (BuildContext context, RodinAppearanceConfig config, Widget? child) {
            return RodinAppearanceScope(
              config: config,
              child: PopScope(
                canPop: current == RodinScreen.home,
                onPopInvokedWithResult: (bool didPop, Object? result) {
                  if (!didPop && current != RodinScreen.home) {
                    _back();
                  }
                },
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  extendBody: true,
                  body: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _RodinBackgroundLayer(config: config),
                      SafeArea(
                        bottom: false,
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            _rootPager(),
                            AnimatedSwitcher(
                              duration: RodinInteractionSettings.motionDuration(
                                260,
                              ),
                              reverseDuration:
                                  RodinInteractionSettings.motionDuration(200),
                              switchInCurve:
                                  RodinInteractionSettings.transitionCurve,
                              switchOutCurve: Curves.easeInOutCubic,
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) {
                                    final Animation<Offset> slide =
                                        Tween<Offset>(
                                          begin: Offset(
                                            RodinInteractionSettings
                                                .detailSlideDistance,
                                            0,
                                          ),
                                          end: Offset.zero,
                                        ).animate(animation);
                                    final Animation<double>
                                    scale = Tween<double>(
                                      begin: RodinInteractionSettings.pageScale,
                                      end: 1,
                                    ).animate(animation);

                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: scale,
                                        child: SlideTransition(
                                          position: slide,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                              child: current.isRoot
                                  ? const SizedBox.shrink(
                                      key: ValueKey<String>(
                                        'no-detail-overlay',
                                      ),
                                    )
                                  : Container(
                                      key: ValueKey<RodinScreen>(current),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF090C11)
                                            : const Color(0xFFF3F6FA),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.50 : 0.12,
                                            ),
                                            blurRadius: 18,
                                            offset: const Offset(-4, 0),
                                          ),
                                        ],
                                      ),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: <Widget>[
                                          _RodinBackgroundLayer(config: config),
                                          _detailBody(current),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  bottomNavigationBar: RodinBottomBar(
                    controller: _rootController,
                    currentRoot: navRoot,
                    onSelect: _selectRoot,
                  ),
                ),
              ),
            );
          },
    );
  }
}

enum RodinBackgroundStyle { system, midnight, aurora, custom }

class RodinAppearanceConfig {
  const RodinAppearanceConfig({
    required this.themePreference,
    required this.backgroundStyle,
    required this.backgroundBlur,
    required this.customPath,
    this.accentIndex = 0,
    this.cardRadius = 22.0,
    this.cardStyle = 0,
    this.heroGlow = true,
    this.coreVisualizerStyle = 0,
  });

  const RodinAppearanceConfig.defaults()
    : themePreference = RodinThemePreference.system,
      backgroundStyle = RodinBackgroundStyle.system,
      backgroundBlur = 0,
      customPath = '',
      accentIndex = 0,
      cardRadius = 22.0,
      cardStyle = 0,
      heroGlow = true,
      coreVisualizerStyle = 0;

  final RodinThemePreference themePreference;
  final RodinBackgroundStyle backgroundStyle;
  final double backgroundBlur;
  final String customPath;
  final int accentIndex;
  final double cardRadius;
  final int cardStyle;
  final bool heroGlow;
  final int coreVisualizerStyle;

  static const List<Color> accents = <Color>[
    Color(0xFF59BCFF), // Electric Azure (Default)
    Color(0xFF00E5FF), // Neon Cyan
    Color(0xFF38E598), // Emerald Mint
    Color(0xFFB087FF), // Cyber Violet
    Color(0xFFFFA048), // Hyper Amber
    Color(0xFFFF5376), // Crimson Rose
    Color(0xFFD0D7DE), // Titanium Slate
  ];

  static const List<String> accentNames = <String>[
    'Azure',
    'Cyan',
    'Mint',
    'Violet',
    'Amber',
    'Rose',
    'Titanium',
  ];

  Color get activeAccent => accents[accentIndex.clamp(0, accents.length - 1)];

  RodinAppearanceConfig copyWith({
    RodinThemePreference? themePreference,
    RodinBackgroundStyle? backgroundStyle,
    double? backgroundBlur,
    String? customPath,
    int? accentIndex,
    double? cardRadius,
    int? cardStyle,
    bool? heroGlow,
    int? coreVisualizerStyle,
  }) {
    return RodinAppearanceConfig(
      themePreference: themePreference ?? this.themePreference,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      customPath: customPath ?? this.customPath,
      accentIndex: accentIndex ?? this.accentIndex,
      cardRadius: cardRadius ?? this.cardRadius,
      cardStyle: cardStyle ?? this.cardStyle,
      heroGlow: heroGlow ?? this.heroGlow,
      coreVisualizerStyle: coreVisualizerStyle ?? this.coreVisualizerStyle,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'themeMode': themePreference.name,
      'backgroundStyle': backgroundStyle.name,
      'backgroundBlur': backgroundBlur,
      'customPath': customPath,
      'accentIndex': accentIndex,
      'cardRadius': cardRadius,
      'cardStyle': cardStyle,
      'heroGlow': heroGlow,
      'coreVisualizerStyle': coreVisualizerStyle,
    };
  }

  static RodinAppearanceConfig fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const RodinAppearanceConfig.defaults();
    }

    final RodinThemePreference themePreference =
        RodinThemeController.preferenceFromName(raw['themeMode']?.toString());

    final String styleName = raw['backgroundStyle']?.toString() ?? 'system';

    final RodinBackgroundStyle style = RodinBackgroundStyle.values.firstWhere(
      (RodinBackgroundStyle value) => value.name == styleName,
      orElse: () => RodinBackgroundStyle.system,
    );

    final num? blurRaw = raw['backgroundBlur'] as num?;
    final double blur = (blurRaw?.toDouble() ?? 0).clamp(0.0, 28.0).toDouble();

    final int accentIndex = (raw['accentIndex'] as num?)?.toInt() ?? 0;
    final double cardRadius = (raw['cardRadius'] as num?)?.toDouble() ?? 22.0;
    final int cardStyle = (raw['cardStyle'] as num?)?.toInt() ?? 0;
    final bool heroGlow = raw['heroGlow'] as bool? ?? true;
    final int coreVisualizerStyle =
        (raw['coreVisualizerStyle'] as num?)?.toInt() ?? 0;

    return RodinAppearanceConfig(
      themePreference: themePreference,
      backgroundStyle: style,
      backgroundBlur: blur,
      customPath: raw['customPath']?.toString() ?? '',
      accentIndex: accentIndex,
      cardRadius: cardRadius,
      cardStyle: cardStyle,
      heroGlow: heroGlow,
      coreVisualizerStyle: coreVisualizerStyle,
    );
  }
}

class RodinAppearanceScope extends InheritedWidget {
  const RodinAppearanceScope({
    required this.config,
    required super.child,
    super.key,
  });

  final RodinAppearanceConfig config;

  static RodinAppearanceConfig of(BuildContext context) {
    final RodinAppearanceScope? scope = context
        .dependOnInheritedWidgetOfExactType<RodinAppearanceScope>();
    return scope?.config ?? const RodinAppearanceConfig.defaults();
  }

  @override
  bool updateShouldNotify(RodinAppearanceScope oldWidget) {
    return config != oldWidget.config;
  }
}

class _RodinBackgroundLayer extends StatelessWidget {
  const _RodinBackgroundLayer({required this.config});

  final RodinAppearanceConfig config;

  Widget _midnight(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    if (dark) {
      return const Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: Color(0xFF05080D)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.82, -0.88),
                radius: 1.08,
                colors: <Color>[
                  Color(0x2E3B82C6),
                  Color(0x141B416A),
                  Color(0x0005080D),
                ],
                stops: <double>[0, 0.47, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x00000000),
                  Color(0x08000000),
                  Color(0x26000000),
                ],
                stops: <double>[0, 0.58, 1],
              ),
            ),
          ),
        ],
      );
    }

    return const Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: Color(0xFFF3F6FA)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.78, -0.90),
              radius: 1.14,
              colors: <Color>[
                Color(0x244F8FC7),
                Color(0x10346D9F),
                Color(0x00F3F6FA),
              ],
              stops: <double>[0, 0.48, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0x00FFFFFF),
                Color(0x10FFFFFF),
                Color(0x2AEEF3F8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _aurora(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    if (dark) {
      return const Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: Color(0xFF060910)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.92, -0.82),
                radius: 1.20,
                colors: <Color>[
                  Color(0x383E87F5),
                  Color(0x162D5DA7),
                  Color(0x00060910),
                ],
                stops: <double>[0, 0.44, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.02, 0.72),
                radius: 1.12,
                colors: <Color>[
                  Color(0x2A35BE9F),
                  Color(0x12368783),
                  Color(0x00060910),
                ],
                stops: <double>[0, 0.43, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.68, -0.70),
                radius: 0.92,
                colors: <Color>[Color(0x1E8D65D8), Color(0x00060910)],
              ),
            ),
          ),
        ],
      );
    }

    return const Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: Color(0xFFF7F9FC)),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.92, -0.82),
              radius: 1.18,
              colors: <Color>[
                Color(0x2A579CF0),
                Color(0x105F8EC4),
                Color(0x00F7F9FC),
              ],
              stops: <double>[0, 0.46, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.0, 0.72),
              radius: 1.08,
              colors: <Color>[
                Color(0x2439BDA2),
                Color(0x0D65A995),
                Color(0x00F7F9FC),
              ],
              stops: <double>[0, 0.44, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.65, -0.72),
              radius: 0.88,
              colors: <Color>[Color(0x188B67D3), Color(0x00F7F9FC)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _custom(BuildContext context) {
    if (config.customPath.isEmpty) {
      return _aurora(context);
    }

    return Image.file(
      key: ValueKey<String>('rodin-custom-${config.customPath}'),
      File(config.customPath),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return _aurora(context);
          },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    Widget visual = dark
        ? const ColoredBox(color: Color(0xFF000000))
        : switch (config.backgroundStyle) {
            RodinBackgroundStyle.system => ColoredBox(
              color: theme.scaffoldBackgroundColor,
            ),
            RodinBackgroundStyle.midnight => _midnight(context),
            RodinBackgroundStyle.aurora => _aurora(context),
            RodinBackgroundStyle.custom => _custom(context),
          };

    if (!dark && config.backgroundBlur > 0.05) {
      visual = ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: config.backgroundBlur,
            sigmaY: config.backgroundBlur,
            tileMode: TileMode.clamp,
          ),
          child: Transform.scale(scale: 1.06, child: visual),
        ),
      );
    }

    final bool decorated =
        !dark && config.backgroundStyle != RodinBackgroundStyle.system;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        visual,
        if (decorated)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? <Color>[
                          colors.surface.withValues(alpha: 0.09),
                          Colors.transparent,
                          colors.surface.withValues(alpha: 0.16),
                        ]
                      : <Color>[
                          colors.surface.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.035),
                          colors.surface.withValues(alpha: 0.24),
                        ],
                  stops: const <double>[0, 0.52, 1],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.config,
    required this.onThemePreferenceChanged,
    required this.onBackgroundStyleChanged,
    required this.onCustomBackgroundSelected,
    required this.onBlurChanged,
    required this.onBlurChangeEnd,
    required this.onHorizontalControlActive,
    required this.onResetAppearance,
    required this.onAccentChanged,
    required this.onCardRadiusChanged,
    required this.onCardStyleChanged,
    required this.onHeroGlowChanged,
    required this.onCoreVisualizerStyleChanged,
    super.key,
  });

  final RodinAppearanceConfig config;
  final ValueChanged<RodinThemePreference> onThemePreferenceChanged;
  final ValueChanged<RodinBackgroundStyle> onBackgroundStyleChanged;
  final ValueChanged<String> onCustomBackgroundSelected;
  final ValueChanged<double> onBlurChanged;
  final ValueChanged<double> onBlurChangeEnd;
  final ValueChanged<bool> onHorizontalControlActive;
  final VoidCallback onResetAppearance;
  final ValueChanged<int> onAccentChanged;
  final ValueChanged<double> onCardRadiusChanged;
  final ValueChanged<int> onCardStyleChanged;
  final ValueChanged<bool> onHeroGlowChanged;
  final ValueChanged<int> onCoreVisualizerStyleChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _choosingPhoto = false;
  String? _photoMessage;

  Future<int> _ensurePhotoPermission() async {
    final RodinBackend backend = RodinBackend.instance;

    int state = backend.photoPermissionState();

    if (state > 0) {
      return state;
    }

    if (!backend.requestPhotoPermission()) {
      return 0;
    }

    for (int i = 0; i < 100; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));

      if (!mounted) {
        return 0;
      }

      state = backend.photoPermissionState();

      if (state > 0) {
        return state;
      }
    }

    return 0;
  }

  String _privateBackgroundPath(String selected) {
    final String lower = selected.toLowerCase();

    String extension = '.jpg';

    if (lower.endsWith('.png')) {
      extension = '.png';
    } else if (lower.endsWith('.webp')) {
      extension = '.webp';
    }

    final int nonce = DateTime.now().microsecondsSinceEpoch;

    return '${Directory.systemTemp.parent.path}'
        '/files/rodin-custom-background-'
        '$nonce$extension';
  }

  Future<void> _choosePhoto() async {
    if (_choosingPhoto) {
      return;
    }

    setState(() {
      _choosingPhoto = true;
      _photoMessage = null;
    });

    final int permissionState = await _ensurePhotoPermission();

    if (!mounted) {
      return;
    }

    if (permissionState <= 0) {
      setState(() {
        _choosingPhoto = false;
        _photoMessage =
            'Photo access was not granted. '
            'Rodin Essential keeps working '
            'normally without it.';
      });

      return;
    }

    final String? selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (BuildContext context) {
        return FractionallySizedBox(
          heightFactor: 0.91,
          child: _RodinGalleryBrowser(permissionState: permissionState),
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (selected == null) {
      setState(() {
        _choosingPhoto = false;
      });

      return;
    }

    try {
      final String destination = _privateBackgroundPath(selected);

      final File target = File(destination);

      await target.parent.create(recursive: true);

      await File(selected).copy(target.path);

      // Decode the new unique FileImage first so the shell swaps to an
      // already-ready provider. No restart and no stale same-path cache.
      await precacheImage(FileImage(target), context);

      if (!mounted) {
        return;
      }

      widget.onCustomBackgroundSelected(target.path);

      setState(() {
        _choosingPhoto = false;
        _photoMessage = 'Custom background applied';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _choosingPhoto = false;
        _photoMessage =
            'That image could not be '
            'applied.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final RodinAppearanceConfig config = widget.config;

    return RodinScrollPage(
      children: <Widget>[
        const RodinHeader(
          title: 'Settings',
          subtitle: 'Theme, elements, and UI customization',
          large: true,
        ),
        const SizedBox(height: 10),

        // 1. LIVE PREVIEW CARD
        const SectionLabel('Live preview'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: config.activeAccent,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: config.activeAccent.withValues(alpha: 0.8),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'ACTIVE STYLE PREVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: config.activeAccent,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: config.activeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: config.activeAccent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Text(
                      '${config.cardRadius.toInt()}px radius',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: config.activeAccent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  IconTile(
                    icon: Icons.palette_rounded,
                    accent: config.activeAccent,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Rodin Custom Surface',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${RodinAppearanceConfig.accentNames[config.accentIndex]} accent · ${switch (config.cardStyle) {
                            1 => 'Frosted Glass',
                            2 => 'Neon Ambient Edge',
                            3 => 'Minimal Slate',
                            _ => 'AMOLED Deep',
                          }}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. ACCENT COLOR STUDIO
        const SectionLabel('Accent color'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Signature color palette',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Changes primary highlights, toggles, badges, and card accents.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: <Widget>[
                  for (
                    int i = 0;
                    i < RodinAppearanceConfig.accents.length;
                    i++
                  ) ...<Widget>[
                    PressScale(
                      onTap: () {
                        widget.onAccentChanged(i);
                        RodinHaptics.tap();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: config.accentIndex == i
                              ? RodinAppearanceConfig.accents[i].withValues(
                                  alpha: 0.16,
                                )
                              : colors.surfaceContainer.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: config.accentIndex == i
                                ? RodinAppearanceConfig.accents[i]
                                : colors.outline.withValues(alpha: 0.22),
                            width: config.accentIndex == i ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: RodinAppearanceConfig.accents[i],
                                shape: BoxShape.circle,
                                boxShadow: config.accentIndex == i
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color: RodinAppearanceConfig
                                              .accents[i]
                                              .withValues(alpha: 0.6),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              RodinAppearanceConfig.accentNames[i],
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: config.accentIndex == i
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: config.accentIndex == i
                                    ? colors.onSurface
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. CARD & SURFACE ELEMENTS
        const SectionLabel('Card & surface elements'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Corner curvature',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust how rounded UI cards, tiles, and panels appear.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _RodinAppearanceChoice(
                    label: 'Sharp (10px)',
                    icon: Icons.square_outlined,
                    selected: (config.cardRadius - 10.0).abs() < 1.0,
                    onTap: () {
                      widget.onCardRadiusChanged(10.0);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Classic (16px)',
                    icon: Icons.rounded_corner_rounded,
                    selected: (config.cardRadius - 16.0).abs() < 1.0,
                    onTap: () {
                      widget.onCardRadiusChanged(16.0);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Squircle (22px)',
                    icon: Icons.crop_square_rounded,
                    selected: (config.cardRadius - 22.0).abs() < 1.0,
                    onTap: () {
                      widget.onCardRadiusChanged(22.0);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Pill (28px)',
                    icon: Icons.circle_outlined,
                    selected: (config.cardRadius - 28.0).abs() < 1.0,
                    onTap: () {
                      widget.onCardRadiusChanged(28.0);
                      RodinHaptics.tap();
                    },
                  ),
                ],
              ),
              const Divider(height: 22),
              const Text(
                'Surface visual style',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Select the material finish for cards across all screens.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _RodinAppearanceChoice(
                    label: 'AMOLED Deep',
                    icon: Icons.dark_mode_outlined,
                    selected: config.cardStyle == 0,
                    onTap: () {
                      widget.onCardStyleChanged(0);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Frosted Glass',
                    icon: Icons.blur_on_rounded,
                    selected: config.cardStyle == 1,
                    onTap: () {
                      widget.onCardStyleChanged(1);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Neon Edge',
                    icon: Icons.auto_awesome_outlined,
                    selected: config.cardStyle == 2,
                    onTap: () {
                      widget.onCardStyleChanged(2);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Minimal Slate',
                    icon: Icons.layers_outlined,
                    selected: config.cardStyle == 3,
                    onTap: () {
                      widget.onCardStyleChanged(3);
                      RodinHaptics.tap();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. VISUAL ELEMENTS & DASHBOARD
        const SectionLabel('Visual elements'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Device pulse ambient halo',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Display a glowing ambient halo behind the Home dashboard.',
                          style: TextStyle(
                            fontSize: 11.2,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: config.heroGlow,
                    onChanged: (bool enabled) {
                      widget.onHeroGlowChanged(enabled);
                      RodinHaptics.tap();
                    },
                  ),
                ],
              ),
              const Divider(height: 20),
              const Text(
                'CPU core visualizer style',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how processor cores are displayed on the Home hero.',
                style: TextStyle(
                  fontSize: 11.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _RodinAppearanceChoice(
                    label: 'Capsules',
                    icon: Icons.view_column_rounded,
                    selected: config.coreVisualizerStyle == 0,
                    onTap: () {
                      widget.onCoreVisualizerStyleChanged(0);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Neon Dots',
                    icon: Icons.radio_button_checked_rounded,
                    selected: config.coreVisualizerStyle == 1,
                    onTap: () {
                      widget.onCoreVisualizerStyleChanged(1);
                      RodinHaptics.tap();
                    },
                  ),
                  _RodinAppearanceChoice(
                    label: 'Energy Bar',
                    icon: Icons.horizontal_distribute_rounded,
                    selected: config.coreVisualizerStyle == 2,
                    onTap: () {
                      widget.onCoreVisualizerStyleChanged(2);
                      RodinHaptics.tap();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 5. THEME MODE
        const SectionLabel('Theme'),
        const SizedBox(height: 9),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'App theme',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Use Android automatically or force Rodin Essential to Light or pure AMOLED Black.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _RodinAppearanceChoice(
                    label: 'System',
                    icon: Icons.brightness_auto_rounded,
                    selected:
                        config.themePreference == RodinThemePreference.system,
                    onTap: () => widget.onThemePreferenceChanged(
                      RodinThemePreference.system,
                    ),
                  ),
                  _RodinAppearanceChoice(
                    label: 'Light',
                    icon: Icons.light_mode_rounded,
                    selected:
                        config.themePreference == RodinThemePreference.light,
                    onTap: () => widget.onThemePreferenceChanged(
                      RodinThemePreference.light,
                    ),
                  ),
                  _RodinAppearanceChoice(
                    label: 'AMOLED',
                    icon: Icons.dark_mode_rounded,
                    selected:
                        config.themePreference == RodinThemePreference.dark,
                    onTap: () => widget.onThemePreferenceChanged(
                      RodinThemePreference.dark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),

        // 6. INTERACTION & MOTION
        const SectionLabel('Interaction'),
        const SizedBox(height: 9),
        ValueListenableBuilder<int>(
          valueListenable: RodinInteractionSettings.revision,
          builder: (BuildContext context, int revision, Widget? child) {
            final ColorScheme colors = Theme.of(context).colorScheme;

            return SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.motion_photos_on_rounded,
                          color: colors.primary,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Motion feel',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              RodinInteractionSettings.motionLabel,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${RodinInteractionSettings.motionSpeed.toStringAsFixed(2)}×',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'One control now tunes navigation pace, easing, press depth, fades, and page movement across the whole app.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.28),
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: RodinInteractionSettings.motionDuration(300),
                      curve: RodinInteractionSettings.transitionCurve,
                      alignment: Alignment(
                        -1.0 + RodinInteractionSettings.motionProgress * 2.0,
                        0,
                      ),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.28),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  Slider(
                    min: 0.75,
                    max: 1.35,
                    divisions: 24,
                    value: RodinInteractionSettings.motionSpeed,
                    onChangeStart: (_) {
                      widget.onHorizontalControlActive(true);
                      RodinHaptics.segment();
                    },
                    onChanged: (double value) {
                      setState(() {
                        RodinInteractionSettings.previewMotionSpeed(value);
                      });
                      RodinHaptics.frequentSegment();
                    },
                    onChangeEnd: (double value) {
                      RodinInteractionSettings.commitMotionSpeed(value);
                      widget.onHorizontalControlActive(false);
                      RodinHaptics.confirm();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Relaxed',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Balanced',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Direct',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          RodinInteractionSettings.resetMotion();
                        });
                        RodinHaptics.confirm();
                      },
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: const Text('Reset to balanced'),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Divider(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Haptic feedback',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Android semantic feedback for taps, toggles, choices and sliders.',
                              style: TextStyle(
                                fontSize: 11.2,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: RodinInteractionSettings.hapticsEnabled,
                        onChanged: (bool enabled) {
                          if (!enabled) {
                            RodinHaptics.toggle(false);
                          }

                          RodinInteractionSettings.setHaptics(enabled);

                          if (enabled) {
                            RodinHaptics.confirm();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 13),

        // 7. APP BACKGROUND
        const SectionLabel('App background'),
        const SizedBox(height: 9),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Background style',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Midnight and Aurora now stay behind the controls instead of competing with them.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  _RodinAppearanceChoice(
                    label: 'System',
                    icon: Icons.phone_android_rounded,
                    selected:
                        config.backgroundStyle == RodinBackgroundStyle.system,
                    onTap: () => widget.onBackgroundStyleChanged(
                      RodinBackgroundStyle.system,
                    ),
                  ),
                  _RodinAppearanceChoice(
                    label: 'Midnight',
                    icon: Icons.nights_stay_rounded,
                    selected:
                        config.backgroundStyle == RodinBackgroundStyle.midnight,
                    onTap: () => widget.onBackgroundStyleChanged(
                      RodinBackgroundStyle.midnight,
                    ),
                  ),
                  _RodinAppearanceChoice(
                    label: 'Aurora',
                    icon: Icons.auto_awesome_rounded,
                    selected:
                        config.backgroundStyle == RodinBackgroundStyle.aurora,
                    onTap: () => widget.onBackgroundStyleChanged(
                      RodinBackgroundStyle.aurora,
                    ),
                  ),
                  _RodinAppearanceChoice(
                    label: _choosingPhoto ? 'Opening…' : 'Gallery',
                    icon: Icons.photo_library_rounded,
                    selected:
                        config.backgroundStyle == RodinBackgroundStyle.custom,
                    onTap: _choosePhoto,
                  ),
                ],
              ),
              if (_photoMessage != null) ...<Widget>[
                const SizedBox(height: 9),
                Text(
                  _photoMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 9),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Background blur',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    config.backgroundBlur < 0.5
                        ? 'Off'
                        : config.backgroundBlur.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Blur affects only the wallpaper. Cards, text and controls remain sharp.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              Slider(
                min: 0,
                max: 28,
                divisions: 28,
                value: config.backgroundBlur.clamp(0.0, 28.0).toDouble(),
                onChangeStart: (_) {
                  widget.onHorizontalControlActive(true);
                  RodinHaptics.segment();
                },
                onChanged: (double value) {
                  widget.onBlurChanged(value);
                  RodinHaptics.frequentSegment();
                },
                onChangeEnd: (double value) {
                  widget.onBlurChangeEnd(value);
                  widget.onHorizontalControlActive(false);
                  RodinHaptics.confirm();
                },
              ),
            ],
          ),
        ),
        if (config.customPath.isNotEmpty) ...<Widget>[
          const SizedBox(height: 9),
          SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: colors.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The selected image is copied into Rodin Essential private storage so it remains usable after photo permission changes.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.32,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 9),
        PressScale(
          onTap: widget.onResetAppearance,
          child: SurfaceCard(
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.restart_alt_rounded,
                  color: colors.secondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Reset all appearance settings',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RodinGalleryItem {
  const _RodinGalleryItem({required this.path, required this.modified});

  final String path;
  final DateTime modified;
}

class _RodinGalleryBrowser extends StatefulWidget {
  const _RodinGalleryBrowser({required this.permissionState});

  final int permissionState;

  @override
  State<_RodinGalleryBrowser> createState() => _RodinGalleryBrowserState();
}

class _RodinGalleryBrowserState extends State<_RodinGalleryBrowser> {
  static const int _maxItems = 360;

  static const List<String> _roots = <String>[
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Pictures',
    '/storage/emulated/0/Download',
  ];

  bool _loading = true;
  String? _error;
  List<_RodinGalleryItem> _items = const <_RodinGalleryItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _supported(String path) {
    final String lower = path.toLowerCase();

    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  Future<bool> _readable(File file) async {
    try {
      final RandomAccessFile handle = await file.open(mode: FileMode.read);
      await handle.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    final List<_RodinGalleryItem> result = <_RodinGalleryItem>[];
    final Set<String> seen = <String>{};

    try {
      for (final String rootPath in _roots) {
        if (result.length >= _maxItems) {
          break;
        }

        final Directory root = Directory(rootPath);

        if (!await root.exists()) {
          continue;
        }

        try {
          await for (final FileSystemEntity entity in root.list(
            recursive: true,
            followLinks: false,
          )) {
            if (result.length >= _maxItems) {
              break;
            }

            if (entity is! File) {
              continue;
            }

            final String path = entity.path;

            if (!_supported(path) || !seen.add(path)) {
              continue;
            }

            if (!await _readable(entity)) {
              continue;
            }

            DateTime modified;

            try {
              modified = await entity.lastModified();
            } catch (_) {
              modified = DateTime.fromMillisecondsSinceEpoch(0);
            }

            result.add(_RodinGalleryItem(path: path, modified: modified));
          }
        } catch (_) {}
      }

      result.sort(
        (_RodinGalleryItem a, _RodinGalleryItem b) =>
            b.modified.compareTo(a.modified),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = result;
        _loading = false;

        if (result.isEmpty) {
          _error = widget.permissionState == 1
              ? 'Android granted selected-photo '
                    'access, but no readable JPG, '
                    'PNG or WebP files were exposed '
                    'through the shared media paths.'
              : 'No readable JPG, PNG or WebP '
                    'images were found in DCIM, '
                    'Pictures or Download.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'Unable to read the shared media library.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 9),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outline.withValues(alpha: 0.52),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Choose background',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.permissionState == 1
                              ? 'Selected-photo access'
                              : 'Photos on this device',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.34)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(3),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 3,
                            mainAxisSpacing: 3,
                          ),
                      itemCount: _items.length,
                      itemBuilder: (BuildContext context, int index) {
                        final _RodinGalleryItem item = _items[index];

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.of(context).pop(item.path);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              File(item.path),
                              fit: BoxFit.cover,
                              cacheWidth: 360,
                              filterQuality: FilterQuality.low,
                              gaplessPlayback: true,
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? stack,
                                  ) {
                                    return ColoredBox(
                                      color: colors.surfaceContainer,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    );
                                  },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RodinAppearanceChoice extends StatelessWidget {
  const _RodinAppearanceChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: dark ? 0.17 : 0.12)
              : colors.surfaceContainer.withValues(alpha: dark ? 0.92 : 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.32)
                : colors.outline.withValues(alpha: dark ? 0.62 : 0.72),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onOpen,
    required this.onHubs,
    required this.onSupport,
    super.key,
  });

  final ValueChanged<RodinScreen> onOpen;
  final VoidCallback onHubs;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    return RodinScrollPage(
      children: <Widget>[
        const RodinHeader(
          title: 'Rodin Essential',
          subtitle: 'Your device, beautifully simplified',
          large: true,
        ),
        const SizedBox(height: 10),
        const LiveDashboardHero(),
        const SizedBox(height: 16),
        const SectionLabel('At a glance'),
        const SizedBox(height: 9),
        _LiveOverviewGrid(onOpen: onOpen),
        const SizedBox(height: 16),
        _ControlCenterPortal(onTap: onHubs),
        const SizedBox(height: 16),
        const SectionLabel('Explore'),
        const SizedBox(height: 9),
        Row(
          children: <Widget>[
            Expanded(
              child: _ExploreCard(
                title: 'ZRAM Swap',
                subtitle: 'Memory compression & swap',
                icon: Icons.storage_rounded,
                accent: const Color(0xFF67C2FF),
                onTap: () => onOpen(RodinScreen.zramSwap),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ExploreCard(
                title: 'Diagnostics',
                subtitle: 'Check device health',
                icon: Icons.monitor_heart_rounded,
                accent: const Color(0xFF74E6C6),
                onTap: () => onOpen(RodinScreen.diagnostics),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: <Widget>[
            Expanded(
              child: _ExploreCard(
                title: 'Resolution',
                subtitle: 'Screen sizing tools',
                icon: Icons.aspect_ratio_rounded,
                accent: const Color(0xFFFFBE63),
                onTap: () => onOpen(RodinScreen.resolution),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _ExploreCard(
                title: 'Community',
                subtitle: 'Project & support',
                icon: Icons.forum_outlined,
                accent: const Color(0xFF67C2FF),
                onTap: onSupport,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _DisclaimerCard(),
      ],
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF141416).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFB84D).withValues(alpha: 0.22),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB84D).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: Color(0xFFFFB84D),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Kernel & Hardware Disclaimer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Direct native hardware parameter tuning',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFB84D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Rodin Essential provides direct kernel hardware tuning, MediaTek Mali GPU frequency locks, independent CPU frequency and topology control, and AIDL display calibrations via native ROM system interfaces. GPU modes never change CPU settings. Gaming Dynamic and Extreme Beast intentionally override only the vendor GPU cooling cap; sustained high clocks can cause severe heat, battery drain, instability, or hardware damage.',
            style: TextStyle(
              fontSize: 11.2,
              height: 1.45,
              color: colors.onSurfaceVariant.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveOverviewGrid extends StatelessWidget {
  const _LiveOverviewGrid({required this.onOpen});

  final ValueChanged<RodinScreen> onOpen;

  @override
  Widget build(BuildContext context) {
    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int onlineCores = _rodinOnlineCoreCount(snapshot);

        final String battery = snapshot.batteryCapacity >= 0
            ? '${snapshot.batteryCapacity}%'
            : '—';
        final String temperature = snapshot.batteryTempC == null
            ? '—'
            : '${snapshot.batteryTempC!.toStringAsFixed(1)}°C';

        final String coreValue = snapshot.ready ? '$onlineCores / 8' : '—';
        final String coreSubtitle = backend.extendedValue(34) == 1
            ? 'Manual control'
            : 'Auto balance';

        final String display = switch (snapshot.displayColor) {
          0 => 'Original PRO',
          1 => 'Vivid',
          2 => 'Saturated',
          _ => 'Vivid',
        };

        final String touch = switch (snapshot.touchState) {
          1 => '250 Hz',
          2 => '500 Hz',
          3 => '1000 Hz',
          _ => '250 Hz',
        };

        final int zramDiskMb = backend.extendedValue(39) > 0
            ? backend.extendedValue(39)
            : 8192;
        final int zramUsedMb = backend.extendedValue(42) >= 0
            ? backend.extendedValue(42)
            : 0;
        final int zramAlgCode = backend.extendedValue(44);
        final String zramAlg = switch (zramAlgCode) {
          1 => 'ZSTD',
          2 => 'LZO-RLE',
          3 => 'LZO',
          _ => 'LZ4',
        };

        final String memoryVal = '${(zramDiskMb / 1024).toStringAsFixed(1)} GB';
        final String memorySub = zramUsedMb > 0
            ? '${zramUsedMb}M used · $zramAlg'
            : 'ZRAM Pool · $zramAlg';

        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _OverviewCard(
                    eyebrow: 'POWER',
                    value: battery,
                    subtitle: temperature,
                    icon: Icons.bolt_rounded,
                    accent: const Color(0xFF41C98A),
                    onTap: () => onOpen(RodinScreen.charging),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _OverviewCard(
                    eyebrow: 'CPU',
                    value: coreValue,
                    subtitle: coreSubtitle,
                    icon: Icons.memory_rounded,
                    accent: const Color(0xFF67C2FF),
                    onTap: () => onOpen(RodinScreen.cpuPerformance),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                Expanded(
                  child: _OverviewCard(
                    eyebrow: 'DISPLAY',
                    value: display,
                    subtitle: touch,
                    icon: Icons.auto_awesome_rounded,
                    accent: const Color(0xFFB087FF),
                    onTap: () => onOpen(RodinScreen.displayStudio),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _OverviewCard(
                    eyebrow: 'MEMORY',
                    value: memoryVal,
                    subtitle: memorySub,
                    icon: Icons.layers_rounded,
                    accent: const Color(0xFFFFB84D),
                    onTap: () => onOpen(RodinScreen.zramSwap),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.eyebrow,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String eyebrow;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    final Widget card = SurfaceCard(
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 126),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.12 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(alpha: dark ? 0.28 : 0.18),
                  ),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        eyebrow,
                        style: TextStyle(
                          fontSize: 9.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 8.5,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.8,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap != null) {
      return PressScale(onTap: onTap!, child: card);
    }

    return card;
  }
}

class _ControlCenterPortal extends StatelessWidget {
  const _ControlCenterPortal({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = colors.primary;

    return PressScale(
      onTap: onTap,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 15, 13, 15),
        child: Row(
          children: <Widget>[
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: dark ? 0.12 : 0.09),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: accent.withValues(alpha: dark ? 0.28 : 0.18),
                ),
              ),
              child: Icon(Icons.tune_rounded, color: accent, size: 25),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Tune your device',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.25,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'CONTROL HUBS',
                          style: TextStyle(
                            fontSize: 8.2,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Every performance and hardware control in one place',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.8,
                      height: 1.25,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: onTap,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 11, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: dark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: accent.withValues(alpha: dark ? 0.25 : 0.16),
                        ),
                      ),
                      child: Icon(icon, size: 19, color: accent),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.north_east_rounded,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.4,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _rodinOnlineCoreCount(RodinBackendSnapshot snapshot) {
  int count = 0;

  for (int cpu = 0; cpu < 8; cpu += 1) {
    if (snapshot.cpuOnline(cpu)) {
      count += 1;
    }
  }

  return count;
}

String _rodinPerformanceLabel(int profile) {
  return switch (profile) {
    0 => 'Stock Balanced',
    1 => 'Gaming Dynamic',
    2 => 'Battery Saver',
    3 => 'Extreme Beast',
    _ => 'Stock Balanced',
  };
}

class HubsScreen extends StatelessWidget {
  const HubsScreen({required this.onOpen, super.key});

  final ValueChanged<RodinScreen> onOpen;

  static const List<_HubSpec> hubs = <_HubSpec>[
    _HubSpec(
      RodinScreen.charging,
      'Charging',
      'Fast charging & power stats',
      Icons.battery_charging_full_rounded,
      Color(0xFF41C98A),
    ),
    _HubSpec(
      RodinScreen.touchBoost,
      'Touch Response',
      '250 default · 500 native · 1000 output',
      Icons.bolt_rounded,
      Color(0xFF41C98A),
    ),
    _HubSpec(
      RodinScreen.displayStudio,
      'Display Studio',
      'Color calibration & HDR tuning',
      Icons.palette_rounded,
      Color(0xFF67C2FF),
    ),
    _HubSpec(
      RodinScreen.cpuPerformance,
      'CPU Performance',
      'Clock ranges, locks & core control',
      Icons.memory_rounded,
      Color(0xFF67C2FF),
    ),
    _HubSpec(
      RodinScreen.advancedConfiguration,
      'Advanced Configuration',
      'Governors & device tuning',
      Icons.tune_rounded,
      Color(0xFFFFB84D),
    ),
    _HubSpec(
      RodinScreen.resolution,
      'Resolution',
      'Display panel specifications',
      Icons.grid_view_rounded,
      Color(0xFFFFBE63),
    ),
    _HubSpec(
      RodinScreen.zramSwap,
      'ZRAM & Swap Manager',
      'Memory compression, swap size & algorithm',
      Icons.storage_rounded,
      Color(0xFF67C2FF),
    ),
    _HubSpec(
      RodinScreen.maliGpu,
      'MediaTek Mali GPU & GED',
      'Hardware 1.30 GHz target, GED turbo & live clock tuning',
      Icons.sports_esports_rounded,
      Color(0xFFFF5252),
    ),
    _HubSpec(
      RodinScreen.diagnostics,
      'Diagnostics',
      'Hardware health & sensors',
      Icons.monitor_heart_rounded,
      Color(0xFF74E6C6),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final String battery = snapshot.batteryCapacity >= 0
            ? '${snapshot.batteryCapacity}%'
            : '—';
        final int onlineCores = _rodinOnlineCoreCount(snapshot);
        final String cores = snapshot.ready ? '$onlineCores / 8' : '—';
        final int liveGpuFreq = backend.extendedValue(46) >= 0
            ? backend.extendedValue(46)
            : 0;
        final int rawMinFreq = backend.extendedValue(47) >= 0
            ? backend.extendedValue(47)
            : 260;
        final int rawMaxFreq = backend.extendedValue(48) >= 0
            ? backend.extendedValue(48)
            : 1300;
        final int rawUncap = backend.extendedValue(52);
        final int activePerf = snapshot.performanceProfile >= 0
            ? snapshot.performanceProfile
            : (backend.extendedValue(19) == 1 && backend.extendedValue(20) >= 0
                  ? backend.extendedValue(20)
                  : 0);

        final bool isBeast =
            (rawUncap == 1 && rawMinFreq == 1300 && rawMaxFreq == 1300) ||
            activePerf == 3;
        final String gpuLabel = liveGpuFreq >= 260
            ? '$liveGpuFreq MHz'
            : (isBeast ? '1300 MHz target' : '$rawMaxFreq MHz');

        final Color gpuAccent = isBeast
            ? const Color(0xFFFF5252)
            : (activePerf == 1 || backend.extendedValue(50) == 1
                  ? const Color(0xFFFFB84D)
                  : (activePerf == 2 || rawMaxFreq <= 598
                        ? const Color(0xFF35C997)
                        : const Color(0xFF4EA8DE)));

        return RodinScrollPage(
          children: <Widget>[
            const RodinHeader(
              title: 'Control Hubs',
              subtitle: 'Hardware tools and tuning controls',
            ),
            const SizedBox(height: 9),
            Row(
              children: <Widget>[
                Expanded(
                  child: SummaryChip(
                    title: 'Battery',
                    subtitle: battery,
                    accent: const Color(0xFF41C98A),
                    onTap: () => onOpen(RodinScreen.charging),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryChip(
                    title: 'CPU',
                    subtitle: cores,
                    accent: const Color(0xFF67C2FF),
                    onTap: () => onOpen(RodinScreen.cpuPerformance),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryChip(
                    title: 'Mali GPU',
                    subtitle: gpuLabel,
                    accent: gpuAccent,
                    onTap: () => onOpen(RodinScreen.maliGpu),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            for (final _HubSpec item in hubs) ...<Widget>[
              FeatureCard(
                title: item.title,
                subtitle: item.subtitle,
                icon: item.icon,
                accent: item.accent,
                onTap: () => onOpen(item.screen),
              ),
              const SizedBox(height: 9),
            ],
          ],
        );
      },
    );
  }
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  void _openLink(int code) {
    RodinHaptics.confirm();
    RodinBackend.instance.openSupportLink(code);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return RodinScrollPage(
      topPadding: 16,
      children: <Widget>[
        // Hero Header Card with Redesigned Flagship OEM Logo
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  _RodinAppEmblem(size: 60, color: colors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text(
                              'Rodin Essential',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF41C98A,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFF41C98A,
                                  ).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF41C98A),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'ROM NATIVE',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF41C98A),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Built-in System Performance Studio',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: <Widget>[
                            StatusPill(
                              label: 'v1.18.0',
                              accent: colors.primary,
                            ),
                            StatusPill(
                              label: 'Zero-DEX AOT',
                              accent: colors.secondary,
                            ),
                            const StatusPill(
                              label: '16KB Page',
                              accent: Color(0xFF41C98A),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer.withValues(
                    alpha: dark ? 0.35 : 0.45,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.outline.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.bolt_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Engineered exclusively for Dimensity 8400-Ultra (MT6899 / rodin)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const SectionLabel('Official Community & Source'),
        const SizedBox(height: 8),

        // GitHub Card
        _CommunityCard(
          title: 'GitHub Repository',
          subtitle: 'Star, fork, and inspect the open-source code',
          badge: 'NEESCHAL-3',
          iconWidget: GithubIcon(color: colors.primary, size: 22),
          accent: colors.primary,
          onTap: () => _openLink(0),
        ),
        const SizedBox(height: 8),

        // Telegram Card
        _CommunityCard(
          title: 'Telegram Community',
          subtitle: 'Join device discussions, chat & get instant support',
          badge: '@PocoX7ProNepalChat',
          iconWidget: const Icon(
            Icons.send_rounded,
            size: 20,
            color: Color(0xFF26A5E4),
          ),
          accent: const Color(0xFF26A5E4),
          onTap: () => _openLink(1),
        ),

        const SizedBox(height: 16),
        const SectionLabel('System Integration Architecture'),
        const SizedBox(height: 8),

        const _DisclaimerCard(),

        const SizedBox(height: 20),

        // Sleek Developer / Community Footer
        Center(
          child: Column(
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Crafted for the community by ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'NEESCHAL',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Built-in System Component for Rodin ROMs • Zero Telemetry',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _RodinAppEmblem extends StatelessWidget {
  const _RodinAppEmblem({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0066FF).withValues(alpha: 0.28),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset(
          'assets/app_icon.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.iconWidget,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Widget iconWidget;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: onTap,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accent.withValues(alpha: 0.18),
                    accent.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.20)),
              ),
              alignment: Alignment.center,
              child: iconWidget,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5.5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.arrow_outward_rounded, size: 14, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

class ChargingScreen extends StatefulWidget {
  const ChargingScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends State<ChargingScreen> {
  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RodinBackendSnapshot>(
      stream: RodinBackend.instance.snapshots,
      initialData: RodinBackend.instance.latest,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<RodinBackendSnapshot> asyncSnapshot,
          ) {
            final RodinBackendSnapshot snapshot =
                asyncSnapshot.data ?? RodinBackend.instance.latest;

            return RodinScrollPage(
              children: <Widget>[
                DetailHeader(
                  title: 'Battery & Charging',
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 3),
                Text(
                  'Fast charging controls and live power status',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                _ChargingBatteryCard(snapshot: snapshot),
                const SizedBox(height: 9),
                _ChargingModeCard(snapshot: snapshot),
              ],
            );
          },
    );
  }
}

class _ChargingBatteryCard extends StatelessWidget {
  const _ChargingBatteryCard({required this.snapshot});

  final RodinBackendSnapshot snapshot;

  static const Color accent = Color(0xFF35C997);

  String _capacity() =>
      snapshot.batteryCapacity >= 0 ? '${snapshot.batteryCapacity}%' : '—';

  String _temperature() {
    final double? value = snapshot.batteryTempC;
    return value == null ? '—' : '${value.toStringAsFixed(1)}°C';
  }

  String _voltage() {
    final double? value = snapshot.batteryVoltageV;
    return value == null ? '—' : '${value.toStringAsFixed(2)} V';
  }

  String _current() {
    final double? value = snapshot.batteryCurrentA;
    return value == null ? '—' : '${value.toStringAsFixed(2)} A';
  }

  String _wattage() {
    final double? v = snapshot.batteryVoltageV;
    final double? a = snapshot.batteryCurrentA;
    if (v == null || a == null || v <= 0 || a <= 0) return '—';
    return '${(v * a).toStringAsFixed(1)} W';
  }

  String _status() {
    switch (snapshot.batteryStatus) {
      case 1:
        return 'Charging';
      case 2:
        return 'Discharging';
      case 3:
        return 'Not charging';
      case 4:
        return 'Full';
      case 0:
        return 'Unknown';
      default:
        return 'Unavailable';
    }
  }

  String _health() {
    switch (snapshot.batteryHealth) {
      case 1:
        return 'Good health';
      case 2:
        return 'Overheat';
      case 3:
        return 'Dead';
      case 4:
        return 'Over voltage';
      case 5:
        return 'Cold';
      case 0:
        return 'Unknown';
      default:
        return 'Unavailable';
    }
  }

  Color _tempColor() {
    final double? t = snapshot.batteryTempC;
    if (t == null) return const Color(0xFF67C2FF);
    if (t >= 44.0) return const Color(0xFFFF453A);
    if (t >= 38.0) return const Color(0xFFFFB84D);
    return const Color(0xFF41C98A);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isCharging = snapshot.batteryStatus == 1;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color:
                      (isCharging
                              ? const Color(0xFF35C997)
                              : const Color(0xFF4EA8DE))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        (isCharging
                                ? const Color(0xFF35C997)
                                : const Color(0xFF4EA8DE))
                            .withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  isCharging ? Icons.bolt_rounded : Icons.battery_5_bar_rounded,
                  color: isCharging
                      ? const Color(0xFF35C997)
                      : const Color(0xFF4EA8DE),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          _capacity(),
                          style: const TextStyle(
                            fontSize: 26,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (isCharging) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF35C997,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: const Color(
                                  0xFF35C997,
                                ).withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Text(
                              'CHARGING',
                              style: TextStyle(
                                fontSize: 8.8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                color: Color(0xFF35C997),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_status()} · ${_health()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ChargingStatePill(
                label: snapshot.ready ? 'LIVE' : 'OFFLINE',
                accent: snapshot.ready ? accent : colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.22)),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _ChargingMetric(
                  label: 'Temperature',
                  value: _temperature(),
                  icon: Icons.thermostat_rounded,
                  accentColor: _tempColor(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChargingMetric(
                  label: 'Power Flow',
                  value: _wattage(),
                  icon: Icons.bolt_rounded,
                  accentColor: const Color(0xFFFFB84D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _ChargingMetric(
                  label: 'Voltage',
                  value: _voltage(),
                  icon: Icons.electric_bolt_rounded,
                  accentColor: const Color(0xFF67C2FF),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChargingMetric(
                  label: 'Current',
                  value: _current(),
                  icon: Icons.speed_rounded,
                  accentColor: const Color(0xFFB087FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChargingMetric extends StatelessWidget {
  const _ChargingMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color color = accentColor ?? colors.primary;

    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colors.outline.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargingModeCard extends StatelessWidget {
  const _ChargingModeCard({required this.snapshot});

  final RodinBackendSnapshot snapshot;

  static const Color accent = Color(0xFF35C997);

  String _modeName() {
    switch (snapshot.chargingMode) {
      case 8:
        return 'Boost';
      case 0:
        return 'Standard';
      default:
        return 'Unavailable';
    }
  }

  String _detail() {
    if (!snapshot.ready) {
      return 'Privileged charging backend unavailable';
    }

    switch (snapshot.chargingWriteState) {
      case 1:
        return 'Applying charging mode…';
      case 2:
        return 'Charging mode applied';
      case -1:
        return 'Could not apply charging mode';
      default:
        return snapshot.chargingBoost
            ? 'Faster charging mode is active'
            : 'Standard charging mode is active';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool busy = snapshot.chargingWriteState == 1;
    final bool canWrite = snapshot.ready && snapshot.chargingMode >= 0 && !busy;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.bolt_rounded, size: 22, color: accent),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Charging boost',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _detail(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: snapshot.chargingBoost,
                onChanged: RodinHaptics.toggleCallback(
                  canWrite
                      ? (bool enabled) {
                          final bool queued = RodinBackend.instance
                              .setChargingBoost(enabled);
                          if (!queued) {
                            RodinBackend.instance.refresh();
                          }
                        }
                      : null,
                ),
                activeThumbColor: accent,
                activeTrackColor: accent.withValues(alpha: 0.35),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surfaceContainer.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outline.withValues(alpha: 0.38)),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  'Mode',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (busy) ...<Widget>[
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  _modeName(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargingStatePill extends StatelessWidget {
  const _ChargingStatePill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class TouchBoostScreen extends StatefulWidget {
  const TouchBoostScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<TouchBoostScreen> createState() => _TouchBoostScreenState();
}

class _TouchBoostScreenState extends State<TouchBoostScreen> {
  int? _pendingProfile;
  Timer? _pendingTimer;

  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  bool _selectProfile(int profile) {
    final bool accepted = RodinBackend.instance.setTouchProfile(profile);
    if (!accepted) {
      return false;
    }

    setState(() => _pendingProfile = profile);
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      setState(() => _pendingProfile = null);
      RodinBackend.instance.refresh();
    });
    return true;
  }

  String _profileTitle(int profile) => switch (profile) {
    1 => '250 Hz Mode',
    2 => '500 Hz Mode',
    3 => '1000 Hz Output',
    _ => '250 Hz Mode',
  };

  String _profileRate(int profile) => switch (profile) {
    1 => '240 Hz native timing · simple testers display about 250',
    2 => '480 Hz native timing · simple testers display about 500',
    3 => 'Precise 1 ms Android output · native source remains 480 Hz',
    _ => '240 Hz native timing · simple testers display about 250',
  };

  Color _profileAccent(int profile) => switch (profile) {
    1 => const Color(0xFFFFB84D),
    2 => const Color(0xFFFF6B57),
    3 => const Color(0xFFE95CFF),
    _ => const Color(0xFFFFB84D),
  };

  IconData _profileIcon(int profile) => switch (profile) {
    1 => Icons.sports_esports_rounded,
    2 => Icons.speed_rounded,
    3 => Icons.whatshot_rounded,
    _ => Icons.sports_esports_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int dt2w = RodinBackend.instance.extendedValue(1);
        final int savedProfile =
            (1 <= snapshot.touchState && snapshot.touchState <= 3)
            ? snapshot.touchState
            : 1;
        final int activeProfile = _pendingProfile ?? savedProfile;
        final Color accent = _profileAccent(activeProfile);
        final int touchAck = backend.extendedValue(29);
        final int panelCode = backend.extendedValue(62);
        final int controlPath = backend.extendedValue(63);
        final String panel = switch (panelCode) {
          1 => 'Goodix GT9916',
          2 => 'FocalTech',
          _ => 'Rodin auto-detect',
        };
        final String engine = switch (controlPath) {
          1 => 'Vendor HAL',
          2 => 'Direct driver fallback',
          3 => 'Rodin 1 ms output scheduler',
          _ => snapshot.touchHal == 1 ? 'Vendor HAL ready' : 'Unavailable',
        };
        final bool applying =
            _pendingProfile != null && snapshot.touchState != _pendingProfile;
        final bool controlsEnabled =
            snapshot.ready && snapshot.touchHal == 1 && !snapshot.busy;

        return RodinScrollPage(
          children: <Widget>[
            DetailHeader(title: 'Touch Response', onBack: widget.onBack),
            const SizedBox(height: 4),
            Text(
              'Only 250, 500, and 1000 — 250 is the default',
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            HeroCard(
              icon: _profileIcon(activeProfile),
              accent: accent,
              title: _profileTitle(activeProfile),
              subtitle: snapshot.touchHal == 1
                  ? '${_profileRate(activeProfile)} · $panel · $engine'
                  : 'Rodin touch engine unavailable on this vendor stack',
            ),
            const SizedBox(height: 12),
            _TouchProfileGrid(
              selectedProfile: activeProfile,
              enabled: controlsEnabled,
              onSelected: _selectProfile,
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              accent: accent,
              child: Row(
                children: <Widget>[
                  IconTile(
                    icon: !applying && touchAck == 1
                        ? Icons.verified_rounded
                        : Icons.sync_rounded,
                    accent: !applying && touchAck == 1
                        ? const Color(0xFF41C98A)
                        : const Color(0xFFFFB84D),
                    size: 44,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          !applying && touchAck == 1
                              ? 'Profile persisted'
                              : 'Applying touch pipeline',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          !applying && touchAck == 1
                              ? 'Reasserted after boot, screen wake, and vendor resets'
                              : 'Waiting for the panel HAL to confirm every required mode',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.25,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SwitchCard(
              icon: Icons.wb_twilight_rounded,
              accent: const Color(0xFF67C2FF),
              title: 'Double tap to wake',
              subtitle: 'Double-tap the screen when locked to wake up',
              value: dt2w == 1,
              enabled: controlsEnabled,
              stateKnown: true,
              onChanged: RodinBackend.instance.setDoubleTapWake,
            ),
            const SizedBox(height: 12),
            const SurfaceCard(
              child: _InfoBlock(
                title: 'Tester values',
                text:
                    '250 uses the native 240 Hz panel target and 500 uses the native 480 Hz target; simple tester apps round those values to about 250 and 500. The 1000 option delivers a one-millisecond Android event stream from the 480 Hz native source. No Adaptive mode or instant-boost mode is applied.',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TouchProfileGrid extends StatelessWidget {
  const _TouchProfileGrid({
    required this.selectedProfile,
    required this.enabled,
    required this.onSelected,
  });

  final int selectedProfile;
  final bool enabled;
  final bool Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'TOUCH MODES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.65,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: <Widget>[
            Expanded(
              child: _TouchProfileTile(
                profile: 1,
                title: '250 Hz',
                rate: '240 Hz native target',
                detail: 'Tester display ≈250',
                icon: Icons.sports_esports_rounded,
                accent: const Color(0xFFFFB84D),
                selected: selectedProfile == 1,
                enabled: enabled,
                onSelected: onSelected,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TouchProfileTile(
                profile: 2,
                title: '500 Hz',
                rate: '480 Hz native target',
                detail: 'Tester display ≈500',
                icon: Icons.speed_rounded,
                accent: const Color(0xFFFF6B57),
                selected: selectedProfile == 2,
                enabled: enabled,
                onSelected: onSelected,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _TouchProfileTile(
          profile: 3,
          title: '1000 Hz',
          rate: '1 ms Android event output',
          detail: 'Resampled from the native 480 Hz source',
          icon: Icons.whatshot_rounded,
          accent: const Color(0xFFE95CFF),
          selected: selectedProfile == 3,
          enabled: enabled,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

class _TouchProfileTile extends StatelessWidget {
  const _TouchProfileTile({
    required this.profile,
    required this.title,
    required this.rate,
    required this.detail,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final int profile;
  final String title;
  final String rate;
  final String detail;
  final IconData icon;
  final Color accent;
  final bool selected;
  final bool enabled;
  final bool Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled && !selected
            ? () {
                final bool accepted = onSelected(profile);
                if (accepted) {
                  RodinHaptics.segment();
                } else {
                  RodinHaptics.reject();
                }
              }
            : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(13),
          constraints: const BoxConstraints(minHeight: 132),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: dark ? 0.15 : 0.10)
                : (dark ? const Color(0xFF151A24) : const Color(0xFFF4F7FA)),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.88)
                  : colors.outline.withValues(alpha: 0.38),
              width: selected ? 1.6 : 1.0,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.10),
                      blurRadius: 16,
                      spreadRadius: -4,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: selected ? 0.20 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: accent),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? accent : colors.onSurfaceVariant,
                        width: selected ? 5.5 : 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                rate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.2,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.4,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RodinNestedBackController {
  const RodinNestedBackController._();

  static Object? _owner;
  static bool Function()? _handler;

  static void attach(Object owner, bool Function() handler) {
    _owner = owner;
    _handler = handler;
  }

  static void detach(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }

    _owner = null;
    _handler = null;
  }

  static bool handleBack() {
    final bool Function()? handler = _handler;

    if (handler == null) {
      return false;
    }

    return handler();
  }
}

class DisplayStudioScreen extends StatefulWidget {
  const DisplayStudioScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<DisplayStudioScreen> createState() => _DisplayStudioScreenState();
}

class _DisplayStudioScreenState extends State<DisplayStudioScreen> {
  bool _showColourModes = false;
  bool _colourTransitionForward = true;

  @override
  void initState() {
    super.initState();

    RodinNestedBackController.attach(this, _consumeNestedBack);

    RodinBackend.instance.refresh();
  }

  @override
  void dispose() {
    RodinNestedBackController.detach(this);
    super.dispose();
  }

  bool _consumeNestedBack() {
    if (!_showColourModes) {
      return false;
    }

    _closeColourModes();
    return true;
  }

  void _openColourModes() {
    if (_showColourModes) {
      return;
    }

    setState(() {
      _colourTransitionForward = true;
      _showColourModes = true;
    });
  }

  void _closeColourModes() {
    if (!_showColourModes) {
      return;
    }

    RodinHaptics.back();

    setState(() {
      _colourTransitionForward = false;
      _showColourModes = false;
    });
  }

  Widget _buildColourModes(
    BuildContext context,
    RodinBackendSnapshot snapshot,
    RodinBackend backend,
    int gamut,
    List<int> expert,
    bool expertEnabled,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final Color accent = colors.primary;
    final bool expertCalibrationEnabled =
        expertEnabled && snapshot.displayColor == 0;

    return RodinScrollPage(
      children: <Widget>[
        DetailHeader(title: 'Colour modes', onBack: _closeColourModes),
        const SizedBox(height: 4),
        Text(
          'Adjust color temperature, color gamut, and RGB channels',
          style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),

        _ChoiceCard(
          title: 'Display colour',
          subtitle: 'Original PRO, Vivid or Saturated',
          icon: Icons.color_lens_rounded,
          accent: accent,
          selectedCode: snapshot.displayColor,
          options: const <_ChoiceOption>[
            _ChoiceOption(0, 'Original PRO'),
            _ChoiceOption(1, 'Vivid'),
            _ChoiceOption(2, 'Saturated'),
          ],
          enabled: expertEnabled,
          onSelected: backend.setDisplayColor,
        ),
        const SizedBox(height: 9),

        _ChoiceCard(
          title: 'Colour temperature',
          subtitle: 'Warm, Normal or Cold',
          icon: Icons.thermostat_rounded,
          accent: const Color(0xFFFFB84D),
          selectedCode: snapshot.displayTemp,
          options: const <_ChoiceOption>[
            _ChoiceOption(1, 'Warm'),
            _ChoiceOption(2, 'Normal'),
            _ChoiceOption(3, 'Cold'),
          ],
          enabled: expertEnabled,
          onSelected: backend.setDisplayTemperature,
        ),
        const SizedBox(height: 9),

        _ChoiceCard(
          title: 'Expert gamut',
          subtitle: snapshot.displayColor == 0
              ? 'Original, Display P3 or sRGB'
              : 'Select Original PRO to customize color space',
          icon: Icons.tonality_rounded,
          accent: const Color(0xFF56D8C7),
          selectedCode: gamut,
          options: const <_ChoiceOption>[
            _ChoiceOption(1, 'Original'),
            _ChoiceOption(2, 'Display P3'),
            _ChoiceOption(3, 'sRGB'),
          ],
          enabled: expertCalibrationEnabled,
          onSelected: backend.setExpertGamut,
        ),
        const SizedBox(height: 9),

        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text(
                    'Live colour swatch',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Builder(
                    builder: (BuildContext context) {
                      final int r = expert[0] >= 0
                          ? expert[0].clamp(0, 255)
                          : 255;
                      final int g = expert[1] >= 0
                          ? expert[1].clamp(0, 255)
                          : 255;
                      final int b = expert[2] >= 0
                          ? expert[2].clamp(0, 255)
                          : 255;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(r, g, b, 0.18),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Color.fromRGBO(r, g, b, 0.6),
                          ),
                        ),
                        child: Text(
                          expert[0] >= 0
                              ? 'RGB($r, $g, $b)'
                              : 'DEFAULT (255, 255, 255)',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (BuildContext context) {
                  final int r = expert[0] >= 0 ? expert[0].clamp(0, 255) : 255;
                  final int g = expert[1] >= 0 ? expert[1].clamp(0, 255) : 255;
                  final int b = expert[2] >= 0 ? expert[2].clamp(0, 255) : 255;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 46,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(r, g, b, 1.0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color.fromRGBO(r, g, b, 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),

        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'RGB channels',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Live expert channel calibration',
                style: TextStyle(
                  fontSize: 11.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),

              _ExpertSliderRow(
                title: 'R',
                value: expert[0],
                min: 0,
                max: 255,
                defaultValue: 255,
                activeColor: const Color(0xFFFF3B30),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(1, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'G',
                value: expert[1],
                min: 0,
                max: 255,
                defaultValue: 255,
                activeColor: const Color(0xFF34C759),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(2, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'B',
                value: expert[2],
                min: 0,
                max: 255,
                defaultValue: 255,
                activeColor: const Color(0xFF007AFF),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(3, value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),

        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'HSV & tone',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Live colour and tone shaping',
                style: TextStyle(
                  fontSize: 11.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),

              _ExpertSliderRow(
                title: 'Hue',
                value: expert[3],
                min: 0,
                max: 255,
                defaultValue: 0,
                activeColor: const Color(0xFFFF9F0A),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(4, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'Saturation',
                value: expert[4],
                min: -40,
                max: 50,
                defaultValue: 0,
                activeColor: const Color(0xFFBF5AF2),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(5, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'Value',
                value: expert[5],
                min: -240,
                max: 255,
                defaultValue: 0,
                activeColor: const Color(0xFF64D2FF),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(6, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'Contrast',
                value: expert[6],
                min: 0,
                max: 100,
                defaultValue: 50,
                activeColor: const Color(0xFFFFD60A),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(7, value),
              ),
              const Divider(height: 8),

              _ExpertSliderRow(
                title: 'Gamma',
                value: expert[7],
                min: 254,
                max: 270,
                defaultValue: 262,
                activeColor: const Color(0xFF30D158),
                enabled: expertCalibrationEnabled,
                onChanged: (int value) => backend.setExpertChannel(8, value),
              ),
              const SizedBox(height: 5),

              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: expertCalibrationEnabled
                      ? () {
                          if (backend.resetExpertDisplay()) {
                            RodinHaptics.confirm();
                          } else {
                            RodinHaptics.reject();
                          }
                        }
                      : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restore expert defaults'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisplayStudioRoot(
    BuildContext context,
    RodinBackendSnapshot snapshot,
    RodinBackend backend,
    bool expertEnabled,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final Color accent = colors.primary;

    return RodinScrollPage(
      children: <Widget>[
        DetailHeader(title: 'Display Studio', onBack: widget.onBack),
        const SizedBox(height: 4),
        Text(
          'Screen color calibration, HDR, and visual enhancements',
          style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),

        HeroCard(
          icon: Icons.palette_rounded,
          accent: accent,
          title: 'Display Engine',
          subtitle: snapshot.displayHal == 1
              ? 'Hardware color engine active'
              : 'Display calibration unavailable',
        ),
        const SizedBox(height: 12),

        const SectionLabel('Display controls'),
        const SizedBox(height: 8),

        FeatureCard(
          icon: Icons.color_lens_rounded,
          accent: accent,
          title: 'Colour modes',
          subtitle: 'Display color, temperature, gamut, RGB, and tone balance',
          onTap: _openColourModes,
        ),

        const SizedBox(height: 12),
        const SectionLabel('Display features'),
        const SizedBox(height: 8),

        _SwitchCard(
          icon: Icons.wb_sunny_rounded,
          accent: const Color(0xFFFFB84D),
          title: 'Sunlight mode',
          subtitle: 'Improves screen readability under bright outdoor light',
          value: snapshot.sunlight == 1,
          enabled: expertEnabled,
          stateKnown: true,
          onChanged: backend.setSunlight,
        ),
        const SizedBox(height: 9),

        _SwitchCard(
          icon: Icons.brightness_6_rounded,
          accent: const Color(0xFF67C2FF),
          title: 'Silky brightness',
          subtitle: 'Smooth brightness dimming curve for low-light comfort',
          value: snapshot.silky == 1,
          enabled: expertEnabled,
          stateKnown: true,
          onChanged: backend.setSilky,
        ),
        const SizedBox(height: 9),

        _SwitchCard(
          icon: Icons.movie_filter_rounded,
          accent: const Color(0xFFB087FF),
          title: 'Video enhancement',
          subtitle: 'Enhance contrast and detail in movies and video playback',
          value: snapshot.video == 1,
          enabled: expertEnabled,
          stateKnown: true,
          onChanged: backend.setVideoEnhancement,
        ),
        const SizedBox(height: 9),

        _SwitchCard(
          icon: Icons.hdr_on_rounded,
          accent: const Color(0xFF74E6C6),
          title: 'Dolby Vision / HDR',
          subtitle: 'Expand dynamic range and depth in HDR content',
          value: snapshot.dolby == 1,
          enabled: expertEnabled,
          stateKnown: true,
          onChanged: backend.setDolbyVision,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;

        final int gamut = backend.extendedValue(2);

        final List<int> expert = List<int>.generate(
          8,
          (int index) => backend.extendedValue(3 + index),
          growable: false,
        );

        final bool expertEnabled =
            snapshot.ready && snapshot.displayHal == 1 && !snapshot.busy;

        final Widget currentPage = _showColourModes
            ? _buildColourModes(
                context,
                snapshot,
                backend,
                gamut,
                expert,
                expertEnabled,
              )
            : _buildDisplayStudioRoot(
                context,
                snapshot,
                backend,
                expertEnabled,
              );

        return AnimatedSwitcher(
          duration: RodinInteractionSettings.motionDuration(500),
          reverseDuration: RodinInteractionSettings.motionDuration(460),
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return ClipRect(child: currentChild ?? const SizedBox.shrink());
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            const Curve relaxedCurve = Cubic(0.16, 1.0, 0.30, 1.0);

            final CurvedAnimation movement = CurvedAnimation(
              parent: animation,
              curve: relaxedCurve,
            );

            final CurvedAnimation opacity = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.86, curve: Curves.easeOutCubic),
            );

            final Animation<Offset> slide = Tween<Offset>(
              begin: Offset(_colourTransitionForward ? 0.040 : -0.040, 0.002),
              end: Offset.zero,
            ).animate(movement);

            final Animation<double> fade = Tween<double>(
              begin: 0.94,
              end: 1,
            ).animate(opacity);

            final Animation<double> scale = Tween<double>(
              begin: 0.998,
              end: 1,
            ).animate(movement);

            return ClipRect(
              child: FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: scale,
                  alignment: _colourTransitionForward
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: SlideTransition(position: slide, child: child),
                ),
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(
              _showColourModes
                  ? 'display-studio-colour-modes'
                  : 'display-studio-root',
            ),
            child: currentPage,
          ),
        );
      },
    );
  }
}

String _performanceProfileLabel(int profile) {
  return switch (profile) {
    0 => 'Stock Balanced',
    1 => 'Gaming Dynamic',
    2 => 'Battery Saver',
    3 => 'Extreme Beast',
    _ => 'Stock Balanced',
  };
}

class PerAppProfilesScreen extends StatefulWidget {
  const PerAppProfilesScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<PerAppProfilesScreen> createState() => _PerAppProfilesScreenState();
}

class _PerAppProfilesScreenState extends State<PerAppProfilesScreen> {
  Timer? _catalogTimer;
  List<RodinInstalledApp> _apps = const <RodinInstalledApp>[];
  String _query = '';
  int _catalogRevision = -1;

  @override
  void initState() {
    super.initState();

    final RodinBackend backend = RodinBackend.instance;
    backend.refreshInstalledApps();
    _reloadCatalog(force: true);

    _catalogTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      if (!mounted) return;
      _reloadCatalog();
    });
  }

  void _reloadCatalog({bool force = false}) {
    final RodinBackend backend = RodinBackend.instance;
    final int revision = backend.installedAppsRevision();

    if (!force && revision == _catalogRevision) {
      return;
    }

    final List<RodinInstalledApp> apps = backend.installedApps();

    if (!mounted) {
      return;
    }

    setState(() {
      _catalogRevision = revision;
      _apps = apps;
    });
  }

  @override
  void dispose() {
    _catalogTimer?.cancel();
    _catalogTimer = null;
    super.dispose();
  }

  List<RodinInstalledApp> get _filteredApps {
    final String query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return _apps;
    }

    return _apps
        .where((RodinInstalledApp app) {
          return app.label.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<RodinInstalledApp> shown = _filteredApps;

    return RodinScrollPage(
      header: DetailHeader(title: 'Per-app Profiles', onBack: widget.onBack),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Text(
                'Native foreground profiles with direct installed-app assignments',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              _PerAppHeaderStatus(apps: _apps),
              const SizedBox(height: 12),
              const SectionLabel('Installed apps'),
              const SizedBox(height: 8),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 4,
                ),
                child: TextField(
                  onChanged: (String value) {
                    setState(() => _query = value);
                  },
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search_rounded),
                    hintText: 'Search apps or package names',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        if (_apps.isEmpty)
          const SliverToBoxAdapter(
            child: SurfaceCard(
              child: _InfoBlock(
                title: 'Loading installed apps',
                text:
                    'The native PackageManager catalog is refreshing in the background.',
              ),
            ),
          )
        else if (shown.isEmpty)
          const SliverToBoxAdapter(
            child: SurfaceCard(
              child: _InfoBlock(
                title: 'No matching apps',
                text: 'Try another app name or package name.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (BuildContext context, int index) {
              final RodinInstalledApp app = shown[index];
              return Padding(
                key: ValueKey<String>(app.packageName),
                padding: const EdgeInsets.only(bottom: 8),
                child: _AppProfileRow(
                  app: app,
                  onProfileChanged: () => setState(() {}),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PerAppHeaderStatus extends StatelessWidget {
  const _PerAppHeaderStatus({required this.apps});

  final List<RodinInstalledApp> apps;

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFF67C2FF);

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int perAppEnabled = backend.extendedValue(19);
        final int activeProfile = backend.extendedValue(20);
        final int mappingCount = backend.extendedValue(21);
        final int applyAck = backend.extendedValue(30);
        final int pruned = backend.extendedValue(31);
        final int keepaliveAck = backend.extendedValue(32);
        final int keepaliveCount = backend.extendedValue(33);
        final int activeIndex = backend.activeInstalledAppIndex();

        RodinInstalledApp? activeApp;
        for (final RodinInstalledApp app in apps) {
          if (app.index == activeIndex) {
            activeApp = app;
            break;
          }
        }

        return Column(
          children: <Widget>[
            HeroCard(
              icon: Icons.auto_awesome_motion_rounded,
              accent: accent,
              title: activeApp?.label ?? 'Per-app controller',
              subtitle: perAppEnabled == 1
                  ? activeApp == null
                        ? 'Active · unmapped apps use Balanced'
                        : '${activeApp.packageName} · runtime ${_performanceProfileLabel(activeProfile)}'
                  : 'Disabled · saved global profile controls performance',
            ),
            const SizedBox(height: 9),
            _SwitchCard(
              icon: Icons.apps_rounded,
              accent: const Color(0xFF56D8C7),
              title: 'Enable per-app profiles',
              subtitle:
                  'Foreground changes are handled by the privileged Rust daemon',
              value: perAppEnabled == 1,
              enabled: snapshot.ready && !snapshot.busy,
              stateKnown: perAppEnabled >= 0,
              onChanged: backend.setPerAppPerformance,
            ),
            const SizedBox(height: 9),
            SurfaceCard(
              child: Column(
                children: <Widget>[
                  _DiagnosticRow(
                    label: 'Runtime apply ACK',
                    good: perAppEnabled != 1 || applyAck == 1,
                    detail: perAppEnabled != 1
                        ? 'Inactive'
                        : applyAck == 1
                        ? 'Applied and verified'
                        : applyAck == 0
                        ? 'Last apply failed'
                        : 'Waiting for foreground app',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Saved mappings',
                    good: mappingCount >= 0,
                    detail: mappingCount >= 0
                        ? '$mappingCount apps'
                        : 'Unknown',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Package cleanup',
                    good: pruned >= 0,
                    detail: pruned > 0
                        ? '$pruned stale mappings removed'
                        : 'No stale mappings',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Runtime keepalive',
                    good: keepaliveAck != 0,
                    detail: keepaliveAck == 1
                        ? 'Active · $keepaliveCount reassertions'
                        : keepaliveAck == 0
                        ? 'Last reassertion failed'
                        : 'Waiting for first wake cycle',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppProfileRow extends StatelessWidget {
  const _AppProfileRow({required this.app, this.onProfileChanged});

  final RodinInstalledApp app;
  final VoidCallback? onProfileChanged;

  Widget _buildIcon(ColorScheme colors, Color accent) {
    if (app.iconPath.isNotEmpty) {
      final File file = File(app.iconPath);
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          file,
          width: 42,
          height: 42,
          cacheWidth: 84,
          cacheHeight: 84,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => IconTile(
            icon: app.system ? Icons.android_rounded : Icons.apps_rounded,
            accent: app.system ? colors.onSurfaceVariant : accent,
            size: 42,
          ),
        ),
      );
    }

    return IconTile(
      icon: app.system ? Icons.android_rounded : Icons.apps_rounded,
      accent: app.system ? colors.onSurfaceVariant : accent,
      size: 42,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    const Color accent = Color(0xFF67C2FF);
    final RodinBackend backend = RodinBackend.instance;
    final int selectedProfile = backend.installedAppProfile(app.index);

    const List<_ChoiceOption> options = <_ChoiceOption>[
      _ChoiceOption(-1, 'Default'),
      _ChoiceOption(0, 'Balanced'),
      _ChoiceOption(1, 'Performance'),
      _ChoiceOption(2, 'Battery'),
      _ChoiceOption(3, 'Gaming'),
    ];

    return RepaintBoundary(
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _buildIcon(colors, accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.8,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _performanceProfileLabel(selectedProfile),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selectedProfile >= 0
                        ? accent
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: options
                  .map((_ChoiceOption option) {
                    final bool selected = option.code == selectedProfile;

                    return ChoiceChip(
                      label: Text(option.label),
                      selected: selected,
                      onSelected: !selected
                          ? (_) {
                              final bool accepted = backend
                                  .setInstalledAppProfile(
                                    app.index,
                                    option.code,
                                  );
                              if (accepted) {
                                RodinHaptics.segment();
                                onProfileChanged?.call();
                              } else {
                                RodinHaptics.reject();
                              }
                            }
                          : null,
                      visualDensity: VisualDensity.compact,
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class CpuPerformanceScreen extends StatefulWidget {
  const CpuPerformanceScreen({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  State<CpuPerformanceScreen> createState() => _CpuPerformanceScreenState();
}

class _CpuPerformanceScreenState extends State<CpuPerformanceScreen> {
  Timer? _toastTimer;
  bool _toastVisible = false;
  String _toastTag = '';
  String _toastMessage = '';
  IconData _toastIcon = Icons.info_outline;
  Color _toastAccent = const Color(0xFF67C2FF);

  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showGlassToast(
    String tag,
    String message,
    IconData icon,
    Color accent,
  ) {
    _toastTimer?.cancel();
    setState(() {
      _toastTag = tag;
      _toastMessage = message;
      _toastIcon = icon;
      _toastAccent = accent;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) {
        setState(() => _toastVisible = false);
      }
    });
  }

  String _freq(int value) {
    if (value <= 0) return '—';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)} GHz';
    return '${(value / 1000).toStringAsFixed(0)} MHz';
  }

  String _mask(int value) {
    if (value < 0) return 'Unknown';
    return '0x${(value & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  void _applyCorePreset(String name, List<int> onlineCores, Color accent) {
    RodinHaptics.confirm();
    final RodinBackend backend = RodinBackend.instance;
    backend.setCpuManualMode(true);
    for (int i = 1; i <= 7; i++) {
      backend.setCpuCoreOnline(i, onlineCores.contains(i));
    }
    _showGlassToast(
      'CORE PRESET APPLIED',
      '$name (${onlineCores.length} Cores Active)',
      Icons.memory_rounded,
      accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot s) {
        final RodinBackend backend = RodinBackend.instance;
        final int manual = backend.extendedValue(34);
        final int writeAck = backend.extendedValue(35);
        final int savedMask = backend.extendedValue(36);
        final int coreCtlNodes = backend.extendedValue(37);
        final int frequencyWriteAck = backend.extendedValue(74);
        final bool canWrite = s.ready && !s.busy;

        int clusterCurrentMhz(Iterable<int> cores) {
          int current = -1;
          for (final int cpu in cores) {
            if (s.cpuOnline(cpu) && s.cpuFreqKhz[cpu] > 0) {
              final int mhz = s.cpuFreqKhz[cpu] ~/ 1000;
              if (mhz > current) current = mhz;
            }
          }
          return current;
        }

        int efficiencyOnline = 0;
        for (int c = 0; c <= 3; c++) {
          if (s.cpuOnline(c)) efficiencyOnline++;
        }
        int performanceOnline = 0;
        for (int c = 4; c <= 6; c++) {
          if (s.cpuOnline(c)) performanceOnline++;
        }
        int primeOnline = s.cpuOnline(7) ? 1 : 0;
        final int totalOnline =
            efficiencyOnline + performanceOnline + primeOnline;

        return Stack(
          children: <Widget>[
            RodinScrollPage(
              children: <Widget>[
                DetailHeader(title: 'CPU Performance', onBack: widget.onBack),
                const SizedBox(height: 4),
                Text(
                  'Per-cluster frequency ranges, exact locks, and processor core control',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                // 1. HERO CARD WITH LIVE CORE STATUS
                SurfaceCard(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? <Color>[
                                const Color(0xFF1E293B),
                                const Color(0xFF0F172A),
                              ]
                            : <Color>[
                                const Color(0xFFEFF6FF),
                                const Color(0xFFDBEAFE),
                              ],
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF38BDF8,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.memory_rounded,
                                color: Color(0xFF38BDF8),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Dimensity 8400-Ultra CPU',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$totalOnline / 8 Cores Online · Live Cluster Control',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00E676,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF00E676,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.circle,
                                    color: Color(0xFF00E676),
                                    size: 7,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF00E676),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: <Widget>[
                            _buildHeroStat(
                              label: 'EFFICIENCY (4C)',
                              val: '$efficiencyOnline / 4 Online',
                              accent: const Color(0xFF4EA8DE),
                              sub: '4× Cortex-A725',
                            ),
                            const SizedBox(width: 8),
                            _buildHeroStat(
                              label: 'PERFORMANCE (3C)',
                              val: '$performanceOnline / 3 Online',
                              accent: const Color(0xFFA066FF),
                              sub: '3× Cortex-A725',
                            ),
                            const SizedBox(width: 8),
                            _buildHeroStat(
                              label: 'PRIME (1C)',
                              val: '$primeOnline / 1 Online',
                              accent: const Color(0xFFFF8E3C),
                              sub: '1× Cortex-A725',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'CPU FREQUENCY CONTROL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 9),
                _CpuFrequencyCard(
                  policy: 0,
                  title: 'Efficiency Cluster',
                  subtitle: '4× Cortex-A725 · Cores 0–3 · 256KB L2',
                  accent: const Color(0xFF4EA8DE),
                  currentMhz: clusterCurrentMhz(const <int>[0, 1, 2, 3]),
                  targetMinMhz: backend.cpuTargetMinFrequency(0),
                  targetMaxMhz: backend.cpuTargetMaxFrequency(0),
                  liveMinMhz: backend.cpuLiveMinFrequency(0),
                  liveMaxMhz: backend.cpuLiveMaxFrequency(0),
                  availableMhz: backend.cpuAvailableFrequencies(0),
                  governorCode: s.cpuGovernor0,
                  writeAck: frequencyWriteAck,
                  drift: backend.cpuFrequencyDrift(0),
                  enabled: canWrite,
                  onFeedback: _showGlassToast,
                ),
                const SizedBox(height: 9),
                _CpuFrequencyCard(
                  policy: 4,
                  title: 'Performance Cluster',
                  subtitle: '3× Cortex-A725 · Cores 4–6 · 512KB L2',
                  accent: const Color(0xFFA066FF),
                  currentMhz: clusterCurrentMhz(const <int>[4, 5, 6]),
                  targetMinMhz: backend.cpuTargetMinFrequency(4),
                  targetMaxMhz: backend.cpuTargetMaxFrequency(4),
                  liveMinMhz: backend.cpuLiveMinFrequency(4),
                  liveMaxMhz: backend.cpuLiveMaxFrequency(4),
                  availableMhz: backend.cpuAvailableFrequencies(4),
                  governorCode: s.cpuGovernor4,
                  writeAck: frequencyWriteAck,
                  drift: backend.cpuFrequencyDrift(4),
                  enabled: canWrite,
                  onFeedback: _showGlassToast,
                ),
                const SizedBox(height: 9),
                _CpuFrequencyCard(
                  policy: 7,
                  title: 'Prime Core',
                  subtitle: '1× Cortex-A725 · Core 7 · 1MB L2',
                  accent: const Color(0xFFFF8E3C),
                  currentMhz: clusterCurrentMhz(const <int>[7]),
                  targetMinMhz: backend.cpuTargetMinFrequency(7),
                  targetMaxMhz: backend.cpuTargetMaxFrequency(7),
                  liveMinMhz: backend.cpuLiveMinFrequency(7),
                  liveMaxMhz: backend.cpuLiveMaxFrequency(7),
                  availableMhz: backend.cpuAvailableFrequencies(7),
                  governorCode: s.cpuGovernor7,
                  writeAck: frequencyWriteAck,
                  drift: backend.cpuFrequencyDrift(7),
                  enabled: canWrite,
                  onFeedback: _showGlassToast,
                ),
                const SizedBox(height: 10),
                const SurfaceCard(
                  child: _InfoBlock(
                    title: 'Independent frequency targets',
                    text:
                        'Minimum, maximum, and exact-lock targets persist across reboot without changing the selected CPU governor. Live effective limits are reported separately from the saved target.',
                  ),
                ),
                const SizedBox(height: 12),

                // 2. MANUAL MASTER SWITCH
                _SwitchCard(
                  icon: Icons.tune_rounded,
                  accent: const Color(0xFF67C2FF),
                  title: 'Manual core control',
                  subtitle: manual == 1
                      ? 'Manual hotplug active · cores stay at toggled states'
                      : 'Enable to manually power on/off individual processor cores',
                  value: manual == 1,
                  enabled: canWrite,
                  stateKnown: manual >= 0,
                  onChanged: (bool val) {
                    RodinHaptics.toggle(val);
                    return backend.setCpuManualMode(val);
                  },
                ),
                const SizedBox(height: 12),

                // 3. QUICK CORE PRESETS
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'QUICK CORE CONFIGURATIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _buildQuickCoreButton(
                            isDark: isDark,
                            colors: colors,
                            title: 'All Cores On',
                            subtitle: '8/8 Cores Online',
                            icon: Icons.flash_on_rounded,
                            accent: const Color(0xFF00E676),
                            onTap: () => _applyCorePreset(
                              'All 8 Cores Online',
                              <int>[0, 1, 2, 3, 4, 5, 6, 7],
                              const Color(0xFF00E676),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildQuickCoreButton(
                            isDark: isDark,
                            colors: colors,
                            title: 'Balanced',
                            subtitle: '7/8 · Prime Core Off',
                            icon: Icons.balance_rounded,
                            accent: const Color(0xFF4EA8DE),
                            onTap: () => _applyCorePreset(
                              'Balanced 7-Core Mode',
                              <int>[0, 1, 2, 3, 4, 5, 6],
                              const Color(0xFF4EA8DE),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildQuickCoreButton(
                            isDark: isDark,
                            colors: colors,
                            title: 'Power Saver',
                            subtitle: 'Efficiency Cores 0–3',
                            icon: Icons.eco_rounded,
                            accent: const Color(0xFF35C997),
                            onTap: () => _applyCorePreset(
                              'Eco 4-Core Mode',
                              <int>[0, 1, 2, 3],
                              const Color(0xFF35C997),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 4. EFFICIENCY CLUSTER (CORES 0-3)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4EA8DE),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Efficiency Cluster',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  '4× Cortex-A725 · Cores 0–3 · $efficiencyOnline/4 Online',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      for (int cpu = 0; cpu <= 3; cpu++) ...<Widget>[
                        _CpuStatusRow(
                          cpu: cpu,
                          online: s.cpuOnline(cpu),
                          frequency: s.cpuOnline(cpu)
                              ? _freq(s.cpuFreqKhz[cpu])
                              : 'Off',
                          accent: const Color(0xFF4EA8DE),
                          clusterTag: cpu == 0 ? 'MASTER' : 'EFFICIENCY',
                          toggleEnabled: cpu != 0 && manual == 1 && canWrite,
                          onChanged: cpu == 0
                              ? null
                              : (bool online) {
                                  RodinHaptics.toggle(online);
                                  backend.setCpuCoreOnline(cpu, online);
                                },
                        ),
                        if (cpu != 3) const Divider(height: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 5. PERFORMANCE CLUSTER (CORES 4-6)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFA066FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Performance Cluster',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  '3× Cortex-A725 · Cores 4–6 · $performanceOnline/3 Online',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      for (int cpu = 4; cpu <= 6; cpu++) ...<Widget>[
                        _CpuStatusRow(
                          cpu: cpu,
                          online: s.cpuOnline(cpu),
                          frequency: s.cpuOnline(cpu)
                              ? _freq(s.cpuFreqKhz[cpu])
                              : 'Off',
                          accent: const Color(0xFFA066FF),
                          clusterTag: 'PERFORMANCE',
                          toggleEnabled: manual == 1 && canWrite,
                          onChanged: (bool online) {
                            RodinHaptics.toggle(online);
                            backend.setCpuCoreOnline(cpu, online);
                          },
                        ),
                        if (cpu != 6) const Divider(height: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 6. PRIME SUPERCORE (CORE 7)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF8E3C),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Prime Core',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  '1× Cortex-A725 · Core 7 · $primeOnline/1 Online',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      _CpuStatusRow(
                        cpu: 7,
                        online: s.cpuOnline(7),
                        frequency: s.cpuOnline(7)
                            ? _freq(s.cpuFreqKhz[7])
                            : 'Off',
                        accent: const Color(0xFFFF8E3C),
                        clusterTag: 'PRIME',
                        toggleEnabled: manual == 1 && canWrite,
                        onChanged: (bool online) {
                          RodinHaptics.toggle(online);
                          backend.setCpuCoreOnline(7, online);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 7. DIAGNOSTICS & SAFETY
                SurfaceCard(
                  child: Column(
                    children: <Widget>[
                      _DiagnosticRow(
                        label: 'Control Mode',
                        good: manual == 1,
                        detail: manual == 1
                            ? 'Manual hotplug control'
                            : 'Automatic balance',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Frequency Target',
                        good: frequencyWriteAck != 0,
                        detail: frequencyWriteAck == 1
                            ? 'Last request verified'
                            : frequencyWriteAck == 0
                            ? 'Last request failed'
                            : 'No request yet',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Core State',
                        good: writeAck == 1,
                        detail: writeAck == 1
                            ? 'Applied'
                            : writeAck == 0
                            ? 'Failed'
                            : 'Checking...',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Active Core Mask',
                        good: savedMask >= 0,
                        detail: _mask(savedMask),
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Processor Clusters',
                        good: coreCtlNodes >= 0,
                        detail: coreCtlNodes >= 0
                            ? '$coreCtlNodes clusters active'
                            : 'Unknown',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SurfaceCard(
                  child: _InfoBlock(
                    title: 'Processor Core Safety',
                    text:
                        'Primary core (CPU0) remains permanently active to ensure kernel and essential background services run smoothly. Core states persist across device reboots.',
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),

            // FLOATING GLASS TOAST OVERLAY AT BOTTOM
            if (_toastVisible)
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                left: 16,
                right: 16,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (BuildContext context, double value, Widget? child) {
                    return Transform.translate(
                      offset: Offset(0, 14 * (1.0 - value)),
                      child: Opacity(
                        opacity: value,
                        child: _buildToastCard(colors: colors),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeroStat({
    required String label,
    required String val,
    required Color accent,
    required String sub,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              val,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 1),
            Text(
              sub,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: accent.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCoreButton({
    required bool isDark,
    required ColorScheme colors,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToastCard({required ColorScheme colors}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _toastAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _toastAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_toastIcon, size: 20, color: _toastAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _toastTag,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _toastAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _toastMessage,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CpuFrequencyCard extends StatefulWidget {
  const _CpuFrequencyCard({
    required this.policy,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.currentMhz,
    required this.targetMinMhz,
    required this.targetMaxMhz,
    required this.liveMinMhz,
    required this.liveMaxMhz,
    required this.availableMhz,
    required this.governorCode,
    required this.writeAck,
    required this.drift,
    required this.enabled,
    required this.onFeedback,
  });

  final int policy;
  final String title;
  final String subtitle;
  final Color accent;
  final int currentMhz;
  final int targetMinMhz;
  final int targetMaxMhz;
  final int liveMinMhz;
  final int liveMaxMhz;
  final List<int> availableMhz;
  final int governorCode;
  final int writeAck;
  final int drift;
  final bool enabled;
  final void Function(String, String, IconData, Color) onFeedback;

  @override
  State<_CpuFrequencyCard> createState() => _CpuFrequencyCardState();
}

class _CpuFrequencyCardState extends State<_CpuFrequencyCard> {
  int _minimumMhz = -1;
  int _maximumMhz = -1;
  bool _exactLock = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _syncFromBackend(force: true);
  }

  @override
  void didUpdateWidget(covariant _CpuFrequencyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromBackend();
  }

  int _nearestAvailable(int requested) {
    final List<int> available = widget.availableMhz;
    if (available.isEmpty) return -1;
    if (requested <= 0) return available.first;

    int nearest = available.first;
    int distance = (nearest - requested).abs();
    for (final int frequency in available.skip(1)) {
      final int nextDistance = (frequency - requested).abs();
      if (nextDistance < distance) {
        nearest = frequency;
        distance = nextDistance;
      }
    }
    return nearest;
  }

  void _syncFromBackend({bool force = false}) {
    if (widget.availableMhz.isEmpty || (_dirty && !force)) return;

    final bool custom = widget.targetMinMhz > 0 && widget.targetMaxMhz > 0;
    final int requestedMin = custom ? widget.targetMinMhz : widget.liveMinMhz;
    final int requestedMax = custom ? widget.targetMaxMhz : widget.liveMaxMhz;
    _minimumMhz = _nearestAvailable(requestedMin);
    _maximumMhz = _nearestAvailable(requestedMax);

    if (_minimumMhz > _maximumMhz) {
      final int swap = _minimumMhz;
      _minimumMhz = _maximumMhz;
      _maximumMhz = swap;
    }
    _exactLock = custom && _minimumMhz == _maximumMhz;
  }

  int _frequencyIndex(int frequency) {
    final int exact = widget.availableMhz.indexOf(frequency);
    if (exact >= 0) return exact;
    return widget.availableMhz.indexOf(_nearestAvailable(frequency));
  }

  String _frequencyLabel(int mhz) {
    if (mhz <= 0) return '—';
    if (mhz >= 1000) {
      final int hundredths = (mhz * 100) ~/ 1000;
      final String value = (hundredths / 100).toStringAsFixed(
        hundredths % 10 == 0 ? 1 : 2,
      );
      return '$value GHz';
    }
    return '$mhz MHz';
  }

  String _governorLabel() => switch (widget.governorCode) {
    0 => 'sugov_ext',
    1 => 'conservative',
    2 => 'powersave',
    3 => 'performance',
    4 => 'schedutil',
    _ => 'Detecting',
  };

  void _setExactLock(bool lock) {
    if (_exactLock == lock || widget.availableMhz.isEmpty) return;
    RodinHaptics.segment();
    setState(() {
      _exactLock = lock;
      if (lock) {
        final int target = _maximumMhz > 0
            ? _maximumMhz
            : widget.availableMhz.last;
        _minimumMhz = target;
        _maximumMhz = target;
      } else if (_minimumMhz == _maximumMhz) {
        _minimumMhz = widget.availableMhz.first;
      }
      _dirty = true;
    });
  }

  void _apply() {
    if (!widget.enabled ||
        widget.availableMhz.isEmpty ||
        _minimumMhz <= 0 ||
        _maximumMhz <= 0) {
      RodinHaptics.reject();
      return;
    }

    final bool accepted = RodinBackend.instance.setCpuClusterFreqRange(
      widget.policy,
      _minimumMhz,
      _maximumMhz,
    );
    if (!accepted) {
      RodinHaptics.reject();
      return;
    }

    RodinHaptics.confirm();
    setState(() => _dirty = false);
    widget.onFeedback(
      _exactLock ? 'EXACT LOCK REQUESTED' : 'FREQUENCY RANGE REQUESTED',
      _exactLock
          ? '${widget.title} · ${_frequencyLabel(_maximumMhz)}'
          : '${widget.title} · ${_frequencyLabel(_minimumMhz)} – ${_frequencyLabel(_maximumMhz)}',
      _exactLock ? Icons.lock_rounded : Icons.tune_rounded,
      widget.accent,
    );
  }

  void _reset() {
    if (!widget.enabled) {
      RodinHaptics.reject();
      return;
    }

    final bool accepted = RodinBackend.instance.resetCpuClusterFreqRange(
      widget.policy,
    );
    if (!accepted) {
      RodinHaptics.reject();
      return;
    }

    RodinHaptics.confirm();
    setState(() {
      _dirty = false;
      _exactLock = false;
      if (widget.availableMhz.isNotEmpty) {
        _minimumMhz = widget.availableMhz.first;
        _maximumMhz = widget.availableMhz.last;
      }
    });
    widget.onFeedback(
      'OEM RANGE REQUESTED',
      '${widget.title} returned to OEM-managed limits',
      Icons.restart_alt_rounded,
      widget.accent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool custom = widget.targetMinMhz > 0 && widget.targetMaxMhz > 0;
    final bool tableReady = widget.availableMhz.isNotEmpty;
    final int maxIndex = tableReady ? widget.availableMhz.length - 1 : 0;
    final int minIndex = tableReady
        ? _frequencyIndex(_minimumMhz).clamp(0, maxIndex)
        : 0;
    final int selectedMaxIndex = tableReady
        ? _frequencyIndex(_maximumMhz).clamp(0, maxIndex)
        : 0;
    final String stateLabel = _dirty
        ? 'EDITING'
        : !custom
        ? 'OEM'
        : widget.targetMinMhz == widget.targetMaxMhz
        ? 'LOCKED'
        : 'RANGE';
    final String verification = !custom
        ? 'OEM managed'
        : widget.drift == 0
        ? 'Target verified'
        : widget.writeAck == 0
        ? 'Write not verified'
        : 'Target reapplying';

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: widget.accent,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: widget.accent.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 10.8,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: stateLabel, accent: widget.accent),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: widget.accent.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _CpuFrequencyMetric(
                    label: 'CURRENT',
                    value: _frequencyLabel(widget.currentMhz),
                    accent: widget.accent,
                  ),
                ),
                Container(
                  width: 1,
                  height: 35,
                  color: colors.outline.withValues(alpha: 0.28),
                ),
                Expanded(
                  child: _CpuFrequencyMetric(
                    label: 'LIVE LIMITS',
                    value:
                        '${_frequencyLabel(widget.liveMinMhz)} – ${_frequencyLabel(widget.liveMaxMhz)}',
                    accent: widget.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Governor: ${_governorLabel()} · unchanged',
                  style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                tableReady
                    ? '${widget.availableMhz.length} supported clocks'
                    : 'Reading clock table',
                style: TextStyle(
                  fontSize: 10.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _CpuModeButton(
                  label: 'Dynamic Range',
                  icon: Icons.swap_horiz_rounded,
                  selected: !_exactLock,
                  accent: widget.accent,
                  enabled: widget.enabled && tableReady,
                  onTap: () => _setExactLock(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CpuModeButton(
                  label: 'Exact Lock',
                  icon: Icons.lock_rounded,
                  selected: _exactLock,
                  accent: widget.accent,
                  enabled: widget.enabled && tableReady,
                  onTap: () => _setExactLock(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: !tableReady
                ? SizedBox(
                    key: const ValueKey<String>('loading'),
                    height: 54,
                    child: Center(
                      child: Text(
                        'Waiting for the kernel frequency table…',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                : _exactLock
                ? Column(
                    key: const ValueKey<String>('lock'),
                    children: <Widget>[
                      _CpuRangeLabels(
                        leftLabel: 'LOCK TARGET',
                        leftValue: _frequencyLabel(_maximumMhz),
                        rightLabel: 'MIN = MAX',
                        rightValue: '${_maximumMhz} MHz',
                        accent: widget.accent,
                      ),
                      Slider(
                        value: selectedMaxIndex.toDouble(),
                        min: 0,
                        max: maxIndex.toDouble(),
                        divisions: maxIndex > 0 ? maxIndex : null,
                        label: _frequencyLabel(_maximumMhz),
                        activeColor: widget.accent,
                        onChanged: widget.enabled
                            ? (double value) {
                                final int target =
                                    widget.availableMhz[value.round()];
                                setState(() {
                                  _minimumMhz = target;
                                  _maximumMhz = target;
                                  _dirty = true;
                                });
                              }
                            : null,
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey<String>('range'),
                    children: <Widget>[
                      _CpuRangeLabels(
                        leftLabel: 'MINIMUM',
                        leftValue: _frequencyLabel(_minimumMhz),
                        rightLabel: 'MAXIMUM',
                        rightValue: _frequencyLabel(_maximumMhz),
                        accent: widget.accent,
                      ),
                      RangeSlider(
                        values: RangeValues(
                          minIndex.toDouble(),
                          selectedMaxIndex.toDouble(),
                        ),
                        min: 0,
                        max: maxIndex.toDouble(),
                        divisions: maxIndex > 0 ? maxIndex : null,
                        labels: RangeLabels(
                          _frequencyLabel(_minimumMhz),
                          _frequencyLabel(_maximumMhz),
                        ),
                        activeColor: widget.accent,
                        onChanged: widget.enabled
                            ? (RangeValues values) {
                                setState(() {
                                  _minimumMhz =
                                      widget.availableMhz[values.start.round()];
                                  _maximumMhz =
                                      widget.availableMhz[values.end.round()];
                                  _dirty = true;
                                });
                              }
                            : null,
                      ),
                    ],
                  ),
          ),
          Row(
            children: <Widget>[
              Icon(
                widget.drift == 1 ? Icons.sync_rounded : Icons.verified_rounded,
                size: 14,
                color: widget.drift == 1
                    ? colors.onSurfaceVariant
                    : widget.accent,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  verification,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: widget.enabled ? _reset : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                label: const Text('OEM'),
              ),
              const SizedBox(width: 3),
              FilledButton.tonalIcon(
                onPressed: widget.enabled && tableReady && _dirty
                    ? _apply
                    : null,
                icon: Icon(
                  _exactLock ? Icons.lock_rounded : Icons.check_rounded,
                  size: 17,
                ),
                label: const Text('Apply'),
                style: FilledButton.styleFrom(
                  foregroundColor: widget.accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CpuFrequencyMetric extends StatelessWidget {
  const _CpuFrequencyMetric({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: accent,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _CpuModeButton extends StatelessWidget {
  const _CpuModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.13)
                : colors.surfaceContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.52)
                  : colors.outline.withValues(alpha: 0.42),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: selected ? accent : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? accent : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CpuRangeLabels extends StatelessWidget {
  const _CpuRangeLabels({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
    required this.accent,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, CrossAxisAlignment alignment) {
      return Column(
        crossAxisAlignment: alignment,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 9.3,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        item(leftLabel, leftValue, CrossAxisAlignment.start),
        const Spacer(),
        item(rightLabel, rightValue, CrossAxisAlignment.end),
      ],
    );
  }
}

class AdvancedConfigurationScreen extends StatefulWidget {
  const AdvancedConfigurationScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<AdvancedConfigurationScreen> createState() =>
      _AdvancedConfigurationScreenState();
}

class _AdvancedConfigurationScreenState
    extends State<AdvancedConfigurationScreen> {
  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    const List<_ChoiceOption> cpuGovernors = <_ChoiceOption>[
      _ChoiceOption(0, 'sugov_ext'),
      _ChoiceOption(1, 'conservative'),
      _ChoiceOption(2, 'powersave'),
      _ChoiceOption(3, 'performance'),
      _ChoiceOption(4, 'schedutil'),
    ];

    const List<_ChoiceOption> schedulers = <_ChoiceOption>[
      _ChoiceOption(0, 'none'),
      _ChoiceOption(1, 'mq-deadline'),
      _ChoiceOption(2, 'kyber'),
      _ChoiceOption(3, 'bfq'),
    ];

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int drift0 = backend.extendedValue(14);
        final int drift4 = backend.extendedValue(15);
        final int drift7 = backend.extendedValue(16);
        final int ioDrift = backend.extendedValue(18);

        return RodinScrollPage(
          children: <Widget>[
            DetailHeader(
              title: 'Advanced Configuration',
              onBack: widget.onBack,
            ),
            const SizedBox(height: 4),
            Text(
              'Processor governors, graphics scaling, and storage queue policies',
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            const HeroCard(
              icon: Icons.tune_rounded,
              accent: Color(0xFFFF9F68),
              title: 'Persistent System Tuning',
              subtitle:
                  'Settings are saved securely and automatically maintained in the background',
            ),
            const SizedBox(height: 12),
            const SectionLabel('CPU governors'),
            const SizedBox(height: 8),
            _ChoiceCard(
              title: 'Efficiency cluster',
              subtitle: 'Efficiency cores (Cores 0–3)',
              icon: Icons.memory_rounded,
              accent: const Color(0xFF46CFA1),
              selectedCode: snapshot.cpuGovernor0,
              options: cpuGovernors,
              enabled: snapshot.ready && !snapshot.busy,
              onSelected: (int code) => backend.setCpuGovernor(0, code),
            ),
            const SizedBox(height: 9),
            _ChoiceCard(
              title: 'Performance cluster',
              subtitle: 'Performance cores (Cores 4–6)',
              icon: Icons.memory_rounded,
              accent: const Color(0xFFB087FF),
              selectedCode: snapshot.cpuGovernor4,
              options: cpuGovernors,
              enabled: snapshot.ready && !snapshot.busy,
              onSelected: (int code) => backend.setCpuGovernor(4, code),
            ),
            const SizedBox(height: 9),
            _ChoiceCard(
              title: 'Prime cluster',
              subtitle: 'Prime core (Core 7)',
              icon: Icons.memory_rounded,
              accent: const Color(0xFFFF9F68),
              selectedCode: snapshot.cpuGovernor7,
              options: cpuGovernors,
              enabled: snapshot.ready && !snapshot.busy,
              onSelected: (int code) => backend.setCpuGovernor(7, code),
            ),
            const SizedBox(height: 9),
            SurfaceCard(
              child: Column(
                children: <Widget>[
                  _PersistenceStatusRow(
                    label: 'Efficiency governor persistence',
                    state: drift0,
                  ),
                  const Divider(height: 14),
                  _PersistenceStatusRow(
                    label: 'Performance governor persistence',
                    state: drift4,
                  ),
                  const Divider(height: 14),
                  _PersistenceStatusRow(
                    label: 'Prime governor persistence',
                    state: drift7,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SectionLabel('Storage scheduler'),
            const SizedBox(height: 8),
            _ChoiceCard(
              title: 'UFS storage scheduler',
              subtitle: 'Queue policy across every detected UFS LUN',
              icon: Icons.storage_rounded,
              accent: Theme.of(context).colorScheme.primary,
              selectedCode: snapshot.ufsScheduler,
              options: schedulers,
              enabled: snapshot.ready && !snapshot.busy,
              onSelected: backend.setUfsScheduler,
            ),
            const SizedBox(height: 9),
            SurfaceCard(
              child: _PersistenceStatusRow(
                label: 'UFS scheduler persistence',
                state: ioDrift,
              ),
            ),
          ],
        );
      },
    );
  }
}

class ResolutionScreen extends StatefulWidget {
  const ResolutionScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<ResolutionScreen> createState() => _ResolutionScreenState();
}

class _ResolutionScreenState extends State<ResolutionScreen> {
  int _customWidth = 1080;
  int _customHeight = 2400;
  int _customDensity = 460;
  bool _lockAspectRatio = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  void _applyResolution(int width, int height, int density, String label) {
    final RodinBackend backend = RodinBackend.instance;
    backend.haptic(2);
    setState(() => _applying = true);

    final bool isNative =
        (width <= 0 || height <= 0) || (width == 1220 && height == 2712);

    if (isNative) {
      backend.resetDisplayResolution();
    } else {
      backend.setDisplayResolution(width, height, density);
    }

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      backend.refresh();
      if (mounted) {
        setState(() => _applying = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF1E222A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: const Color(0xFFFFBE63).withValues(alpha: 0.35),
              ),
            ),
            content: Row(
              children: <Widget>[
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFFFFBE63),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isNative
                        ? 'Reset to Rodin 1.5K Native Panel'
                        : 'Applied $label ($width × $height @ ${density}DPI)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFFFFBE63);
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int activeWidth = backend.extendedValue(22);
        final int activeHeight = backend.extendedValue(23);
        final int hzX10 = backend.extendedValue(24);
        final int activeDensity = backend.extendedValue(38) > 0
            ? backend.extendedValue(38)
            : 520;

        final bool isNative =
            activeWidth <= 0 || (activeWidth == 1220 && activeHeight == 2712);
        final bool isFhd = activeWidth == 1080 && activeHeight == 2400;
        final bool isHd = activeWidth == 720 && activeHeight == 1600;
        final bool isQhd = activeWidth == 1440 && activeHeight == 3200;

        String hz(int value) {
          if (value <= 0) return '120 Hz';
          final double rate = value / 10.0;
          return value % 10 == 0
              ? '${rate.toStringAsFixed(0)} Hz'
              : '${rate.toStringAsFixed(1)} Hz';
        }

        final List<_ResolutionPreset> presets = <_ResolutionPreset>[
          _ResolutionPreset(
            title: 'Native 1.5K Pro',
            badge: '1.5K NATIVE',
            resolutionText: '1220 × 2712',
            width: 1220,
            height: 2712,
            density: 520,
            aspectRatio: '20:9',
            description:
                'Rodin physical hardware panel resolution. Maximum sharpness and true 1:1 pixel rendering with zero scaling.',
            accentColor: const Color(0xFF59BCFF),
            icon: Icons.auto_awesome_rounded,
            isActive: isNative,
          ),
          _ResolutionPreset(
            title: 'Full HD+ (High Performance)',
            badge: 'FHD+ 1080p',
            resolutionText: '1080 × 2400',
            width: 1080,
            height: 2400,
            density: 460,
            aspectRatio: '20:9',
            description:
                'Reduces GPU rasterization load by ~22%. Boosts sustained 120 FPS frame stability in heavy 3D games.',
            accentColor: const Color(0xFF38E598),
            icon: Icons.sports_esports_rounded,
            isActive: isFhd,
          ),
          _ResolutionPreset(
            title: 'HD+ (Ultra Battery Saver)',
            badge: 'HD+ 720p',
            resolutionText: '720 × 1600',
            width: 720,
            height: 1600,
            density: 307,
            aspectRatio: '20:9',
            description:
                'Lowest GPU workload and power consumption. Drastically extends battery life in emergency situations.',
            accentColor: const Color(0xFFFFA048),
            icon: Icons.battery_charging_full_rounded,
            isActive: isHd,
          ),
          _ResolutionPreset(
            title: 'Quad HD+ (High Density Canvas)',
            badge: 'QHD+ 1440p',
            resolutionText: '1440 × 3200',
            width: 1440,
            height: 3200,
            density: 614,
            aspectRatio: '20:9',
            description:
                'Downscaled 2K virtual canvas for maximum screen real estate and ultra-compact multitasking view.',
            accentColor: const Color(0xFFB087FF),
            icon: Icons.fullscreen_rounded,
            isActive: isQhd,
          ),
        ];

        return RodinScrollPage(
          children: <Widget>[
            DetailHeader(title: 'Resolution', onBack: widget.onBack),
            const SizedBox(height: 4),
            Text(
              'Hardware-mapped resolution switching and canvas scaling for Rodin (1220×2712 1.5K AMOLED)',
              style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // Live Hero Card
            SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: dark ? 0.14 : 0.09),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: dark ? 0.28 : 0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.grid_view_rounded,
                          size: 22,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                activeWidth > 0 && activeHeight > 0
                                    ? '$activeWidth × $activeHeight'
                                    : '1220 × 2712',
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isNative
                                  ? 'Rodin 1.5K AMOLED Native (1:1 Map)'
                                  : isFhd
                                  ? 'FHD+ High Performance Mode'
                                  : isHd
                                  ? 'HD+ Battery Saver Mode'
                                  : isQhd
                                  ? 'QHD+ Canvas Mode'
                                  : 'Custom Resolution Override',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (isNative ? const Color(0xFF59BCFF) : accent)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: (isNative ? const Color(0xFF59BCFF) : accent)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          isNative ? '1.5K NATIVE' : 'SCALED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                            color: isNative ? const Color(0xFF59BCFF) : accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      _ResolutionMetricPill(
                        icon: Icons.aspect_ratio_rounded,
                        label: 'Aspect',
                        value: '20:9',
                      ),
                      const SizedBox(width: 8),
                      _ResolutionMetricPill(
                        icon: Icons.speed_rounded,
                        label: 'Refresh',
                        value: hz(hzX10),
                      ),
                      const SizedBox(width: 8),
                      _ResolutionMetricPill(
                        icon: Icons.grain_rounded,
                        label: 'Density',
                        value: '$activeDensity DPI',
                      ),
                    ],
                  ),
                  if (!isNative) ...<Widget>[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF59BCFF),
                          side: BorderSide(
                            color: const Color(
                              0xFF59BCFF,
                            ).withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text(
                          'Reset to 1.5K Native (1220 × 2712)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: _applying
                            ? null
                            : () => _applyResolution(
                                1220,
                                2712,
                                520,
                                '1.5K Native',
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Section Header
            Row(
              children: <Widget>[
                const Text(
                  'RODIN PRESET MAPPINGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Text(
                  '1220×2712 Physical Panel',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Presets Cards
            for (final _ResolutionPreset preset in presets) ...<Widget>[
              _PresetCard(
                preset: preset,
                applying: _applying,
                onTap: () => _applyResolution(
                  preset.width,
                  preset.height,
                  preset.density,
                  preset.title,
                ),
              ),
              const SizedBox(height: 9),
            ],

            const SizedBox(height: 8),

            // Custom Resolution Tuner
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconTile(
                        icon: Icons.tune_rounded,
                        accent: accent,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Custom Resolution Tuner',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Direct wm size & density hardware scaling',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Aspect Ratio Lock Toggle
                  Row(
                    children: <Widget>[
                      Icon(
                        _lockAspectRatio
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 17,
                        color: _lockAspectRatio
                            ? accent
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Lock 20:9 Aspect Ratio (Prevents distortion)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Switch(
                        value: _lockAspectRatio,
                        activeThumbColor: accent,
                        activeTrackColor: accent.withValues(alpha: 0.35),
                        onChanged: (bool value) {
                          setState(() => _lockAspectRatio = value);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 18),

                  // Width Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Horizontal Width',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$_customWidth px',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _customWidth.toDouble(),
                    min: 720,
                    max: 1440,
                    divisions: 72,
                    activeColor: accent,
                    onChangeStart: (_) => RodinHaptics.segment(),
                    onChanged: (double val) {
                      final int w = val.round();
                      setState(() {
                        _customWidth = w;
                        if (_lockAspectRatio) {
                          _customHeight = (w * 2712 ~/ 1220);
                          _customDensity = (520 * w ~/ 1220);
                        }
                      });
                      RodinHaptics.frequentSegment();
                    },
                    onChangeEnd: (_) => RodinHaptics.confirm(),
                  ),

                  // Height Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Vertical Height',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$_customHeight px',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _customHeight.toDouble().clamp(1600, 3200),
                    min: 1600,
                    max: 3200,
                    divisions: 160,
                    activeColor: accent,
                    onChangeStart: _lockAspectRatio
                        ? null
                        : (_) => RodinHaptics.segment(),
                    onChanged: _lockAspectRatio
                        ? null
                        : (double val) {
                            setState(() => _customHeight = val.round());
                            RodinHaptics.frequentSegment();
                          },
                    onChangeEnd: _lockAspectRatio
                        ? null
                        : (_) => RodinHaptics.confirm(),
                  ),

                  // Density Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text(
                        'Pixel Density (DPI)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$_customDensity DPI',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _customDensity.toDouble().clamp(280, 640),
                    min: 280,
                    max: 640,
                    divisions: 72,
                    activeColor: accent,
                    onChangeStart: (_) => RodinHaptics.segment(),
                    onChanged: (double val) {
                      setState(() => _customDensity = val.round());
                      RodinHaptics.frequentSegment();
                    },
                    onChangeEnd: (_) => RodinHaptics.confirm(),
                  ),

                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _applying
                            ? 'Applying...'
                            : 'Apply Custom $_customWidth × $_customHeight (${_customDensity}DPI)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                      onPressed: _applying
                          ? null
                          : () => _applyResolution(
                              _customWidth,
                              _customHeight,
                              _customDensity,
                              'Custom',
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Hardware Telemetry
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Rodin Display Architecture',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DiagnosticRow(
                    label: 'Physical Panel Size',
                    good: true,
                    detail: '1220 × 2712 (1.5K AMOLED)',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Hardware Pixel Density',
                    good: true,
                    detail: '520 PPI (Sub-pixel RGB)',
                  ),
                  const Divider(height: 14),
                  const _DiagnosticRow(
                    label: 'Display Refresh Rate',
                    good: true,
                    detail: 'System Managed (Display Settings)',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Panel Aspect Ratio',
                    good: true,
                    detail: '20:9 (Native Precision)',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Active Canvas Mode',
                    good: true,
                    detail: isNative
                        ? '1:1 Native Physical'
                        : '$activeWidth × $activeHeight Scaled',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResolutionPreset {
  const _ResolutionPreset({
    required this.title,
    required this.badge,
    required this.resolutionText,
    required this.width,
    required this.height,
    required this.density,
    required this.aspectRatio,
    required this.description,
    required this.accentColor,
    required this.icon,
    required this.isActive,
  });

  final String title;
  final String badge;
  final String resolutionText;
  final int width;
  final int height;
  final int density;
  final String aspectRatio;
  final String description;
  final Color accentColor;
  final IconData icon;
  final bool isActive;
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.applying,
    required this.onTap,
  });

  final _ResolutionPreset preset;
  final bool applying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: applying || preset.isActive ? null : onTap,
      child: SurfaceCard(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: preset.accentColor.withValues(
                      alpha: dark ? 0.14 : 0.09,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: preset.accentColor.withValues(
                        alpha: dark ? 0.28 : 0.18,
                      ),
                    ),
                  ),
                  child: Icon(preset.icon, size: 19, color: preset.accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          preset.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${preset.resolutionText} · ${preset.density} DPI · ${preset.aspectRatio}',
                          style: TextStyle(
                            fontSize: 11.2,
                            fontWeight: FontWeight.w700,
                            color: preset.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: preset.isActive
                        ? preset.accentColor.withValues(alpha: 0.18)
                        : colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: preset.isActive
                          ? preset.accentColor.withValues(alpha: 0.45)
                          : colors.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (preset.isActive) ...<Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: preset.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        preset.isActive ? 'ACTIVE' : preset.badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: preset.isActive
                              ? preset.accentColor
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              preset.description,
              style: TextStyle(
                fontSize: 11.8,
                height: 1.35,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolutionMetricPill extends StatelessWidget {
  const _ResolutionMetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(
            alpha: dark ? 0.35 : 0.6,
          ),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: colors.onSurfaceVariant),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ZramSwapScreen extends StatefulWidget {
  const ZramSwapScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<ZramSwapScreen> createState() => _ZramSwapScreenState();
}

class _ZramSwapScreenState extends State<ZramSwapScreen> {
  int? _optimisticSizeMb;
  int? _optimisticAlgCode;
  int? _optimisticSwappiness;
  int _customSliderMb = 8192;
  bool _isCustomMode = false;
  bool _applying = false;
  bool _compacting = false;

  // Glass Frosted HUD Toast State
  String _toastTag = 'ZRAM ENGINE';
  String _toastMessage = '';
  IconData _toastIcon = Icons.check_circle_rounded;
  Color _toastAccent = const Color(0xFF67C2FF);
  bool _toastVisible = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
    final int currentSize = RodinBackend.instance.extendedValue(39);
    final int activeSize = currentSize >= 0 ? currentSize : 8192;
    _customSliderMb = activeSize;
    const List<int> standardPresets = <int>[0, 4096, 8192, 12288, 16384];
    _isCustomMode = !standardPresets.contains(activeSize);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showGlassToast(
    String tag,
    String message,
    IconData icon,
    Color accent,
  ) {
    _toastTimer?.cancel();
    setState(() {
      _toastTag = tag;
      _toastMessage = message;
      _toastIcon = icon;
      _toastAccent = accent;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() => _toastVisible = false);
      }
    });
  }

  void _applyPresetSize(int sizeMb, String title, IconData icon, Color accent) {
    RodinHaptics.confirm();
    setState(() {
      _isCustomMode = false;
      _optimisticSizeMb = sizeMb;
      _customSliderMb = sizeMb > 0 ? sizeMb : _customSliderMb;
      _applying = true;
    });

    _showGlassToast(
      'ZRAM PRESET',
      sizeMb == 0
          ? 'Disabled · Physical RAM Only'
          : 'Applied $title (${sizeMb} MB)',
      icon,
      accent,
    );

    RodinBackend.instance.setZramSize(sizeMb);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() => _applying = false);
      }
    });
  }

  void _applyCustomSize(int sizeMb) {
    RodinHaptics.confirm();
    setState(() {
      _isCustomMode = true;
      _optimisticSizeMb = sizeMb;
      _customSliderMb = sizeMb;
      _applying = true;
    });

    _showGlassToast(
      'CUSTOM SWAP',
      sizeMb == 0
          ? 'Disabled · Physical RAM Only'
          : 'Set to ${(sizeMb / 1024).toStringAsFixed(1)} GB ($sizeMb MB)',
      Icons.tune_rounded,
      const Color(0xFF67C2FF),
    );

    RodinBackend.instance.setZramSize(sizeMb);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() => _applying = false);
      }
    });
  }

  void _applyAlgorithm(int algCode) {
    RodinHaptics.confirm();
    setState(() => _optimisticAlgCode = algCode);

    final List<String> algNames = <String>['LZ4', 'ZSTD', 'LZO-RLE', 'LZO'];
    final String name = algCode >= 0 && algCode < algNames.length
        ? algNames[algCode]
        : 'LZ4';

    _showGlassToast(
      'KERNEL ENGINE',
      'Switched Compression to $name',
      Icons.compress_rounded,
      const Color(0xFF41C98A),
    );

    RodinBackend.instance.setZramAlgorithm(algCode);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      RodinBackend.instance.refresh();
    });
  }

  void _applySwappiness(int swappiness) {
    RodinHaptics.confirm();
    setState(() => _optimisticSwappiness = swappiness);

    _showGlassToast(
      'KERNEL SWAPPINESS',
      'Swappiness Set to $swappiness',
      Icons.speed_rounded,
      const Color(0xFFFFB84D),
    );

    RodinBackend.instance.setZramSwappiness(swappiness);
    RodinBackend.instance.refresh();
  }

  void _compactMemory() {
    if (_compacting) return;
    RodinHaptics.confirm();
    setState(() => _compacting = true);

    _showGlassToast(
      'MEMORY COMPACTION',
      'Compacting ZRAM Pages & Defragmenting...',
      Icons.cleaning_services_rounded,
      const Color(0xFF74E6C6),
    );

    RodinBackend.instance.compactZram();
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() => _compacting = false);
        _showGlassToast(
          'MEMORY COMPACTION',
          'ZRAM Compaction Complete',
          Icons.check_circle_rounded,
          const Color(0xFF41C98A),
        );
      }
    });
  }

  void _resetDefaults() {
    RodinHaptics.confirm();
    setState(() {
      _isCustomMode = false;
      _optimisticSizeMb = 8192;
      _optimisticAlgCode = 0;
      _optimisticSwappiness = 100;
      _customSliderMb = 8192;
    });

    _showGlassToast(
      'SYSTEM RESTORE',
      'Reset to 8 GB Stock Optimal Defaults',
      Icons.restart_alt_rounded,
      const Color(0xFF41C98A),
    );

    RodinBackend.instance.setZramAlgorithm(0);
    RodinBackend.instance.setZramSwappiness(100);
    RodinBackend.instance.setZramSize(8192);
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      RodinBackend.instance.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = isDark
        ? const Color(0xFF67C2FF)
        : const Color(0xFF0077E6);

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int rawSizeMb = backend.extendedValue(39);
        final int activeSizeMb =
            _optimisticSizeMb ?? (rawSizeMb >= 0 ? rawSizeMb : 8192);

        final int origMb = backend.extendedValue(40) >= 0
            ? backend.extendedValue(40)
            : 3192;
        final int comprMb = backend.extendedValue(41) >= 0
            ? backend.extendedValue(41)
            : 1067;
        final int memUsedMb = backend.extendedValue(42) >= 0
            ? backend.extendedValue(42)
            : 1067;

        final int rawSwappiness = backend.extendedValue(43);
        final int swappiness =
            _optimisticSwappiness ?? (rawSwappiness >= 0 ? rawSwappiness : 100);

        final int rawAlgCode = backend.extendedValue(44);
        final int algCode =
            _optimisticAlgCode ?? (rawAlgCode >= 0 ? rawAlgCode : 0);

        final bool isOff = activeSizeMb == 0;
        final double ratio = comprMb > 0 ? (origMb / comprMb) : 1.0;
        final int ramSavedMb = (origMb - comprMb).clamp(0, 32768);

        final List<String> algLabels = <String>[
          'LZ4 (Ultra Fast)',
          'ZSTD (Max Ratio)',
          'LZO-RLE (Balanced)',
          'LZO (Legacy)',
        ];
        final String activeAlgLabel = algCode >= 0 && algCode < algLabels.length
            ? algLabels[algCode]
            : 'LZ4 (Ultra Fast)';

        final List<_ZramPreset> presets = <_ZramPreset>[
          _ZramPreset(
            title: 'Disabled (0 GB)',
            badge: 'PURE RAM',
            sizeMb: 0,
            description:
                'Disables compressed swap partition completely. Pure physical RAM only with zero CPU memory overhead.',
            accentColor: const Color(0xFFFFB84D),
            icon: Icons.power_settings_new_rounded,
            isActive: !_isCustomMode && activeSizeMb == 0,
          ),
          _ZramPreset(
            title: '4 GB (Light RAM Plus)',
            badge: '4 GB SWAP',
            sizeMb: 4096,
            description:
                'Provides 4,096 MB compressed memory space. Ideal for light usage and minimal background caching.',
            accentColor: const Color(0xFF59BCFF),
            icon: Icons.storage_rounded,
            isActive: !_isCustomMode && activeSizeMb == 4096,
          ),
          _ZramPreset(
            title: '8 GB (Stock Optimal)',
            badge: '8 GB DEFAULT',
            sizeMb: 8192,
            description:
                'Recommended factory configuration for Rodin. Perfect balance of multitasking speed and battery life.',
            accentColor: const Color(0xFF41C98A),
            icon: Icons.verified_rounded,
            isActive: !_isCustomMode && activeSizeMb == 8192,
          ),
          _ZramPreset(
            title: '12 GB (Power Multitask)',
            badge: '12 GB POWER',
            sizeMb: 12288,
            description:
                'High-capacity 12,288 MB virtual memory buffer. Keeps dozens of apps alive in background with zero redraws.',
            accentColor: const Color(0xFFB087FF),
            icon: Icons.all_inclusive_rounded,
            isActive: !_isCustomMode && activeSizeMb == 12288,
          ),
          _ZramPreset(
            title: '16 GB (Extreme Gaming)',
            badge: '16 GB MAX',
            sizeMb: 16384,
            description:
                'Maximum 16,384 MB virtual RAM headroom. Optimized for demanding 3D games, emulation, and heavy tasks.',
            accentColor: const Color(0xFFFF8A65),
            icon: Icons.rocket_launch_rounded,
            isActive: !_isCustomMode && activeSizeMb == 16384,
          ),
        ];

        return Stack(
          children: <Widget>[
            RodinScrollPage(
              children: <Widget>[
                DetailHeader(
                  title: 'ZRAM & Swap Manager',
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 4),
                Text(
                  'Hardware memory compression, swap sizing, and kernel swappiness tuning for Rodin',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                // HERO DASHBOARD CARD
                SurfaceCard(
                  accent: isOff ? const Color(0xFFFFB84D) : accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  (isOff
                                          ? const Color(0xFFFFB84D)
                                          : const Color(0xFF41C98A))
                                      .withValues(alpha: 0.16),
                              border: Border.all(
                                color:
                                    (isOff
                                            ? const Color(0xFFFFB84D)
                                            : const Color(0xFF41C98A))
                                        .withValues(alpha: 0.3),
                                width: 1.2,
                              ),
                            ),
                            child: Icon(
                              isOff
                                  ? Icons.power_settings_new_rounded
                                  : Icons.memory_rounded,
                              size: 26,
                              color: isOff
                                  ? const Color(0xFFFFB84D)
                                  : const Color(0xFF41C98A),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Text(
                                      isOff
                                          ? 'Swap Disabled'
                                          : '${(activeSizeMb / 1024).toStringAsFixed(1)} GB ZRAM',
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color:
                                            (isOff
                                                    ? const Color(0xFFFFB84D)
                                                    : const Color(0xFF41C98A))
                                                .withValues(alpha: 0.18),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isOff
                                                  ? const Color(0xFFFFB84D)
                                                  : const Color(0xFF41C98A),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isOff ? 'OFF' : 'ACTIVE',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w900,
                                              color: isOff
                                                  ? const Color(0xFFFFB84D)
                                                  : const Color(0xFF41C98A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isOff
                                      ? 'Physical RAM only · Zero compressed swap'
                                      : '$activeAlgLabel · $swappiness Swappiness',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // TELEMETRY METRIC PILLS
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _ZramMetricPill(
                              label: 'EFFICIENCY',
                              value: isOff
                                  ? '1.00×'
                                  : '${ratio.toStringAsFixed(2)}×',
                              subvalue: isOff ? 'Disabled' : 'Real-time',
                              accent: const Color(0xFF41C98A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ZramMetricPill(
                              label: 'RAM SAVED',
                              value: isOff ? '0 MB' : '+$ramSavedMb MB',
                              subvalue: isOff
                                  ? 'No swap'
                                  : '$origMb in $comprMb MB',
                              accent: const Color(0xFF67C2FF),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ZramMetricPill(
                              label: 'USED SWAP',
                              value: isOff ? '0 MB' : '$memUsedMb MB',
                              subvalue: isOff ? 'Off' : 'of $activeSizeMb MB',
                              accent: const Color(0xFFB087FF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // PRESETS SECTION (MAX 16 GB)
                const Text(
                  'QUICK ZRAM SIZE PRESETS (MAX 16 GB)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 8),

                for (final _ZramPreset preset in presets) ...<Widget>[
                  _ZramPresetCard(
                    preset: preset,
                    applying: _applying,
                    onTap: () => _applyPresetSize(
                      preset.sizeMb,
                      preset.title,
                      preset.icon,
                      preset.accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 6),

                // CUSTOM SIZE TUNER (MAX 25 GB)
                SurfaceCard(
                  accent: _isCustomMode ? const Color(0xFF67C2FF) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.tune_rounded, size: 20, color: accent),
                          const SizedBox(width: 8),
                          const Text(
                            'Custom Swap Size',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _customSliderMb == 0
                                ? 'Disabled'
                                : '${(_customSliderMb / 1024).toStringAsFixed(1)} GB',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _customSliderMb == 0
                            ? 'Disabled: Pure physical RAM only with zero compressed swap.'
                            : 'Allocates ${_customSliderMb} MB compressed virtual swap partition (up to 25.0 GB).',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _customSliderMb.toDouble().clamp(0, 25600),
                        min: 0,
                        max: 25600,
                        divisions: 25,
                        activeColor: accent,
                        onChangeStart: (_) => RodinHaptics.segment(),
                        onChanged: (double val) {
                          setState(() {
                            _customSliderMb = val.round();
                            _isCustomMode = true;
                          });
                          RodinHaptics.frequentSegment();
                        },
                        onChangeEnd: (double val) {
                          RodinHaptics.confirm();
                          _applyCustomSize(val.round());
                        },
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _applying
                              ? null
                              : () => _applyCustomSize(_customSliderMb),
                          icon: _applying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            _applying ? 'Applying...' : 'Apply',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // COMPRESSION ALGORITHM SELECTOR
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Row(
                        children: <Widget>[
                          Icon(
                            Icons.compress_rounded,
                            size: 20,
                            color: Color(0xFF41C98A),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Compression Algorithm',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the real-time kernel compression engine for the ZRAM block device.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _AlgorithmOptionCard(
                        title: 'LZ4 (Ultra Fast)',
                        badge: 'RECOMMENDED',
                        description:
                            'Highest decompression speed and near-zero CPU overhead. Ideal for 120 FPS UI and gaming.',
                        code: 0,
                        activeCode: algCode,
                        accent: const Color(0xFF41C98A),
                        onTap: () => _applyAlgorithm(0),
                      ),
                      const SizedBox(height: 6),
                      _AlgorithmOptionCard(
                        title: 'ZSTD (Maximum Density)',
                        badge: 'MAX RATIO',
                        description:
                            'State-of-the-art compression ratio. Compresses up to 40% more data into physical RAM.',
                        code: 1,
                        activeCode: algCode,
                        accent: const Color(0xFF67C2FF),
                        onTap: () => _applyAlgorithm(1),
                      ),
                      const SizedBox(height: 6),
                      _AlgorithmOptionCard(
                        title: 'LZO-RLE (Balanced)',
                        badge: 'BALANCED',
                        description:
                            'Standard Android kernel algorithm with run-length zero-page acceleration.',
                        code: 2,
                        activeCode: algCode,
                        accent: const Color(0xFFB087FF),
                        onTap: () => _applyAlgorithm(2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // SWAPPINESS TUNER
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.speed_rounded,
                            size: 20,
                            color: Color(0xFFFFB84D),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Kernel Swappiness',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$swappiness',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFFB84D),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        swappiness < 60
                            ? 'Conservative: Avoids swapping memory pages unless physical RAM is critically low.'
                            : swappiness <= 100
                            ? 'Balanced (Stock 100): Optimal balance for daily app usage and multi-tasking.'
                            : swappiness <= 160
                            ? 'Aggressive: Proactively pushes idle background apps into ZRAM to maximize free RAM for active apps.'
                            : 'Maximum: Aggressively keeps foreground memory free for heavy gaming.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: swappiness.toDouble().clamp(0, 200),
                        min: 0,
                        max: 200,
                        divisions: 40,
                        activeColor: const Color(0xFFFFB84D),
                        onChangeStart: (_) => RodinHaptics.segment(),
                        onChanged: (double val) {
                          setState(() => _optimisticSwappiness = val.round());
                          RodinHaptics.frequentSegment();
                        },
                        onChangeEnd: (double val) =>
                            _applySwappiness(val.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // INSTANT ACTIONS
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Instant Memory Tools',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _compacting ? null : _compactMemory,
                              icon: _compacting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.cleaning_services_rounded,
                                      size: 16,
                                    ),
                              label: Text(
                                _compacting ? 'Compacting...' : 'Compact ZRAM',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _applying ? null : _resetDefaults,
                              icon: const Icon(
                                Icons.restart_alt_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Reset 8GB Default',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // DIAGNOSTICS & HARDWARE SPEC CARD
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ZRAM Hardware Architecture',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DiagnosticRow(
                        label: 'Block Device Node',
                        good: true,
                        detail: '/dev/block/zram0',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Swap Partition Status',
                        good: !isOff,
                        detail: isOff ? 'Unmounted' : 'Active (Priority 32758)',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Kernel Memory Compaction',
                        good: true,
                        detail: 'Supported (/sys/block/zram0/compact)',
                      ),
                      const Divider(height: 14),
                      _DiagnosticRow(
                        label: 'Memory Stream Decompression',
                        good: true,
                        detail: 'Multi-stream Lockless Kernel Engine',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // FROSTED GLASS HUD TOAST
            _ZramGlassToast(
              tag: _toastTag,
              message: _toastMessage,
              icon: _toastIcon,
              accent: _toastAccent,
              visible: _toastVisible,
            ),
          ],
        );
      },
    );
  }
}

class _ZramGlassToast extends StatelessWidget {
  const _ZramGlassToast({
    required this.tag,
    required this.message,
    required this.icon,
    required this.accent,
    required this.visible,
  });

  final String tag;
  final String message;
  final IconData icon;
  final Color accent;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 380),
      curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
      bottom: visible ? 84 : -110,
      left: 16,
      right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: visible ? 1.0 : 0.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xDD121924)
                    : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accent.withValues(alpha: dark ? 0.35 : 0.45),
                  width: 1.2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: dark ? 0.18 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: dark ? 0.18 : 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_rounded, size: 12, color: accent),
                        const SizedBox(width: 3),
                        Text(
                          'APPLIED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZramPreset {
  const _ZramPreset({
    required this.title,
    required this.badge,
    required this.sizeMb,
    required this.description,
    required this.accentColor,
    required this.icon,
    required this.isActive,
  });

  final String title;
  final String badge;
  final int sizeMb;
  final String description;
  final Color accentColor;
  final IconData icon;
  final bool isActive;
}

class _ZramPresetCard extends StatelessWidget {
  const _ZramPresetCard({
    required this.preset,
    required this.applying,
    required this.onTap,
  });

  final _ZramPreset preset;
  final bool applying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: applying || preset.isActive ? null : onTap,
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        accent: preset.isActive ? preset.accentColor : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: preset.accentColor.withValues(
                      alpha: dark ? 0.14 : 0.09,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: preset.accentColor.withValues(
                        alpha: dark ? 0.28 : 0.18,
                      ),
                    ),
                  ),
                  child: Icon(preset.icon, size: 19, color: preset.accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          preset.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          preset.sizeMb == 0
                              ? 'Pure Physical RAM · 0 MB Swap'
                              : '${preset.sizeMb} MB · ${(preset.sizeMb / 1024).toStringAsFixed(1)} GB Capacity',
                          style: TextStyle(
                            fontSize: 11.2,
                            fontWeight: FontWeight.w700,
                            color: preset.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: preset.isActive
                        ? preset.accentColor.withValues(alpha: 0.18)
                        : colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: preset.isActive
                          ? preset.accentColor.withValues(alpha: 0.45)
                          : colors.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (preset.isActive) ...<Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: preset.accentColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        preset.isActive ? 'ACTIVE' : preset.badge,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: preset.isActive
                              ? preset.accentColor
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.description,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZramMetricPill extends StatelessWidget {
  const _ZramMetricPill({
    required this.label,
    required this.value,
    required this.subvalue,
    required this.accent,
  });

  final String label;
  final String value;
  final String subvalue;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.6),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: accent,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subvalue,
            style: TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AlgorithmOptionCard extends StatelessWidget {
  const _AlgorithmOptionCard({
    required this.title,
    required this.badge,
    required this.description,
    required this.code,
    required this.activeCode,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String description;
  final int code;
  final int activeCode;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = code == activeCode;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: isActive ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isActive
              ? accent.withValues(alpha: 0.12)
              : colors.surfaceContainerHighest.withValues(alpha: 0.3),
          border: Border.all(
            color: isActive ? accent : colors.outline.withValues(alpha: 0.12),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: accent.withValues(alpha: 0.16),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: accent,
                    ),
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Icon(Icons.check_circle_rounded, size: 18, color: accent)
                else
                  Icon(
                    Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class MaliGpuScreen extends StatefulWidget {
  const MaliGpuScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<MaliGpuScreen> createState() => _MaliGpuScreenState();
}

class _MaliGpuScreenState extends State<MaliGpuScreen> {
  int? _optimisticProfile;
  bool? _optimisticUncap;
  int? _optimisticMinFreq;
  int? _optimisticMaxFreq;
  int? _optimisticGov;
  bool? _optimisticGedBoost;
  int? _optimisticPowerPolicy;
  Timer? _interactionTimer;

  // Glass Frosted HUD Toast State
  String _toastTag = 'MALI GPU';
  String _toastMessage = '';
  IconData _toastIcon = Icons.sports_esports_rounded;
  Color _toastAccent = const Color(0xFFFF5252);
  bool _toastVisible = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _interactionTimer?.cancel();
    super.dispose();
  }

  void _showGlassToast(
    String tag,
    String message,
    IconData icon,
    Color accent,
  ) {
    _toastTimer?.cancel();
    setState(() {
      _toastTag = tag;
      _toastMessage = message;
      _toastIcon = icon;
      _toastAccent = accent;
      _toastVisible = true;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() => _toastVisible = false);
      }
    });
  }

  void _applyPreset(
    int profileCode,
    int min,
    int max,
    int gov,
    bool ged,
    int powerPolicy,
    String name,
    IconData icon,
    Color accent,
  ) {
    RodinHaptics.confirm();
    final bool willUncap = profileCode == 3;

    setState(() {
      _optimisticProfile = profileCode;
      _optimisticMinFreq = min;
      _optimisticMaxFreq = max;
      _optimisticGov = gov;
      _optimisticGedBoost = ged;
      _optimisticPowerPolicy = powerPolicy;
      _optimisticUncap = willUncap;
    });

    _showGlassToast(
      'GPU PRESET',
      'Applied $name ($min–$max MHz)',
      icon,
      accent,
    );

    RodinBackend.instance.setPerformanceProfile(profileCode);

    _interactionTimer?.cancel();
    _interactionTimer = Timer(const Duration(milliseconds: 600), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() {
          _optimisticProfile = null;
          _optimisticUncap = null;
          _optimisticMinFreq = null;
          _optimisticMaxFreq = null;
          _optimisticGov = null;
          _optimisticGedBoost = null;
          _optimisticPowerPolicy = null;
        });
      }
    });
  }

  void _applyPowerPolicy(int policyCode) {
    RodinHaptics.confirm();
    setState(() => _optimisticPowerPolicy = policyCode);

    final String name = policyCode == 1
        ? 'Always-On (Zero Latency)'
        : 'Coarse Demand (Dynamic)';
    _showGlassToast(
      'MALI POWER POLICY',
      'Set Policy to $name',
      policyCode == 1 ? Icons.bolt_rounded : Icons.eco_rounded,
      policyCode == 1 ? const Color(0xFFFF5252) : const Color(0xFF67C2FF),
    );

    RodinBackend.instance.setGpuPowerPolicy(policyCode);
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() => _optimisticPowerPolicy = null);
      }
    });
  }

  void _applyGovernor(int govCode) {
    RodinHaptics.confirm();
    setState(() => _optimisticGov = govCode);

    const List<String> names = <String>[
      'Simple On-Demand',
      'Performance',
      'Powersave',
      'Userspace',
      'OEM Stock',
    ];
    final String name = govCode >= 0 && govCode < names.length
        ? names[govCode]
        : 'Simple On-Demand';

    _showGlassToast(
      'DEVFREQ GOVERNOR',
      'Switched Governor to $name',
      Icons.tune_rounded,
      const Color(0xFF67C2FF),
    );

    RodinBackend.instance.setGpuDevfreqGovernor(govCode);
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() => _optimisticGov = null);
      }
    });
  }

  void _resetDefault() {
    RodinHaptics.confirm();
    setState(() {
      _optimisticProfile = 0;
      _optimisticUncap = false;
      _optimisticMinFreq = 260;
      _optimisticMaxFreq = 1300;
      _optimisticGov = 4;
      _optimisticGedBoost = false;
      _optimisticPowerPolicy = 0;
    });

    _showGlassToast(
      'GPU RESET',
      'Restored MediaTek Stock Balanced Settings',
      Icons.restore_rounded,
      const Color(0xFF67C2FF),
    );

    RodinBackend.instance.setPerformanceProfile(0);
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      RodinBackend.instance.refresh();
      if (mounted) {
        setState(() {
          _optimisticProfile = null;
          _optimisticUncap = null;
          _optimisticMinFreq = null;
          _optimisticMaxFreq = null;
          _optimisticGov = null;
          _optimisticGedBoost = null;
          _optimisticPowerPolicy = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;

        // Telemetry Slots
        final int liveLoad = backend.extendedValue(45) >= 0
            ? backend.extendedValue(45)
            : 0;
        final int liveCurFreq = backend.extendedValue(46) >= 0
            ? backend.extendedValue(46)
            : 0;
        final int rawMinFreq = backend.extendedValue(47) >= 0
            ? backend.extendedValue(47)
            : 260;
        final int rawMaxFreq = backend.extendedValue(48) >= 0
            ? backend.extendedValue(48)
            : 1300;
        final int rawGovCode = backend.extendedValue(49) >= 0
            ? backend.extendedValue(49)
            : 0;
        final int rawGedBoost = backend.extendedValue(50) >= 0
            ? backend.extendedValue(50)
            : 0;
        final int thermalState = backend.extendedValue(51);
        final int rawUncap = backend.extendedValue(52);
        final int rawPowerPolicy = backend.extendedValue(59) >= 0
            ? backend.extendedValue(59)
            : 0;
        final bool profileVerified =
            _optimisticProfile == null && backend.extendedValue(13) == 1;

        final int activeMinFreq = _optimisticMinFreq ?? rawMinFreq;
        final int activeMaxFreq = _optimisticMaxFreq ?? rawMaxFreq;
        final int activeGov = _optimisticGov ?? rawGovCode;
        final bool activeGedBoost = _optimisticGedBoost ?? (rawGedBoost == 1);
        final int activePowerPolicy = _optimisticPowerPolicy ?? rawPowerPolicy;
        final bool isUncapped = _optimisticUncap ?? (rawUncap == 1);
        final int activePerf =
            _optimisticProfile ??
            (snapshot.performanceProfile >= 0
                ? snapshot.performanceProfile
                : (backend.extendedValue(19) == 1 &&
                          backend.extendedValue(20) >= 0
                      ? backend.extendedValue(20)
                      : 0));
        final int requestedMaxFreq = switch (activePerf) {
          3 => 1300,
          1 => 1300,
          2 => 598,
          _ => rawMaxFreq,
        };
        final bool hasHardwareReadback = _optimisticProfile == null;
        final bool isThrottledByOs =
            hasHardwareReadback &&
            ((activePerf == 3 &&
                    ((liveCurFreq > 0 && liveCurFreq < 1300) ||
                        rawMaxFreq < requestedMaxFreq)) ||
                ((activePerf == 1 || activePerf == 2) &&
                    rawMaxFreq < requestedMaxFreq));
        final bool isBeast =
            activePerf == 3 ||
            isUncapped ||
            (activeMinFreq == 1300 && activeMaxFreq == 1300);
        final bool isGaming = !isBeast && activePerf == 1;
        final bool isBattery = !isBeast && activePerf == 2;
        final Color mainColor = isBeast
            ? const Color(0xFFFF5252)
            : (isGaming
                  ? const Color(0xFFFFB84D)
                  : (isBattery
                        ? const Color(0xFF35C997)
                        : const Color(0xFF4EA8DE)));
        final IconData modeIcon = isBeast
            ? Icons.bolt_rounded
            : (isGaming
                  ? Icons.sports_esports_rounded
                  : (isBattery
                        ? Icons.energy_savings_leaf_rounded
                        : Icons.balance_rounded));
        final String modeSummary = isBeast
            ? (liveCurFreq > 0
                  ? 'Live: $liveCurFreq MHz · Fixed at 1.30 GHz'
                  : 'Applying fixed 1.30 GHz lock')
            : (isGaming
                  ? (liveCurFreq > 0
                        ? 'Live: $liveCurFreq MHz · Scaling freely to 1.30 GHz'
                        : 'Full-range scaling · 260–1300 MHz')
                  : (isBattery
                        ? (liveCurFreq > 0
                              ? 'Live: $liveCurFreq MHz · Efficiency cap at 598 MHz'
                              : 'Efficiency range · 260–598 MHz')
                        : (liveCurFreq > 0
                              ? 'Live: $liveCurFreq MHz · OEM-managed behavior'
                              : 'Vendor-managed clocks and power policy')));

        return Stack(
          children: <Widget>[
            RodinScrollPage(
              children: <Widget>[
                DetailHeader(
                  title: 'Mali GPU & GED',
                  onBack: widget.onBack,
                  trailing: PressScale(
                    onTap: _resetDefault,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.restore_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Live Mali telemetry, GPU modes, GED boost, and frequency policy',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),

                // Top Glass Hero Banner
                HeroCard(
                  icon: modeIcon,
                  accent: mainColor,
                  title: 'Mali-G720 Graphics',
                  subtitle: modeSummary,
                ),
                const SizedBox(height: 12),

                // 1. HERO GPU DASHBOARD
                _buildHeroDashboard(
                  isDark: isDark,
                  colors: colors,
                  activeProfile: activePerf,
                  liveLoad: liveLoad,
                  liveCurFreq: liveCurFreq,
                  minFreq: activeMinFreq,
                  maxFreq: activeMaxFreq,
                  isUncapped: isUncapped,
                  isThrottledByOs: isThrottledByOs,
                  profileVerified: profileVerified,
                ),
                const SizedBox(height: 12),

                // 2. QUICK GPU PRESETS (4 TILES)
                _buildPresetsGrid(
                  isDark: isDark,
                  colors: colors,
                  activeProfile: activePerf,
                  minFreq: activeMinFreq,
                  maxFreq: activeMaxFreq,
                  isUncapped: isUncapped,
                  onSelect: _applyPreset,
                ),
                const SizedBox(height: 12),

                // 3. MEDIATEK GED & GOVERNOR ENGINE
                _buildGedAndGovernorCard(
                  isDark: isDark,
                  colors: colors,
                  gedBoost: activeGedBoost,
                  gedProfileEnabled: isBeast || isGaming,
                  govCode: activeGov,
                  powerPolicyCode: activePowerPolicy,
                  onSelectGov: _applyGovernor,
                  onSelectPowerPolicy: _applyPowerPolicy,
                ),
                const SizedBox(height: 12),

                // 4. HARDWARE ARCHITECTURE & TELEMETRY
                _buildHardwareDetailsCard(
                  isDark: isDark,
                  colors: colors,
                  thermalState: thermalState,
                ),
              ],
            ),

            // FROSTED GLASS HUD TOAST (BOTTOM POSITIONED)
            _MaliGlassToast(
              tag: _toastTag,
              message: _toastMessage,
              icon: _toastIcon,
              accent: _toastAccent,
              visible: _toastVisible,
            ),
          ],
        );
      },
    );
  }

  // 1. HERO GPU DASHBOARD WIDGET
  Widget _buildHeroDashboard({
    required bool isDark,
    required ColorScheme colors,
    required int activeProfile,
    required int liveLoad,
    required int liveCurFreq,
    required int minFreq,
    required int maxFreq,
    required bool isUncapped,
    required bool isThrottledByOs,
    required bool profileVerified,
  }) {
    final bool isBeast =
        activeProfile == 3 ||
        isUncapped ||
        (minFreq == 1300 && maxFreq == 1300);
    final bool isGaming = !isBeast && activeProfile == 1;
    final bool isBattery = !isBeast && activeProfile == 2;

    final Color mainColor = isBeast
        ? const Color(0xFFFF5252)
        : (isGaming
              ? const Color(0xFFFFB84D)
              : (isBattery
                    ? const Color(0xFF35C997)
                    : const Color(0xFF4EA8DE)));

    final String activeDisplayClock = liveCurFreq > 0 ? '$liveCurFreq' : '—';

    final String clockSubtext = isBeast
        ? (isThrottledByOs
              ? 'External clock limit detected · 1300 MHz remains the target'
              : (profileVerified && liveCurFreq == 1300
                    ? 'Fixed 1.30 GHz target verified from live hardware telemetry'
                    : 'Fixed 1.30 GHz target requested · waiting for live verification'))
        : (isGaming
              ? (liveCurFreq > 0
                    ? 'Dynamic Gaming Load ($liveCurFreq MHz · 1.30 GHz Ceiling)'
                    : 'Standby Dynamic (260 – 1300 MHz · GED Boost Active)')
              : (isBattery
                    ? (liveCurFreq > 0
                          ? 'Live $liveCurFreq MHz · $minFreq–$maxFreq MHz Battery Range'
                          : 'Waiting for battery-profile GPU telemetry')
                    : (liveCurFreq > 0
                          ? 'Active OEM OPP ($liveCurFreq MHz)'
                          : 'Waiting for OEM GPU telemetry')));

    final String badgeTitle = isBeast
        ? '1.30 GHz FIXED TARGET'
        : (isGaming
              ? 'GAMING DYNAMIC BOOST'
              : (isBattery ? 'BATTERY SAVER CLAMP' : 'DYNAMIC BALANCED'));

    return SurfaceCard(
      accent: mainColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header Status Badge
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor.withValues(alpha: 0.16),
                  border: Border.all(
                    color: mainColor.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  isBeast ? Icons.bolt_rounded : Icons.sports_esports_rounded,
                  size: 22,
                  color: mainColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      badgeTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: mainColor,
                      ),
                    ),
                    Text(
                      'Dimensity 8400-Ultra · Mali-G720 7-Core',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (maxFreq >= 1300)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    '1.30 GHz Target',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFF5252),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Big Clock Speed Readout
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                activeDisplayClock,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'MHz',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: mainColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            clockSubtext,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 16),

          // Live GPU Load Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'LIVE HARDWARE UTILIZATION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$liveLoad%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: liveLoad > 80
                          ? const Color(0xFFFF5252)
                          : (liveLoad > 40
                                ? const Color(0xFFFFB84D)
                                : const Color(0xFF41C98A)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (liveLoad.clamp(0, 100)) / 100.0,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    liveLoad > 80
                        ? const Color(0xFFFF5252)
                        : (liveLoad > 40
                              ? const Color(0xFFFFB84D)
                              : const Color(0xFF41C98A)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Telemetry Pills 2x2 Grid
          Row(
            children: <Widget>[
              Expanded(
                child: _buildTelemetryPill(
                  isDark: isDark,
                  colors: colors,
                  label: 'PROFILE WRITE',
                  value: isThrottledByOs
                      ? 'Clock Below Target'
                      : (profileVerified ? 'Verified' : 'Applying'),
                  accent: isThrottledByOs || !profileVerified
                      ? const Color(0xFFFFB84D)
                      : const Color(0xFF41C98A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTelemetryPill(
                  isDark: isDark,
                  colors: colors,
                  label: 'ACTIVE RANGE',
                  value: '$minFreq – $maxFreq MHz',
                  accent: mainColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryPill({
    required bool isDark,
    required ColorScheme colors,
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171C28) : const Color(0xFFEEF2F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  // 2. QUICK GPU PRESETS (4 TILES)
  Widget _buildPresetsGrid({
    required bool isDark,
    required ColorScheme colors,
    required int activeProfile,
    required int minFreq,
    required int maxFreq,
    required bool isUncapped,
    required Function(
      int profile,
      int min,
      int max,
      int gov,
      bool ged,
      int powerPolicy,
      String name,
      IconData icon,
      Color accent,
    )
    onSelect,
  }) {
    final bool isBeast =
        activeProfile == 3 ||
        (activeProfile < 0 && isUncapped && minFreq == 1300 && maxFreq == 1300);
    final bool isGaming = activeProfile == 1;
    final bool isBattery = activeProfile == 2;
    final bool isStock = !isBeast && !isGaming && !isBattery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'GPU PERFORMANCE MODES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _buildPresetCard(
                isDark: isDark,
                colors: colors,
                title: 'Extreme Beast',
                range: '1300 MHz fixed · No downclock',
                icon: Icons.bolt_rounded,
                accent: const Color(0xFFFF5252),
                isActive: isBeast,
                onTap: () => onSelect(
                  3,
                  1300,
                  1300,
                  1,
                  true,
                  1,
                  'Extreme Beast · Fixed 1.30 GHz',
                  Icons.bolt_rounded,
                  const Color(0xFFFF5252),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPresetCard(
                isDark: isDark,
                colors: colors,
                title: 'Gaming Dynamic',
                range: '260–1300 MHz · Full-range scaling',
                icon: Icons.sports_esports_rounded,
                accent: const Color(0xFFFFB84D),
                isActive: isGaming,
                onTap: () => onSelect(
                  1,
                  260,
                  1300,
                  0,
                  true,
                  1,
                  'Gaming Dynamic · Full Range',
                  Icons.sports_esports_rounded,
                  const Color(0xFFFFB84D),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: _buildPresetCard(
                isDark: isDark,
                colors: colors,
                title: 'Stock Balanced',
                range: 'OEM range · Vendor managed',
                icon: Icons.balance_rounded,
                accent: const Color(0xFF67C2FF),
                isActive: isStock,
                onTap: () => onSelect(
                  0,
                  260,
                  1300,
                  4,
                  false,
                  0,
                  'Stock Balanced · OEM Control',
                  Icons.balance_rounded,
                  const Color(0xFF67C2FF),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPresetCard(
                isDark: isDark,
                colors: colors,
                title: 'Battery Saver',
                range: '260–598 MHz · Efficiency cap',
                icon: Icons.energy_savings_leaf_rounded,
                accent: const Color(0xFF41C98A),
                isActive: isBattery,
                onTap: () => onSelect(
                  2,
                  260,
                  598,
                  2,
                  false,
                  0,
                  'Battery Saver · 598 MHz Cap',
                  Icons.energy_savings_leaf_rounded,
                  const Color(0xFF41C98A),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetCard({
    required bool isDark,
    required ColorScheme colors,
    required String title,
    required String range,
    required IconData icon,
    required Color accent,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          constraints: const BoxConstraints(minHeight: 108),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141822) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? accent
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
              width: isActive ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: accent),
                  const Spacer(),
                  if (isActive)
                    Icon(Icons.check_circle_rounded, size: 16, color: accent)
                  else
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                range,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.25,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 5. MEDIATEK GED & GOVERNOR ENGINE
  Widget _buildGedAndGovernorCard({
    required bool isDark,
    required ColorScheme colors,
    required bool gedBoost,
    required bool gedProfileEnabled,
    required int govCode,
    required int powerPolicyCode,
    required ValueChanged<int> onSelectGov,
    required ValueChanged<int> onSelectPowerPolicy,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Profile-controlled GED Instant Boost status
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  size: 18,
                  color: Color(0xFFFF5252),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'MediaTek GED Instant Boost',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      gedProfileEnabled
                          ? (gedBoost
                                ? 'Active for this performance mode'
                                : 'Starting boost for this performance mode')
                          : 'Off in Stock Balanced and Battery Saver',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: gedBoost
                      ? const Color(0xFFFF5252).withValues(alpha: 0.16)
                      : colors.onSurfaceVariant.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: gedBoost
                        ? const Color(0xFFFF5252).withValues(alpha: 0.55)
                        : colors.onSurfaceVariant.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  gedBoost ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: gedBoost
                        ? const Color(0xFFFF5252)
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          // Mali Hardware Power Policy (Always On vs Coarse Demand)
          Row(
            children: <Widget>[
              Text(
                'MALI POWER POLICY (CSF DRIVER)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                powerPolicyCode == 1 ? 'Zero Latency' : 'Dynamic Sleep',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: powerPolicyCode == 1
                      ? const Color(0xFFFF5252)
                      : const Color(0xFF41C98A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Controls GPU shader core power domain gating and idle sleep states',
            style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildPolicySegment(
                  isDark: isDark,
                  colors: colors,
                  label: 'Coarse Demand',
                  subtitle: 'Dynamic Sleep Gating',
                  icon: Icons.eco_rounded,
                  code: 0,
                  isSelected: powerPolicyCode == 0,
                  selectedAccent: const Color(0xFF67C2FF),
                  onSelect: onSelectPowerPolicy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPolicySegment(
                  isDark: isDark,
                  colors: colors,
                  label: 'Always On',
                  subtitle: '0 Latency · No Sleep',
                  icon: Icons.bolt_rounded,
                  code: 1,
                  isSelected: powerPolicyCode == 1,
                  selectedAccent: const Color(0xFFFF5252),
                  onSelect: onSelectPowerPolicy,
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          // Devfreq Governor Selector
          Text(
            'DEVFREQ GOVERNOR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double halfWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  SizedBox(
                    width: halfWidth,
                    child: _buildGovSegment(
                      isDark: isDark,
                      colors: colors,
                      label: 'On-Demand',
                      subtitle: 'Load-responsive scaling',
                      icon: Icons.speed_rounded,
                      selectedAccent: const Color(0xFFFFB84D),
                      code: 0,
                      isSelected: govCode == 0,
                      onSelect: onSelectGov,
                    ),
                  ),
                  SizedBox(
                    width: halfWidth,
                    child: _buildGovSegment(
                      isDark: isDark,
                      colors: colors,
                      label: 'Performance',
                      subtitle: 'Maximum-clock priority',
                      icon: Icons.bolt_rounded,
                      selectedAccent: const Color(0xFFFF5252),
                      code: 1,
                      isSelected: govCode == 1,
                      onSelect: onSelectGov,
                    ),
                  ),
                  SizedBox(
                    width: halfWidth,
                    child: _buildGovSegment(
                      isDark: isDark,
                      colors: colors,
                      label: 'Powersave',
                      subtitle: 'Lowest-clock priority',
                      icon: Icons.eco_rounded,
                      selectedAccent: const Color(0xFF41C98A),
                      code: 2,
                      isSelected: govCode == 2,
                      onSelect: onSelectGov,
                    ),
                  ),
                  SizedBox(
                    width: halfWidth,
                    child: _buildGovSegment(
                      isDark: isDark,
                      colors: colors,
                      label: 'Userspace',
                      subtitle: 'Manual frequency control',
                      icon: Icons.tune_rounded,
                      selectedAccent: const Color(0xFFA78BFA),
                      code: 3,
                      isSelected: govCode == 3,
                      onSelect: onSelectGov,
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _buildGovSegment(
                      isDark: isDark,
                      colors: colors,
                      label: 'OEM Stock',
                      subtitle: 'Vendor default governor behavior',
                      icon: Icons.memory_rounded,
                      selectedAccent: const Color(0xFF67C2FF),
                      code: 4,
                      isSelected: govCode == 4,
                      onSelect: onSelectGov,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySegment({
    required bool isDark,
    required ColorScheme colors,
    required String label,
    required String subtitle,
    required IconData icon,
    required int code,
    required bool isSelected,
    required Color selectedAccent,
    required ValueChanged<int> onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(code),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedAccent.withValues(alpha: 0.12)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? selectedAccent : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: isSelected ? selectedAccent : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected ? selectedAccent : colors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGovSegment({
    required bool isDark,
    required ColorScheme colors,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color selectedAccent,
    required int code,
    required bool isSelected,
    required ValueChanged<int> onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelect(code),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedAccent.withValues(alpha: 0.14)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? selectedAccent
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04)),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selectedAccent.withValues(
                    alpha: isSelected ? 0.18 : 0.08,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: isSelected ? selectedAccent : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: isSelected ? selectedAccent : colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.15,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 6. HARDWARE ARCHITECTURE & TELEMETRY
  Widget _buildHardwareDetailsCard({
    required bool isDark,
    required ColorScheme colors,
    required int thermalState,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.developer_board_rounded,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'MediaTek Mali Architecture',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow(
            colors,
            'GPU Architecture',
            'Mali-G720 7-Core r0p1 (0x0C080700)',
          ),
          _buildDetailRow(
            colors,
            'Active Core Mask',
            '0x150055 (All 7 execution clusters active)',
          ),
          _buildDetailRow(
            colors,
            'Thermal Cooling Node',
            '/sys/class/thermal/cooling_device3',
          ),
          _buildDetailRow(
            colors,
            'Thermal Controller State',
            thermalState < 0
                ? 'Unavailable'
                : (thermalState == 0
                      ? '0 (Rodin unrestricted override)'
                      : '$thermalState (vendor managed)'),
          ),
          _buildDetailRow(
            colors,
            'GED Boost Subsystem',
            '/sys/module/ged/parameters/',
          ),
          _buildDetailRow(
            colors,
            'Hardware Frequencies',
            '41 Clock Steps (260 MHz → 1.30 GHz)',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(ColorScheme colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaliGlassToast extends StatelessWidget {
  const _MaliGlassToast({
    required this.tag,
    required this.message,
    required this.icon,
    required this.accent,
    required this.visible,
  });

  final String tag;
  final String message;
  final IconData icon;
  final Color accent;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 380),
      curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
      bottom: visible ? 84 : -110,
      left: 16,
      right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: visible ? 1.0 : 0.0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xDD121924)
                    : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: accent.withValues(alpha: dark ? 0.35 : 0.45),
                  width: 1.2,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(alpha: dark ? 0.18 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.4 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: accent,
                          ),
                        ),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: dark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    RodinBackend.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFF74E6C6);

    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final int phase = backend.extendedValue(0);
        final int perfSupported = backend.extendedValue(11);
        final int perfVerified = backend.extendedValue(12);
        final int perfOk = backend.extendedValue(13);
        final int persistence = backend.extendedValue(26);
        final int displayAck = backend.extendedValue(28);
        final int touchAck = backend.extendedValue(29);

        final List<int> drifts = <int>[
          backend.extendedValue(14),
          backend.extendedValue(15),
          backend.extendedValue(16),
          backend.extendedValue(17),
          backend.extendedValue(18),
        ];

        final List<int> knownDrifts = drifts
            .where((int value) => value >= 0)
            .toList();

        final bool noKnownDrift =
            knownDrifts.isEmpty || knownDrifts.every((int value) => value == 0);

        return RodinScrollPage(
          children: <Widget>[
            DetailHeader(title: 'Diagnostics', onBack: widget.onBack),
            const SizedBox(height: 4),
            Text(
              'Real-time hardware status and system health checks',
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            HeroCard(
              icon: Icons.monitor_heart_rounded,
              accent: accent,
              title: snapshot.ready
                  ? 'System Health Normal'
                  : 'System Service Connecting',
              subtitle: phase == 16
                  ? 'All hardware controllers and telemetry streams active'
                  : 'Waiting for system background service',
            ),
            const SizedBox(height: 9),
            SurfaceCard(
              child: Column(
                children: <Widget>[
                  _DiagnosticRow(
                    label: 'Hardware Controller',
                    good: snapshot.ready && phase == 16,
                    detail: snapshot.ready ? 'Online & Ready' : 'Connecting...',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Touch Controller',
                    good: snapshot.touchHal == 1,
                    detail: snapshot.touchHal == 1 ? 'Active' : 'Unavailable',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Display Engine',
                    good: snapshot.displayHal == 1,
                    detail: snapshot.displayHal == 1 ? 'Active' : 'Unavailable',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Saved Preferences',
                    good: persistence == 1,
                    detail: persistence == 1 ? 'Loaded' : 'Not loaded',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'System Optimizations',
                    good:
                        perfOk == 1 &&
                        perfSupported > 0 &&
                        perfSupported == perfVerified,
                    detail: perfSupported >= 0
                        ? '$perfVerified / $perfSupported active'
                        : 'Checking...',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Hardware Sync Check',
                    good: noKnownDrift,
                    detail: noKnownDrift ? 'In sync' : 'Adjusting...',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Display Bridge',
                    good: displayAck == 1,
                    detail: displayAck == 1
                        ? 'Ready'
                        : displayAck == 0
                        ? 'Failed'
                        : 'Active',
                  ),
                  const Divider(height: 14),
                  _DiagnosticRow(
                    label: 'Touch Bridge',
                    good: touchAck == 1,
                    detail: touchAck == 1
                        ? 'Ready'
                        : touchAck == 0
                        ? 'Failed'
                        : 'Active',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ExpertSliderRow extends StatefulWidget {
  const _ExpertSliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.enabled,
    required this.onChanged,
    this.activeColor,
  });

  final String title;
  final int value;
  final int min;
  final int max;
  final int defaultValue;
  final bool enabled;
  final bool Function(int) onChanged;
  final Color? activeColor;

  @override
  State<_ExpertSliderRow> createState() => _ExpertSliderRowState();
}

class _ExpertSliderRowState extends State<_ExpertSliderRow> {
  late double _preview;
  bool _dragging = false;

  int _lastSent = 0;
  int _lastAccepted = 0;
  int? _lastHapticBucket;

  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);

  int _hapticBucket(int value) {
    final int span = widget.max - widget.min;

    // About 18 meaningful tactile steps across any channel range.
    // This keeps the slider tactile without buzzing on every pixel.
    final int stride = span <= 18 ? 1 : (span / 18).ceil();

    return (value - widget.min) ~/ stride;
  }

  int _safeValue() {
    if (widget.value >= widget.min && widget.value <= widget.max) {
      return widget.value;
    }

    return widget.defaultValue;
  }

  @override
  void initState() {
    super.initState();
    final int value = _safeValue();
    _preview = value.toDouble();
    _lastSent = value;
    _lastAccepted = value;
  }

  @override
  void didUpdateWidget(covariant _ExpertSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!_dragging &&
        (oldWidget.value != widget.value ||
            oldWidget.min != widget.min ||
            oldWidget.max != widget.max)) {
      final int value = _safeValue();
      _preview = value.toDouble();
      _lastSent = value;
      _lastAccepted = value;
    }
  }

  void _tryLiveApply(int value, {bool force = false}) {
    if (value == _lastSent) {
      return;
    }

    final DateTime now = DateTime.now();

    if (!force && now.difference(_lastSendAt).inMilliseconds < 80) {
      return;
    }

    _lastSendAt = now;
    _lastSent = value;

    final bool accepted = widget.onChanged(value);

    if (accepted) {
      _lastAccepted = value;
    }
  }

  void _start(double value) {
    final int rounded = value.round();

    setState(() {
      _dragging = true;
      _preview = value;
    });

    _lastSent = rounded;
    _lastAccepted = rounded;
    _lastHapticBucket = _hapticBucket(rounded);
    _lastSendAt = DateTime.now();

    RodinHaptics.segment();
  }

  void _drag(double value) {
    setState(() {
      // Local visual/value update happens on every Flutter slider event.
      // The thumb and numeric label therefore follow the finger directly.
      _preview = value;
    });

    final int rounded = value.round().clamp(widget.min, widget.max);

    final int bucket = _hapticBucket(rounded);

    if (_lastHapticBucket != bucket) {
      _lastHapticBucket = bucket;
      RodinHaptics.frequentSegment();
    }

    // Real DisplayFeature HAL updates continue while dragging,
    // but are rate-limited so Binder work cannot make the thumb sticky.
    _tryLiveApply(rounded);
  }

  void _finish(double value) {
    final int rounded = value.round().clamp(widget.min, widget.max);

    _tryLiveApply(rounded, force: true);

    setState(() {
      _dragging = false;
      _preview = rounded.toDouble();
    });

    _lastHapticBucket = null;

    if (_lastAccepted == rounded) {
      RodinHaptics.confirm();
    } else {
      RodinHaptics.reject();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color trackColor = widget.activeColor ?? colors.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: trackColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_preview.round()}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: trackColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          RepaintBoundary(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: trackColor,
                thumbColor: trackColor,
                inactiveTrackColor: trackColor.withValues(alpha: 0.18),
                overlayColor: trackColor.withValues(alpha: 0.14),
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6.5,
                ),
              ),
              child: Slider(
                value: _preview.clamp(
                  widget.min.toDouble(),
                  widget.max.toDouble(),
                ),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                onChangeStart: widget.enabled ? _start : null,
                onChanged: widget.enabled ? _drag : null,
                onChangeEnd: widget.enabled ? _finish : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderCard extends StatefulWidget {
  const _SliderCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final int defaultValue;
  final bool enabled;
  final bool Function(int) onChanged;

  @override
  State<_SliderCard> createState() => _SliderCardState();
}

class _SliderCardState extends State<_SliderCard> {
  late double _preview;
  bool _dragging = false;
  int? _lastHapticBucket;

  int _safeValue() {
    if (widget.value >= widget.min && widget.value <= widget.max) {
      return widget.value;
    }
    return widget.defaultValue;
  }

  int _hapticBucket(double value) {
    final int span = widget.max - widget.min;
    final int stride = span <= 24 ? 1 : (span / 24).ceil();
    return (value.round() - widget.min) ~/ stride;
  }

  @override
  void initState() {
    super.initState();
    _preview = _safeValue().toDouble();
  }

  @override
  void didUpdateWidget(covariant _SliderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        (oldWidget.value != widget.value ||
            oldWidget.min != widget.min ||
            oldWidget.max != widget.max)) {
      _preview = _safeValue().toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool known = widget.value >= widget.min && widget.value <= widget.max;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                known ? '${_preview.round()}' : '—',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: _preview.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            divisions: widget.max - widget.min,
            onChangeStart: widget.enabled
                ? (double value) {
                    _lastHapticBucket = _hapticBucket(value);
                    setState(() => _dragging = true);
                  }
                : null,
            onChanged: widget.enabled
                ? (double value) {
                    final int bucket = _hapticBucket(value);
                    if (_lastHapticBucket != bucket) {
                      _lastHapticBucket = bucket;
                      RodinHaptics.frequentSegment();
                    }
                    setState(() => _preview = value);
                  }
                : null,
            onChangeEnd: widget.enabled
                ? (double value) {
                    final int selected = value.round();
                    final bool accepted = widget.onChanged(selected);

                    if (accepted) {
                      RodinHaptics.segment();
                    } else {
                      RodinHaptics.reject();
                    }

                    setState(() {
                      _preview = selected.toDouble();
                      _dragging = false;
                      _lastHapticBucket = null;
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _PersistenceStatusRow extends StatelessWidget {
  const _PersistenceStatusRow({required this.label, required this.state});

  final String label;
  final int state;

  @override
  Widget build(BuildContext context) {
    return _DiagnosticRow(
      label: label,
      good: state == 0,
      detail: state == 0
          ? 'Verified'
          : state == 1
          ? 'Vendor drift detected · guard will reassert'
          : 'No persisted selection yet',
    );
  }
}

class _BackendSnapshotBuilder extends StatelessWidget {
  const _BackendSnapshotBuilder({required this.builder});
  final Widget Function(RodinBackendSnapshot snapshot) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RodinBackendSnapshot>(
      stream: RodinBackend.instance.snapshots,
      initialData: RodinBackend.instance.latest,
      builder:
          (BuildContext context, AsyncSnapshot<RodinBackendSnapshot> async) =>
              builder(async.data ?? RodinBackend.instance.latest),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.stateKnown,
    required this.onChanged,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final bool stateKnown;
  final bool Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  accent.withValues(alpha: value ? 0.24 : 0.13),
                  accent.withValues(alpha: 0.055),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: value ? 0.27 : 0.13),
              ),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!stateKnown) ...<Widget>[
                      const SizedBox(width: 6),
                      StatusPill(
                        label: 'SESSION',
                        accent: colors.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    height: 1.2,
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled
                ? (bool v) {
                    final bool accepted = onChanged(v);
                    if (accepted) {
                      RodinHaptics.toggle(v);
                    } else {
                      RodinHaptics.reject();
                    }
                  }
                : null,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.34),
          ),
        ],
      ),
    );
  }
}

class _ChoiceOption {
  const _ChoiceOption(this.code, this.label);
  final int code;
  final String label;
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.selectedCode,
    required this.options,
    required this.enabled,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final int selectedCode;
  final List<_ChoiceOption> options;
  final bool enabled;
  final bool Function(int) onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    _ChoiceOption? selected;

    for (final _ChoiceOption option in options) {
      if (option.code == selectedCode) {
        selected = option;
      }
    }

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconTile(icon: icon, accent: accent, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: selected?.label ?? 'UNSET',
                accent: selected == null ? colors.onSurfaceVariant : accent,
              ),
            ],
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final _ChoiceOption option in options)
                ChoiceChip(
                  label: Text(option.label),
                  selected: option.code == selectedCode,
                  onSelected: enabled
                      ? (bool selected) {
                          if (selected) {
                            final bool accepted = onSelected(option.code);
                            if (accepted) {
                              RodinHaptics.segment();
                            } else {
                              RodinHaptics.reject();
                            }
                          }
                        }
                      : null,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: accent.withValues(alpha: 0.15),
                  backgroundColor: colors.surfaceContainer.withValues(
                    alpha: 0.46,
                  ),
                  side: BorderSide(
                    color: option.code == selectedCode
                        ? accent.withValues(alpha: 0.38)
                        : colors.outline.withValues(alpha: 0.56),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CpuStatusRow extends StatelessWidget {
  const _CpuStatusRow({
    required this.cpu,
    required this.online,
    required this.frequency,
    required this.toggleEnabled,
    required this.onChanged,
    this.accent = const Color(0xFF67C2FF),
    this.clusterTag,
  });

  final int cpu;
  final bool online;
  final String frequency;
  final bool toggleEnabled;
  final ValueChanged<bool>? onChanged;
  final Color accent;
  final String? clusterTag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: online ? 0.14 : 0.06),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: accent.withValues(alpha: online ? 0.28 : 0.12),
              ),
            ),
            child: Text(
              '$cpu',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: online ? accent : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'CPU$cpu',
                      style: const TextStyle(
                        fontSize: 13.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (clusterTag != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          clusterTag!,
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cpu == 0 ? '$frequency · pinned master' : frequency,
                  style: TextStyle(
                    fontSize: 11.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: online ? 'ONLINE' : 'OFFLINE',
            accent: online ? const Color(0xFF41C98A) : const Color(0xFFFF7A7A),
          ),
          const SizedBox(width: 4),
          Switch.adaptive(
            value: online,
            onChanged: toggleEnabled
                ? RodinHaptics.toggleCallback(onChanged)
                : null,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.label,
    required this.good,
    required this.detail,
  });
  final String label;
  final bool good;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          good ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 18,
          color: good ? const Color(0xFF41C98A) : const Color(0xFFFFB84D),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            detail,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({
    required this.screen,
    required this.icon,
    required this.accent,
    required this.subtitle,
    required this.onBack,
    super.key,
  });

  final RodinScreen screen;
  final IconData icon;
  final Color accent;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return RodinScrollPage(
      children: <Widget>[
        DetailHeader(title: screen.title, onBack: onBack),
        const SizedBox(height: 9),
        HeroCard(
          icon: icon,
          accent: accent,
          title: screen.title,
          subtitle: subtitle,
        ),
        const SizedBox(height: 9),
        const SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Native backend migration',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'UI structure is active. Hardware controls remain intentionally disconnected until their Rust daemon/backend path is migrated.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RodinScrollPage extends StatefulWidget {
  const RodinScrollPage({
    this.children = const <Widget>[],
    this.slivers,
    this.header,
    this.topPadding = 10,
    super.key,
  });

  final List<Widget> children;
  final List<Widget>? slivers;
  final Widget? header;
  final double topPadding;

  @override
  State<RodinScrollPage> createState() => _RodinScrollPageState();
}

class _RodinScrollPageState extends State<RodinScrollPage> {
  final ValueNotifier<double> _scrollPixels = ValueNotifier<double>(0);

  static const double _rodinPhysicalWidth = 1220;
  static const double _rodinPhysicalHeight = 2712;
  static const double _rodinPhysicalCutoutTop = 130;

  @override
  void dispose() {
    _scrollPixels.dispose();
    super.dispose();
  }

  double _resolvedTopInset(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);

    final double frameworkInset = media.viewPadding.top > media.padding.top
        ? media.viewPadding.top
        : media.padding.top;

    if (frameworkInset > 0.5) {
      return frameworkInset;
    }

    final double dpr = media.devicePixelRatio;
    final double physicalWidth = media.size.width * dpr;
    final double physicalHeight = media.size.height * dpr;

    final bool rodinPortrait =
        (physicalWidth - _rodinPhysicalWidth).abs() < 8 &&
        (physicalHeight - _rodinPhysicalHeight).abs() < 8;

    final bool rodinLandscape =
        (physicalWidth - _rodinPhysicalHeight).abs() < 8 &&
        (physicalHeight - _rodinPhysicalWidth).abs() < 8;

    if ((rodinPortrait || rodinLandscape) && dpr > 0) {
      return _rodinPhysicalCutoutTop / dpr;
    }

    return 24;
  }

  Widget? _firstHeader() {
    if (widget.header != null) {
      return widget.header;
    }

    if (widget.children.isEmpty) {
      return null;
    }

    final Widget first = widget.children.first;

    if (first is RodinHeader || first is DetailHeader) {
      return first;
    }

    return null;
  }

  String? _titleOf(Widget? header) {
    if (header is RodinHeader) {
      return header.title;
    }

    if (header is DetailHeader) {
      return header.title;
    }

    return null;
  }

  double _titleStartFont(Widget? header) {
    if (header is RodinHeader) {
      return header.large ? 28 : 24;
    }

    if (header is DetailHeader) {
      return 23;
    }

    return 18;
  }

  double _titleStartX(Widget? header) {
    if (header is DetailHeader) {
      return 68;
    }

    return 16;
  }

  VoidCallback? _backOf(Widget? header) {
    if (header is DetailHeader) {
      return header.onBack;
    }

    return null;
  }

  Widget _headerPlaceholder(Widget? header) {
    if (header is RodinHeader) {
      final double titleHeight = header.large ? 38 : 32;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: titleHeight),
          const SizedBox(height: 6),
          Text(
            header.subtitle,
            style: TextStyle(
              fontSize: 13.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    if (header is DetailHeader) {
      return const SizedBox(height: 44);
    }

    return const SizedBox.shrink();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final double next = notification.metrics.pixels.clamp(0.0, 96.0).toDouble();

    if ((_scrollPixels.value - next).abs() > 0.10) {
      _scrollPixels.value = next;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final double safeTop = _resolvedTopInset(context);
    final Widget? header = _firstHeader();

    final Widget scrollChild;
    if (widget.slivers != null) {
      scrollChild = CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              safeTop + widget.topPadding,
              16,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: header == null
                  ? const SizedBox.shrink()
                  : _headerPlaceholder(header),
            ),
          ),
          ...widget.slivers!,
          const SliverPadding(padding: EdgeInsets.only(bottom: 102)),
        ],
      );
    } else {
      final List<Widget> effectiveChildren = header == null
          ? widget.children
          : <Widget>[_headerPlaceholder(header), ...widget.children.skip(1)];

      scrollChild = ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16, safeTop + widget.topPadding, 16, 102),
        children: effectiveChildren,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: scrollChild,
        ),
        if (header != null)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: safeTop + 58,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrollPixels,
              builder: (BuildContext context, double pixels, Widget? child) {
                return _RodinChromaticGlassMorph(
                  scrollPixels: pixels,
                  safeTop: safeTop,
                  title: _titleOf(header)!,
                  startFont: _titleStartFont(header),
                  startX: _titleStartX(header),
                  topPadding: widget.topPadding,
                  onBack: _backOf(header),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RodinChromaticGlassMorph extends StatelessWidget {
  const _RodinChromaticGlassMorph({
    required this.scrollPixels,
    required this.safeTop,
    required this.title,
    required this.startFont,
    required this.startX,
    required this.topPadding,
    required this.onBack,
  });

  final double scrollPixels;
  final double safeTop;
  final String title;
  final double startFont;
  final double startX;
  final double topPadding;
  final VoidCallback? onBack;

  double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    final double rawMorph = _clamp01(scrollPixels / 58.0);
    final double morph = Curves.easeInOutCubic.transform(rawMorph);

    final double rawGlass = _clamp01((scrollPixels - 7) / 39.0);
    final double glass = Curves.easeOutCubic.transform(rawGlass);

    final double titleFont = ui.lerpDouble(startFont, 17.5, morph) ?? 17.5;

    final double titleX =
        ui.lerpDouble(startX, onBack == null ? 14 : 52, morph) ?? startX;

    final double titleY =
        ui.lerpDouble(safeTop + topPadding, safeTop + 6, morph) ??
        (safeTop + topPadding);

    final double titleWidthRight = onBack == null ? 14 : 12;

    final double blurSigma = 7.75 * glass;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (glass > 0.001)
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: safeTop + 42,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          colors.surface.withValues(
                            alpha: (dark ? 0.17 : 0.10) * glass,
                          ),
                          colors.surface.withValues(
                            alpha: (dark ? 0.12 : 0.065) * glass,
                          ),
                          colors.surface.withValues(
                            alpha: (dark ? 0.07 : 0.035) * glass,
                          ),
                        ],
                        stops: const <double>[0, 0.58, 1],
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: colors.outline.withValues(alpha: 0.08 * glass),
                          width: 0.55,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (glass > 0.001)
          Positioned(
            left: 0,
            right: 0,
            top: safeTop + 34,
            height: 8,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      colors.primary.withValues(alpha: 0.028 * glass),
                      colors.secondary.withValues(alpha: 0.016 * glass),
                      colors.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (glass > 0.001)
          Positioned(
            left: 18 + (12 * (1 - morph)),
            right: 28 - (10 * morph),
            top: safeTop + 41,
            height: 0.8,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.15 * glass,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0),
                        colors.primary.withValues(alpha: 0.34),
                        Colors.white.withValues(alpha: dark ? 0.22 : 0.36),
                        colors.secondary.withValues(alpha: 0.24),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const <double>[0, 0.26, 0.48, 0.72, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (onBack != null)
          Positioned(
            left: ui.lerpDouble(12, 10, morph) ?? 10,
            top:
                ui.lerpDouble(safeTop + topPadding - 2, safeTop + 3, morph) ??
                (safeTop + 3),
            width: ui.lerpDouble(44, 36, morph) ?? 36,
            height: ui.lerpDouble(44, 36, morph) ?? 36,
            child: PressScale(
              onTap: onBack!,
              child: Center(
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: ui.lerpDouble(22, 20, morph) ?? 20,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),

        Positioned(
          left: titleX,
          right: titleWidthRight,
          top: titleY,
          height: ui.lerpDouble(36, 30, morph) ?? 30,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: titleFont,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: ui.lerpDouble(-0.85, -0.25, morph),
                  color: colors.onSurface,
                  shadows: glass > 0.15
                      ? <Shadow>[
                          Shadow(
                            color: colors.surface.withValues(
                              alpha: dark ? 0.22 : 0.28,
                            ),
                            blurRadius: 5 * glass,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RodinHeader extends StatelessWidget {
  const RodinHeader({
    required this.title,
    required this.subtitle,
    this.large = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: large ? 30 : 25,
            fontWeight: FontWeight.w900,
            letterSpacing: large ? -0.85 : -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class DetailHeader extends StatelessWidget {
  const DetailHeader({
    required this.title,
    required this.onBack,
    this.trailing,
    super.key,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        PressScale(
          onTap: onBack,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class LiveDashboardHero extends StatelessWidget {
  const LiveDashboardHero({super.key});

  String _displayMode(RodinBackendSnapshot snapshot) {
    return switch (snapshot.displayColor) {
      0 => 'Original PRO',
      1 => 'Vivid',
      2 => 'Saturated',
      _ => '—',
    };
  }

  @override
  Widget build(BuildContext context) {
    return _BackendSnapshotBuilder(
      builder: (RodinBackendSnapshot snapshot) {
        final RodinBackend backend = RodinBackend.instance;
        final ColorScheme colors = Theme.of(context).colorScheme;
        final bool ready = snapshot.ready;
        final int onlineCores = _rodinOnlineCoreCount(snapshot);
        final int perAppEnabled = backend.extendedValue(19);
        final int perAppProfile = backend.extendedValue(20);
        final int activePerf = snapshot.performanceProfile >= 0
            ? snapshot.performanceProfile
            : (perAppEnabled == 1 && perAppProfile >= 0 ? perAppProfile : 0);
        final String profile = _rodinPerformanceLabel(activePerf);
        final String source = perAppEnabled == 1
            ? 'Adaptive Engine active'
            : 'Global System Profile';
        final String battery = snapshot.batteryCapacity >= 0
            ? '${snapshot.batteryCapacity}%'
            : '—';
        final String temp = snapshot.batteryTempC == null
            ? '—'
            : '${snapshot.batteryTempC!.toStringAsFixed(1)}°C';
        final String touch = switch (snapshot.touchState) {
          1 => '250 Hz',
          2 => '500 Hz',
          3 => '1000 Hz',
          0 => '250 Hz',
          _ => '—',
        };
        final RodinAppearanceConfig appearance = RodinAppearanceScope.of(
          context,
        );

        final Color profileAccent = switch (activePerf) {
          2 => const Color(0xFF35C997), // Battery Saver
          1 => const Color(0xFFFFB84D), // Gaming Dynamic
          3 => const Color(0xFFFF5252), // Extreme Beast
          _ => const Color(0xFF4EA8DE), // Stock Balanced
        };

        return Stack(
          children: <Widget>[
            if (appearance.heroGlow)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      appearance.cardRadius + 4,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: profileAccent.withValues(alpha: 0.14),
                        blurRadius: 28,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'DEVICE PULSE',
                        style: TextStyle(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.25,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (ready
                                      ? const Color(0xFF41C98A)
                                      : colors.onSurfaceVariant)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color:
                                (ready
                                        ? const Color(0xFF41C98A)
                                        : colors.onSurfaceVariant)
                                    .withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: ready
                                    ? const Color(0xFF41C98A)
                                    : colors.onSurfaceVariant,
                                shape: BoxShape.circle,
                                boxShadow: ready
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color: const Color(
                                            0xFF41C98A,
                                          ).withValues(alpha: 0.7),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              ready ? 'LIVE' : 'OFFLINE',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: ready
                                    ? const Color(0xFF41C98A)
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 0.98,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(
                        perAppEnabled == 1
                            ? Icons.apps_rounded
                            : Icons.tune_rounded,
                        size: 15,
                        color: profileAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.4,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Dynamic CPU Core Visualizer Bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          'CORES',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (appearance.coreVisualizerStyle == 1) ...<Widget>[
                          for (int cpu = 0; cpu < 8; cpu++)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: snapshot.cpuOnline(cpu)
                                    ? (cpu == 7
                                          ? const Color(0xFFFF8E3C)
                                          : (cpu >= 4
                                                ? const Color(0xFFA066FF)
                                                : const Color(0xFF4EA8DE)))
                                    : const Color(0xFF222222),
                                boxShadow: snapshot.cpuOnline(cpu)
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color:
                                              (cpu == 7
                                                      ? const Color(0xFFFF8E3C)
                                                      : (cpu >= 4
                                                            ? const Color(
                                                                0xFFA066FF,
                                                              )
                                                            : const Color(
                                                                0xFF4EA8DE,
                                                              )))
                                                  .withValues(alpha: 0.65),
                                          blurRadius: 5,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                        ] else if (appearance.coreVisualizerStyle ==
                            2) ...<Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                for (int cpu = 0; cpu < 8; cpu++)
                                  Container(
                                    width: 13,
                                    height: 10,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 0.5,
                                    ),
                                    color: snapshot.cpuOnline(cpu)
                                        ? (cpu == 7
                                              ? const Color(0xFFFF8E3C)
                                              : (cpu >= 4
                                                    ? const Color(0xFFA066FF)
                                                    : const Color(0xFF4EA8DE)))
                                        : const Color(0xFF222222),
                                  ),
                              ],
                            ),
                          ),
                        ] else ...<Widget>[
                          for (int cpu = 0; cpu < 8; cpu++)
                            Container(
                              width: 8,
                              height: 14,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: snapshot.cpuOnline(cpu)
                                    ? (cpu == 7
                                          ? const Color(0xFFFF8E3C)
                                          : (cpu >= 4
                                                ? const Color(0xFFA066FF)
                                                : const Color(0xFF4EA8DE)))
                                    : const Color(0xFF222222),
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: snapshot.cpuOnline(cpu)
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color:
                                              (cpu == 7
                                                      ? const Color(0xFFFF8E3C)
                                                      : (cpu >= 4
                                                            ? const Color(
                                                                0xFFA066FF,
                                                              )
                                                            : const Color(
                                                                0xFF4EA8DE,
                                                              )))
                                                  .withValues(alpha: 0.45),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      _PulseChip(
                        icon: Icons.memory_rounded,
                        label: ready ? '$onlineCores / 8 online' : 'CPU —',
                        accent: const Color(0xFF67C2FF),
                      ),
                      _PulseChip(
                        icon: Icons.palette_rounded,
                        label: _displayMode(snapshot),
                        accent: const Color(0xFFB087FF),
                      ),
                      _PulseChip(
                        icon: Icons.touch_app_rounded,
                        label: 'Touch $touch',
                        accent: const Color(0xFF41C98A),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    color: colors.outline.withValues(alpha: 0.15),
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.battery_std_rounded,
                        size: 15,
                        color: Color(0xFF41C98A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        battery,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.thermostat_rounded,
                        size: 15,
                        color: Color(0xFF59BCFF),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        temp,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        ready ? 'System online' : 'Offline',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: profileAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PulseChip extends StatelessWidget {
  const _PulseChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.outline.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class HeroCard extends StatelessWidget {
  const HeroCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: dark ? 0.20 : 0.12),
            colors.surface,
            colors.secondary.withValues(alpha: dark ? 0.05 : 0.03),
          ],
          stops: const <double>[0, 0.60, 1],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.23)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 24,
            spreadRadius: -7,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          IconTile(icon: icon, accent: accent, size: 54),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    height: 1.25,
                    fontSize: 12.3,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GithubIcon extends StatelessWidget {
  const GithubIcon({required this.color, this.size = 23, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GithubPainter(color: color)),
    );
  }
}

class _GithubPainter extends CustomPainter {
  const _GithubPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double scale = size.width / 16.0;
    canvas.save();
    canvas.scale(scale, scale);

    final Path path = Path();
    path.moveTo(8, 0);
    path.cubicTo(3.58, 0, 0, 3.58, 0, 8);
    path.cubicTo(0, 11.54, 2.29, 14.53, 5.47, 15.59);
    path.cubicTo(5.87, 15.66, 6.02, 15.42, 6.02, 15.21);
    path.cubicTo(6.02, 15.02, 6.01, 14.39, 6.01, 13.72);
    path.cubicTo(4, 14.09, 3.48, 13.23, 3.32, 12.78);
    path.cubicTo(3.23, 12.55, 2.84, 11.84, 2.5, 11.65);
    path.cubicTo(2.22, 11.5, 1.82, 11.13, 2.49, 11.12);
    path.cubicTo(3.12, 11.11, 3.57, 11.7, 3.72, 11.94);
    path.cubicTo(4.44, 13.15, 5.59, 12.81, 6.05, 12.6);
    path.cubicTo(6.12, 12.08, 6.33, 11.73, 6.56, 11.53);
    path.cubicTo(4.78, 11.33, 2.92, 10.64, 2.92, 7.58);
    path.cubicTo(2.92, 6.71, 3.23, 5.99, 3.74, 5.43);
    path.cubicTo(3.66, 5.23, 3.38, 4.41, 3.82, 3.31);
    path.cubicTo(3.82, 3.31, 4.49, 3.1, 6.02, 4.13);
    path.cubicTo(6.66, 3.95, 7.34, 3.86, 8.02, 3.86);
    path.cubicTo(8.7, 3.86, 9.38, 3.95, 10.02, 4.13);
    path.cubicTo(11.55, 3.1, 12.22, 3.31, 12.22, 3.31);
    path.cubicTo(12.66, 4.41, 12.38, 5.23, 12.3, 5.43);
    path.cubicTo(12.81, 5.99, 13.12, 6.71, 13.12, 7.58);
    path.cubicTo(13.12, 10.65, 11.25, 11.33, 9.47, 11.53);
    path.cubicTo(9.76, 11.78, 10.01, 12.26, 10.01, 13.01);
    path.cubicTo(10.01, 14.08, 10, 14.94, 10, 15.21);
    path.cubicTo(10, 15.42, 10.15, 15.67, 10.55, 15.59);
    path.cubicTo(13.71, 14.53, 16, 11.54, 16, 8);
    path.cubicTo(16, 3.58, 12.42, 0, 8, 0);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GithubPainter oldDelegate) =>
      oldDelegate.color != color;
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.icon,
    this.customIcon,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? customIcon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: onTap,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 13, 12),
        child: Row(
          children: <Widget>[
            IconTile(icon: icon, child: customIcon, accent: accent, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HubRow extends StatelessWidget {
  const HubRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(17)),
        child: Row(
          children: <Widget>[
            IconTile(icon: icon, accent: accent, size: 42),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: colors.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ],
        ),
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accent,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final RodinAppearanceConfig config = RodinAppearanceScope.of(context);
    final Color activeAccent = accent ?? config.activeAccent;
    final double radius = config.cardRadius;

    final BoxDecoration decoration = switch (config.cardStyle) {
      1 => BoxDecoration(
        // Frosted Glass
        color: dark
            ? activeAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? activeAccent.withValues(alpha: 0.22)
              : const Color(0xFFD6E1ED),
          width: 0.95,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: dark
                ? activeAccent.withValues(alpha: 0.06)
                : const Color(0x140C2943),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      2 => BoxDecoration(
        // Neon Ambient Edge
        color: dark ? const Color(0xFF000000) : null,
        gradient: dark
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF7FAFE)],
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
              ? activeAccent.withValues(alpha: 0.45)
              : activeAccent.withValues(alpha: 0.35),
          width: 1.1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: activeAccent.withValues(alpha: dark ? 0.10 : 0.06),
            blurRadius: 14,
            spreadRadius: 0.5,
          ),
        ],
      ),
      3 => BoxDecoration(
        // Minimal Slate
        color: dark ? const Color(0xFF101419) : const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0xFF202730) : const Color(0xFFD2DCE7),
        ),
        boxShadow: dark
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x140C2943),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
      ),
      _ => BoxDecoration(
        // AMOLED Deep (Default)
        color: dark ? const Color(0xFF000000) : null,
        gradient: dark
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFFFFFF), Color(0xFFF7FAFE)],
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0xFF222222) : const Color(0xFFD6E1ED),
        ),
        boxShadow: dark
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x140C2943),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
      ),
    };

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    required this.accent,
    this.icon,
    this.child,
    this.size = 46,
    super.key,
  });

  final IconData? icon;
  final Widget? child;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.23),
            accent.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 14,
            spreadRadius: -5,
          ),
        ],
      ),
      alignment: Alignment.center,
      child:
          child ??
          (icon != null
              ? Icon(icon, color: accent, size: size * 0.49)
              : const SizedBox.shrink()),
    );
  }
}

class SummaryChip extends StatelessWidget {
  const SummaryChip({
    required this.title,
    required this.subtitle,
    required this.accent,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    Widget chip = Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accent.withValues(alpha: 0.13),
            accent.withValues(alpha: 0.045),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.19)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    if (onTap != null) {
      chip = PressScale(onTap: onTap, child: chip);
    }

    return chip;
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.accent, super.key});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.82,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class RodinHaptics {
  const RodinHaptics._();

  static final RodinBackend _backend = RodinBackend.instance;

  static void _send(int kind) {
    if (!RodinInteractionSettings.hapticsEnabled) return;
    _backend.haptic(kind);
  }

  static void tap() => _send(1);
  static void context() => _send(2);
  static void toggle(bool enabled) => _send(enabled ? 3 : 4);
  static void segment() => _send(5);
  static void frequentSegment() => _send(6);
  static void confirm() => _send(7);
  static void reject() => _send(8);
  static void back() => _send(9);

  static ValueChanged<bool>? toggleCallback(ValueChanged<bool>? callback) {
    if (callback == null) return null;
    return (bool enabled) {
      toggle(enabled);
      callback(enabled);
    };
  }
}

class RodinInteractionSettings {
  const RodinInteractionSettings._();

  static const int _motionModelVersion = 6;

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static double motionSpeed = 1.00;
  static bool hapticsEnabled = true;
  static bool _loaded = false;

  static File get _file {
    final Directory parent = Directory.systemTemp.parent;

    return File('${parent.path}/files/rodin-interaction.json');
  }

  static double get motionProgress {
    return ((motionSpeed.clamp(0.75, 1.35) - 0.75) / 0.60).toDouble();
  }

  static String get motionLabel {
    if (motionSpeed < 0.90) return 'Relaxed and cinematic';
    if (motionSpeed > 1.15) return 'Direct and responsive';
    return 'Balanced and fluid';
  }

  static double _mix(double relaxed, double direct) {
    return relaxed + (direct - relaxed) * motionProgress;
  }

  static Curve get pressCurve =>
      Cubic(_mix(0.16, 0.28), _mix(1.00, 0.00), _mix(0.30, 0.18), 1.00);

  static Curve get transitionCurve =>
      Cubic(_mix(0.16, 0.26), _mix(1.00, 0.00), _mix(0.30, 0.16), 1.00);

  static double get pressScale => _mix(0.985, 0.965);

  static double get pressOpacity => _mix(0.975, 0.935);

  static double get detailSlideDistance => _mix(0.035, 0.065);

  static double get pageScale => _mix(0.997, 0.992);

  static Duration motionDuration(int baseMilliseconds) {
    final double speed = motionSpeed.clamp(0.75, 1.35).toDouble();
    final int milliseconds = (baseMilliseconds / speed).round().clamp(70, 900);

    return Duration(milliseconds: milliseconds);
  }

  static Future<void> load() async {
    if (_loaded) {
      return;
    }

    _loaded = true;

    try {
      final File file = _file;

      if (!await file.exists()) {
        revision.value += 1;
        return;
      }

      final Object? decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        revision.value += 1;
        return;
      }

      final int version = (decoded['motionModelVersion'] as num?)?.toInt() ?? 0;

      if (version >= _motionModelVersion) {
        final num? raw = decoded['motionSpeed'] as num?;
        motionSpeed = (raw?.toDouble() ?? 1.00).clamp(0.75, 1.35).toDouble();
      } else {
        motionSpeed = 1.00;
      }

      final Object? hapticRaw = decoded['hapticsEnabled'];

      if (hapticRaw is bool) {
        hapticsEnabled = hapticRaw;
      }

      revision.value += 1;

      if (version != _motionModelVersion) {
        await _persist();
      }
    } catch (_) {
      revision.value += 1;
    }
  }

  static void previewMotionSpeed(double value) {
    motionSpeed = value.clamp(0.75, 1.35).toDouble();
  }

  static Future<void> commitMotionSpeed(double value) async {
    previewMotionSpeed(value);
    revision.value += 1;
    await _persist();
  }

  static Future<void> resetMotion() async {
    motionSpeed = 1.00;
    revision.value += 1;
    await _persist();
  }

  static Future<void> setHaptics(bool enabled) async {
    hapticsEnabled = enabled;
    revision.value += 1;
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final File file = _file;

      await file.parent.create(recursive: true);

      await file.writeAsString(
        jsonEncode(<String, Object>{
          'motionModelVersion': _motionModelVersion,
          'motionSpeed': motionSpeed,
          'hapticsEnabled': hapticsEnabled,
        }),
        flush: false,
      );
    } catch (_) {}
  }
}

class PressScale extends StatefulWidget {
  const PressScale({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }

    final Duration pressDuration = RodinInteractionSettings.motionDuration(80);
    final Duration releaseDuration = RodinInteractionSettings.motionDuration(
      150,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        RodinHaptics.tap();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? RodinInteractionSettings.pressScale : 1.0,
        duration: _pressed ? pressDuration : releaseDuration,
        curve: RodinInteractionSettings.pressCurve,
        child: AnimatedOpacity(
          opacity: _pressed ? RodinInteractionSettings.pressOpacity : 1.0,
          duration: _pressed ? pressDuration : releaseDuration,
          curve: RodinInteractionSettings.pressCurve,
          child: widget.child,
        ),
      ),
    );
  }
}

class RodinBottomBar extends StatelessWidget {
  const RodinBottomBar({
    required this.controller,
    required this.currentRoot,
    required this.onSelect,
    super.key,
  });

  final PageController controller;
  final RodinScreen currentRoot;
  final ValueChanged<RodinScreen> onSelect;

  static const List<RodinScreen> _screens = <RodinScreen>[
    RodinScreen.home,
    RodinScreen.hubs,
    RodinScreen.support,
    RodinScreen.settings,
  ];

  static const List<String> _labels = <String>[
    'Home',
    'Hubs',
    'Support',
    'Settings',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.home_rounded,
    Icons.grid_view_rounded,
    Icons.favorite_rounded,
    Icons.settings_rounded,
  ];

  static const List<Color> _sectionColors = <Color>[
    Color(0xFF2563EB), // Home: Electric Azure
    Color(0xFF10B981), // Hubs: Vivid Emerald
    Color(0xFFF43F5E), // Support: Neon Rose
    Color(0xFF8B5CF6), // Settings: Cyber Violet
  ];

  int _selectedIndex() {
    final int index = _screens.indexOf(currentRoot);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(9, 0, 9, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 6,
            sigmaY: 6,
            tileMode: TileMode.clamp,
          ),
          child: Container(
            height: 60,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: dark ? 0.72 : 0.74),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: colors.outline.withValues(alpha: dark ? 0.46 : 0.50),
                width: 0.75,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.20 : 0.065),
                  blurRadius: 14,
                  spreadRadius: -7,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: controller,
              builder: (BuildContext context, Widget? child) {
                int selectedIndex = _selectedIndex();

                if (controller.hasClients) {
                  try {
                    final double page =
                        controller.page ?? selectedIndex.toDouble();

                    selectedIndex = page.round().clamp(0, _screens.length - 1);
                  } catch (_) {}
                }

                Widget navItem(int index) {
                  final bool selected = index == selectedIndex;
                  final Color itemColor = _sectionColors[index];

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: PressScale(
                        onTap: () => onSelect(_screens[index]),
                        child: AnimatedContainer(
                          duration: RodinInteractionSettings.motionDuration(
                            180,
                          ),
                          curve: RodinInteractionSettings.transitionCurve,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? itemColor.withValues(
                                    alpha: dark ? 0.16 : 0.105,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: selected
                                  ? itemColor.withValues(
                                      alpha: dark ? 0.28 : 0.20,
                                    )
                                  : Colors.transparent,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AnimatedScale(
                                scale: selected ? 1.08 : 0.94,
                                duration:
                                    RodinInteractionSettings.motionDuration(
                                      200,
                                    ),
                                curve: RodinInteractionSettings.transitionCurve,
                                child: Icon(
                                  _icons[index],
                                  size: 20.5,
                                  color: selected
                                      ? itemColor
                                      : colors.onSurfaceVariant.withValues(
                                          alpha: 0.72,
                                        ),
                                ),
                              ),
                              AnimatedSize(
                                duration:
                                    RodinInteractionSettings.motionDuration(
                                      200,
                                    ),
                                reverseDuration:
                                    RodinInteractionSettings.motionDuration(
                                      160,
                                    ),
                                curve: RodinInteractionSettings.transitionCurve,
                                alignment: Alignment.centerLeft,
                                child: selected
                                    ? Padding(
                                        padding: const EdgeInsets.only(left: 7),
                                        child: AnimatedOpacity(
                                          opacity: 1,
                                          duration:
                                              RodinInteractionSettings.motionDuration(
                                                120,
                                              ),
                                          curve: Curves.easeOutCubic,
                                          child: Text(
                                            _labels[index],
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: TextOverflow.fade,
                                            style: TextStyle(
                                              fontSize: 11.2,
                                              fontWeight: FontWeight.w700,
                                              color: itemColor,
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return Row(
                  children: <Widget>[
                    navItem(0),
                    navItem(1),
                    navItem(2),
                    navItem(3),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class BottomBarItem extends StatelessWidget {
  const BottomBarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color foreground = selected
        ? colors.primary
        : colors.onSurfaceVariant;

    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.11)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: foreground, size: 21),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubSpec {
  const _HubSpec(
    this.screen,
    this.title,
    this.subtitle,
    this.icon,
    this.accent,
  );

  final RodinScreen screen;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
}
