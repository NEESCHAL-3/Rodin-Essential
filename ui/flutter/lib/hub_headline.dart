import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'page_motion.dart';

class HubHeadlineCopy {
  const HubHeadlineCopy(
    this.lead,
    this.emphasis,
    this.description,
    this.light,
    this.dark,
  );
  final String lead, emphasis, description;
  final Color light, dark;
}

// NEESCHAL: personality belongs in the words, not invented hardware promises.
const hubHeadlines = <HubHeadlineCopy>[
  HubHeadlineCopy(
    'Control',
    'beyond cores.',
    'Explore CPU, GPU, memory and storage controls.',
    Color(0xFF087DA8),
    Color(0xFF67C2FF),
  ),
  HubHeadlineCopy(
    'Go',
    'beyond defaults.',
    'Choose your settings. Keep OEM control when you want it.',
    Color(0xFF7750BB),
    Color(0xFFB087FF),
  ),
  HubHeadlineCopy(
    'Your device.',
    'Your decisions.',
    'Adjust the details that matter to you.',
    Color(0xFF087E59),
    Color(0xFF41C98A),
  ),
  HubHeadlineCopy(
    'Every app.',
    'Its own rhythm.',
    'Create individual touch, refresh, CPU and GPU profiles.',
    Color(0xFF7750BB),
    Color(0xFFB087FF),
  ),
  HubHeadlineCopy(
    'Make every',
    'touch yours.',
    'Choose OEM response or a supported touch override.',
    Color(0xFF087E59),
    Color(0xFF41C98A),
  ),
  HubHeadlineCopy(
    'Find',
    'your balance.',
    'Fine-tune performance and power for your own routine.',
    Color(0xFF9A6518),
    Color(0xFFFFB84D),
  ),
  HubHeadlineCopy(
    'Set',
    'your own pace.',
    'Explore refresh-rate choices in Per-App Controls.',
    Color(0xFF087DA8),
    Color(0xFF67C2FF),
  ),
  HubHeadlineCopy(
    'Fine-tune',
    'the details.',
    'From frequency ranges to exact locks, choose your setup.',
    Color(0xFFB53D60),
    Color(0xFFFF819F),
  ),
  HubHeadlineCopy(
    'From memory',
    'to motion.',
    'Explore memory, storage, graphics and display controls.',
    Color(0xFF7750BB),
    Color(0xFFB087FF),
  ),
  HubHeadlineCopy(
    'Power',
    'on your terms.',
    'Explore charging controls supported by your device.',
    Color(0xFF9A6518),
    Color(0xFFFFB84D),
  ),
  HubHeadlineCopy(
    'Keep OEM.',
    'Or make it yours.',
    'Use vendor defaults or choose your own supported settings.',
    Color(0xFF087E59),
    Color(0xFF41C98A),
  ),
  HubHeadlineCopy(
    'One hub.',
    'More possibilities.',
    'Discover the controls available on your device.',
    Color(0xFF087DA8),
    Color(0xFF67C2FF),
  ),
];

/// One short transition per five-second reading interval, never a looping
/// ticker. Pauses offscreen, during navigation, in the background and for
/// reduced motion. Only this text subtree paints; telemetry keeps its state.
class HubHeadline extends StatefulWidget {
  const HubHeadline({super.key});
  @override
  State<HubHeadline> createState() => _HubHeadlineState();
}

class _HubHeadlineState extends State<HubHeadline>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion;
  Timer? _timer;
  ScrollPosition? _scroll;
  int _index = 0;
  bool _swapped = false;
  bool _enabled = false;
  bool _visible = true;
  bool _foreground = true;
  Object? _measurementKey;
  double _height = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _motion =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 360),
          )
          ..addListener(_swap)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _schedule();
          });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        !RodinMotionViewportScope.inFlightOf(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (_scroll != position) {
      _scroll?.removeListener(_checkVisibility);
      _scroll = position;
      _scroll?.addListener(_checkVisibility);
    }
    _schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkVisibility();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _checkVisibility() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox) return;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final visible = top < viewportBox.size.height && top + box.size.height > 0;
    if (_visible == visible) return;
    _visible = visible;
    _schedule();
  }

  void _schedule() {
    if (!_enabled || !_visible || !_foreground) {
      _timer?.cancel();
      _timer = null;
      // Finish the local text reveal before a root surface starts moving.
      // A muted ticker must never leave its headline invisible halfway.
      if (_motion.isAnimating) {
        _motion.stop();
        _motion.value = 1;
      }
      return;
    }
    if (_timer != null || _motion.isAnimating) return;
    _timer = Timer(const Duration(seconds: 5), () {
      _timer = null;
      if (!mounted || !_enabled || !_visible || !_foreground) return;
      _swapped = false;
      _motion.forward(from: 0);
    });
  }

  void _swap() {
    if (_motion.value >= 0.5 && !_swapped) {
      _swapped = true;
      setState(() => _index = (_index + 1) % hubHeadlines.length);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_checkVisibility);
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  TextSpan _title(HubHeadlineCopy copy, TextStyle style, Color accent) =>
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${copy.lead}\n'),
          TextSpan(
            text: copy.emphasis,
            style: TextStyle(color: accent),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = theme.textTheme.titleLarge!.copyWith(
      fontSize: 23,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.55,
      color: theme.colorScheme.onSurface,
    );
    final description = theme.textTheme.bodySmall!.copyWith(
      fontSize: 11,
      height: 1.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final measureKey = (
          constraints.maxWidth,
          scaler,
          direction,
          title,
          description,
        );
        if (_measurementKey != measureKey) {
          _measurementKey = measureKey;
          double titleHeight = 0, descriptionHeight = 0;
          for (final copy in hubHeadlines) {
            final heading = TextPainter(
              text: _title(copy, title, Colors.white),
              textDirection: direction,
              textScaler: scaler,
            )..layout(maxWidth: constraints.maxWidth);
            final body = TextPainter(
              text: TextSpan(text: copy.description, style: description),
              textDirection: direction,
              textScaler: scaler,
            )..layout(maxWidth: constraints.maxWidth);
            titleHeight = math.max(titleHeight, heading.height);
            descriptionHeight = math.max(descriptionHeight, body.height);
            heading.dispose();
            body.dispose();
          }
          _height = titleHeight + 8 + descriptionHeight;
        }
        final copy = hubHeadlines[_index];
        final accent = theme.brightness == Brightness.dark
            ? copy.dark
            : copy.light;
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(text: _title(copy, title, accent), textScaler: scaler),
            const SizedBox(height: 8),
            Text(copy.description, style: description),
          ],
        );
        return SizedBox(
          height: _height,
          width: double.infinity,
          child: RepaintBoundary(
            child: Semantics(
              label: '${copy.lead} ${copy.emphasis} ${copy.description}',
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _motion,
                  child: content,
                  builder: (context, child) {
                    final value = _motion.value;
                    final incoming = value >= 0.5;
                    final eased = Curves.easeInOutCubic.transform(
                      incoming ? (value - 0.5) * 2 : value * 2,
                    );
                    final opacity = incoming ? eased : 1 - eased;
                    return Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          incoming ? 3 * (1 - eased) : -3 * eased,
                        ),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
