import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const RodinEssentialApp());
}

enum RodinScreen {
  home,
  hubs,
  support,
  charging,
  touchBoost,
  displayStudio,
  performance,
  cpuCoreControl,
  advancedConfiguration,
  resolution,
  diagnostics,
}

extension RodinScreenName on RodinScreen {
  String get title {
    switch (this) {
      case RodinScreen.home:
        return 'Rodin Essentials';
      case RodinScreen.hubs:
        return 'Control Hubs';
      case RodinScreen.support:
        return 'Community & Support';
      case RodinScreen.charging:
        return 'Charging';
      case RodinScreen.touchBoost:
        return 'Touch Boost';
      case RodinScreen.displayStudio:
        return 'Display Studio';
      case RodinScreen.performance:
        return 'Performance';
      case RodinScreen.cpuCoreControl:
        return 'CPU Core Control';
      case RodinScreen.advancedConfiguration:
        return 'Advanced Configuration';
      case RodinScreen.resolution:
        return 'Resolution';
      case RodinScreen.diagnostics:
        return 'Diagnostics';
    }
  }

  bool get isRoot =>
      this == RodinScreen.home ||
      this == RodinScreen.hubs ||
      this == RodinScreen.support;
}

class RodinEssentialApp extends StatelessWidget {
  const RodinEssentialApp({super.key});

  static const Color _darkBackground = Color(0xFF000000);
  static const Color _darkSurface = Color(0xFF050505);
  static const Color _darkSurfaceVariant = Color(0xFF0D0D0D);
  static const Color _darkPrimary = Color(0xFF4DBBFF);
  static const Color _darkSecondary = Color(0xFF46E6B4);
  static const Color _darkTertiary = Color(0xFFFFB84D);
  static const Color _darkOnSurface = Color(0xFFF5F7FA);
  static const Color _darkOnSurfaceVariant = Color(0xFFA8B0BA);
  static const Color _darkOutline = Color(0xFF202020);

  static const Color _lightBackground = Color(0xFFF4F8FD);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceVariant = Color(0xFFEAF2FB);
  static const Color _lightPrimary = Color(0xFF0A7DCE);
  static const Color _lightSecondary = Color(0xFF0A9F86);
  static const Color _lightTertiary = Color(0xFFC17A10);
  static const Color _lightOnSurface = Color(0xFF0D1726);
  static const Color _lightOnSurfaceVariant = Color(0xFF54657C);
  static const Color _lightOutline = Color(0xFFD3E0EE);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rodin Essentials',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
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
      textTheme: Typography.material2021().black.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
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
  RodinScreen _screen = RodinScreen.home;
  RodinScreen _detailBackTarget = RodinScreen.home;
  bool _transitionForward = true;

  void _selectRoot(RodinScreen screen) {
    setState(() {
      _transitionForward = true;
      _screen = screen;
    });
  }

  void _openDetail(RodinScreen screen) {
    setState(() {
      _transitionForward = true;
      if (_screen.isRoot) {
        _detailBackTarget = _screen;
      }
      _screen = screen;
    });
  }

  void _back() {
    setState(() {
      _transitionForward = false;
      if (_screen == RodinScreen.hubs || _screen == RodinScreen.support) {
        _screen = RodinScreen.home;
      } else if (!_screen.isRoot) {
        _screen = _detailBackTarget;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final RodinScreen current = _screen;

    return PopScope(
      canPop: current == RodinScreen.home,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && current != RodinScreen.home) {
          _back();
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder:
                (Widget? currentChild, List<Widget> previousChildren) {
                  // Keep exactly one full-screen page in the render tree.
                  // This prevents the blue wash caused by compositing/fading
                  // full-screen pages against each other.
                  return ClipRect(
                    child: currentChild ?? const SizedBox.shrink(),
                  );
                },
            transitionBuilder: (Widget child, Animation<double> animation) {
              final Animation<Offset> slide =
                  Tween<Offset>(
                    begin: Offset(_transitionForward ? 0.055 : -0.055, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );

              return ClipRect(
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<RodinScreen>(current),
              child: _screenBody(current),
            ),
          ),
        ),
        bottomNavigationBar: RodinBottomBar(
          current: current,
          onHome: () => _selectRoot(RodinScreen.home),
          onHubs: () => _selectRoot(RodinScreen.hubs),
          onSupport: () => _selectRoot(RodinScreen.support),
        ),
      ),
    );
  }

  Widget _screenBody(RodinScreen screen) {
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
      case RodinScreen.charging:
        return DetailScreen(
          screen: screen,
          icon: Icons.battery_charging_full_rounded,
          accent: const Color(0xFF41C98A),
          subtitle: 'Charging controls and live battery telemetry',
          onBack: _back,
        );
      case RodinScreen.touchBoost:
        return DetailScreen(
          screen: screen,
          icon: Icons.bolt_rounded,
          accent: const Color(0xFF41C98A),
          subtitle: 'Low-latency touch response controls',
          onBack: _back,
        );
      case RodinScreen.displayStudio:
        return DetailScreen(
          screen: screen,
          icon: Icons.palette_rounded,
          accent: Theme.of(context).colorScheme.primary,
          subtitle: 'Colour, brightness, HDR and display tuning',
          onBack: _back,
        );
      case RodinScreen.performance:
        return DetailScreen(
          screen: screen,
          icon: Icons.speed_rounded,
          accent: const Color(0xFFB087FF),
          subtitle: 'Performance profiles and live device status',
          onBack: _back,
        );
      case RodinScreen.cpuCoreControl:
        return DetailScreen(
          screen: screen,
          icon: Icons.memory_rounded,
          accent: const Color(0xFF67C2FF),
          subtitle: 'CPU core state controls',
          onBack: _back,
        );
      case RodinScreen.advancedConfiguration:
        return DetailScreen(
          screen: screen,
          icon: Icons.tune_rounded,
          accent: const Color(0xFFFFB84D),
          subtitle: 'Governor and scheduler configuration',
          onBack: _back,
        );
      case RodinScreen.resolution:
        return DetailScreen(
          screen: screen,
          icon: Icons.grid_view_rounded,
          accent: const Color(0xFFFFBE63),
          subtitle: 'Resolution controls',
          onBack: _back,
        );
      case RodinScreen.diagnostics:
        return DetailScreen(
          screen: screen,
          icon: Icons.monitor_heart_rounded,
          accent: const Color(0xFF74E6C6),
          subtitle: 'Device checks and calibration status',
          onBack: _back,
        );
    }
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
          title: 'Rodin Essentials',
          subtitle: 'Compact device controls for custom ROMs',
          large: true,
        ),
        const SizedBox(height: 9),
        const LiveDashboardHero(),
        const SizedBox(height: 13),
        const SectionLabel('Quick controls'),
        const SizedBox(height: 9),
        FeatureCard(
          title: 'Charging',
          subtitle: 'Charging modes and telemetry',
          icon: Icons.battery_charging_full_rounded,
          accent: const Color(0xFF41C98A),
          onTap: () => onOpen(RodinScreen.charging),
        ),
        const SizedBox(height: 9),
        FeatureCard(
          title: 'Touch Boost',
          subtitle: 'Low-latency response',
          icon: Icons.bolt_rounded,
          accent: const Color(0xFF41C98A),
          onTap: () => onOpen(RodinScreen.touchBoost),
        ),
        const SizedBox(height: 9),
        FeatureCard(
          title: 'Display Studio',
          subtitle: 'Colour and display tuning',
          icon: Icons.palette_rounded,
          accent: Theme.of(context).colorScheme.primary,
          onTap: () => onOpen(RodinScreen.displayStudio),
        ),
        const SizedBox(height: 13),
        const SectionLabel('Control hubs'),
        const SizedBox(height: 9),
        SurfaceCard(
          child: Column(
            children: <Widget>[
              HubRow(
                title: 'All modules',
                subtitle:
                    'Charging, display, performance, CPU, resolution and diagnostics',
                icon: Icons.grid_view_rounded,
                accent: Theme.of(context).colorScheme.secondary,
                onTap: onHubs,
              ),
              const SizedBox(height: 8),
              HubRow(
                title: 'Community & Support',
                subtitle: 'Join the community, get help, and report bugs',
                icon: Icons.help_outline_rounded,
                accent: const Color(0xFFFFB74D),
                onTap: onSupport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HubsScreen extends StatelessWidget {
  const HubsScreen({required this.onOpen, super.key});

  final ValueChanged<RodinScreen> onOpen;

  static const List<_HubSpec> hubs = <_HubSpec>[
    _HubSpec(
      RodinScreen.charging,
      'Charging',
      'Charging controls and telemetry',
      Icons.battery_charging_full_rounded,
      Color(0xFF41C98A),
    ),
    _HubSpec(
      RodinScreen.touchBoost,
      'Touch Boost',
      'Low-latency response',
      Icons.bolt_rounded,
      Color(0xFF41C98A),
    ),
    _HubSpec(
      RodinScreen.displayStudio,
      'Display Studio',
      'Colour and display tuning',
      Icons.palette_rounded,
      Color(0xFF67C2FF),
    ),
    _HubSpec(
      RodinScreen.performance,
      'Performance',
      'Thermal and FPS tools',
      Icons.speed_rounded,
      Color(0xFFB087FF),
    ),
    _HubSpec(
      RodinScreen.cpuCoreControl,
      'CPU Core Control',
      'CPU online-state controls',
      Icons.memory_rounded,
      Color(0xFF67C2FF),
    ),
    _HubSpec(
      RodinScreen.advancedConfiguration,
      'Advanced Configuration',
      'Governors and scheduler',
      Icons.tune_rounded,
      Color(0xFFFFB84D),
    ),
    _HubSpec(
      RodinScreen.resolution,
      'Resolution',
      'Resolution controls',
      Icons.grid_view_rounded,
      Color(0xFFFFBE63),
    ),
    _HubSpec(
      RodinScreen.diagnostics,
      'Diagnostics',
      'Checks and calibration',
      Icons.monitor_heart_rounded,
      Color(0xFF74E6C6),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return RodinScrollPage(
      children: <Widget>[
        const RodinHeader(
          title: 'Control Hubs',
          subtitle: 'Feature areas and modules',
        ),
        const SizedBox(height: 9),
        Row(
          children: const <Widget>[
            Expanded(
              child: SummaryChip(
                title: 'Renderer',
                subtitle: 'Impeller',
                accent: Color(0xFF67C2FF),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SummaryChip(
                title: 'VSync',
                subtitle: '120 Hz',
                accent: Color(0xFF41C98A),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SummaryChip(
                title: 'Runtime',
                subtitle: 'AOT',
                accent: Color(0xFFB087FF),
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
  }
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return RodinScrollPage(
      topPadding: 20,
      children: <Widget>[
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                colors: <Color>[
                  const Color(0xFFFF8A65).withValues(alpha: 0.18),
                  const Color(0xFF67C2FF).withValues(alpha: 0.18),
                  const Color(0xFFB087FF).withValues(alpha: 0.18),
                ],
              ),
            ),
            child: const Icon(Icons.android_rounded, size: 72),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Rodin Essentials',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Community, support and project information',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        const SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Support',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'External actions stay disconnected until the native platform bridge is added.',
              ),
            ],
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

class RodinScrollPage extends StatelessWidget {
  const RodinScrollPage({
    required this.children,
    this.topPadding = 10,
    super.key,
  });

  final List<Widget> children;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 96),
      addRepaintBoundaries: false,
      children: children,
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
            fontSize: large ? 28 : 24,
            fontWeight: FontWeight.w800,
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
  const DetailHeader({required this.title, required this.onBack, super.key});

  final String title;
  final VoidCallback onBack;

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
      ],
    );
  }
}

class LiveDashboardHero extends StatefulWidget {
  const LiveDashboardHero({super.key});

  @override
  State<LiveDashboardHero> createState() => _LiveDashboardHeroState();
}

class _LiveDashboardHeroState extends State<LiveDashboardHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double pulse =
              0.76 + (math.sin(_controller.value * math.pi) * 0.24);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Transform.scale(
                    scale: 0.92 + pulse * 0.08,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(alpha: 0.16),
                      ),
                      child: Icon(
                        Icons.dashboard_customize_rounded,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Rodin live dashboard',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text('Native runtime online'),
                      ],
                    ),
                  ),
                  StatusPill(label: 'LIVE', accent: colors.secondary),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: <Widget>[
                  Expanded(
                    child: DashboardMetric(
                      title: 'Renderer',
                      value: 'Impeller',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: DashboardMetric(title: 'Display', value: '120 Hz'),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: DashboardMetric(title: 'Runtime', value: 'AOT'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({required this.title, required this.value, super.key});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    return SurfaceCard(
      child: Row(
        children: <Widget>[
          IconTile(icon: icon, accent: accent, size: 52),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class FeatureCard extends StatelessWidget {
  const FeatureCard({
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
      child: SurfaceCard(
        child: Row(
          children: <Widget>[
            IconTile(icon: icon, accent: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
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
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outline.withValues(alpha: 0.72)),
      ),
      child: child,
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    required this.accent,
    this.size = 46,
    super.key,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: accent, size: size * 0.5),
    );
  }
}

class SummaryChip extends StatelessWidget {
  const SummaryChip({
    required this.title,
    required this.subtitle,
    required this.accent,
    super.key,
  });

  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
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
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class PressScale extends StatefulWidget {
  const PressScale({required this.child, required this.onTap, super.key});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class RodinBottomBar extends StatelessWidget {
  const RodinBottomBar({
    required this.current,
    required this.onHome,
    required this.onHubs,
    required this.onSupport,
    super.key,
  });

  final RodinScreen current;
  final VoidCallback onHome;
  final VoidCallback onHubs;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool homeSelected = current == RodinScreen.home || !current.isRoot;
    final bool hubsSelected = current == RodinScreen.hubs;
    final bool supportSelected = current == RodinScreen.support;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        height: 68,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: colors.outline.withValues(alpha: 0.80)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: BottomBarItem(
                label: 'Home',
                icon: Icons.home_rounded,
                selected: homeSelected,
                onTap: onHome,
              ),
            ),
            Expanded(
              child: BottomBarItem(
                label: 'Hubs',
                icon: Icons.grid_view_rounded,
                selected: hubsSelected,
                onTap: onHubs,
              ),
            ),
            Expanded(
              child: BottomBarItem(
                label: 'Support',
                icon: Icons.help_outline_rounded,
                selected: supportSelected,
                onTap: onSupport,
              ),
            ),
          ],
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
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: foreground, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
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
