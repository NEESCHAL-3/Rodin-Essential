import 'dart:math' as math;
import 'package:flutter/material.dart';

/// App-local soft-light response, not a dependency on an OEM glass engine.
/// Position changes notify only the painter; there is no shader compilation,
/// extra backdrop blur, saveLayer, or perpetual animation during a hold.
class RodinTouchLight extends StatefulWidget {
  const RodinTouchLight({
    required this.child,
    required this.accent,
    this.radius = 22,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final Color accent;
  final double radius;
  final bool enabled;

  @override
  State<RodinTouchLight> createState() => RodinTouchLightState();
}

class RodinTouchLightState extends State<RodinTouchLight>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset> _point = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _strength;
  late final Listenable _paint;
  int? _pointer;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _strength = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _paint = Listenable.merge(<Listenable>[_point, _strength]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced && _strength.isAnimating) {
      _strength.stop();
      _strength.value = _pointer == null ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(RodinTouchLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) cancel();
  }

  void cancel() {
    _pointer = null;
    if (_reduced) {
      _strength.value = 0;
    } else {
      _strength.reverse();
    }
  }

  @override
  void dispose() {
    _strength.dispose();
    _point.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_pointer != null) return;
        _pointer = event.pointer;
        _point.value = event.localPosition;
        if (_reduced) {
          _strength.value = 1;
        } else {
          // First-frame feedback must not wait for the animation's first tick.
          _strength.value = math.max(0.25, _strength.value);
          _strength.forward();
        }
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        final size = context.size;
        if (size == null ||
            !(Offset.zero & size).contains(event.localPosition)) {
          cancel();
          return;
        }
        _point.value = event.localPosition;
      },
      onPointerUp: (event) {
        if (event.pointer == _pointer) cancel();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) cancel();
      },
      child: Stack(
        children: <Widget>[
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: RodinTouchLightPainter(
                      repaint: _paint,
                      point: _point,
                      strength: _strength,
                      accent: widget.accent,
                      radius: widget.radius,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RodinTouchLightPainter extends CustomPainter {
  RodinTouchLightPainter({
    required super.repaint,
    required this.point,
    required this.strength,
    required this.accent,
    required this.radius,
    required this.dark,
  });
  final ValueNotifier<Offset> point;
  final Animation<double> strength;
  final Color accent;
  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final power = strength.value.clamp(0.0, 1.0);
    if (power <= 0 || size.isEmpty) return;
    final bounds = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      bounds.deflate(0.6),
      Radius.circular(radius.clamp(0.0, size.shortestSide / 2)),
    );
    final lightRadius = math.min(
      140.0,
      math.max(55.0, size.longestSide * 0.42),
    );
    final lightBounds = Rect.fromCircle(
      center: point.value,
      radius: lightRadius,
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Color.lerp(
              accent,
              Colors.white,
              0.50,
            )!.withValues(alpha: (dark ? 0.19 : 0.11) * power),
            accent.withValues(alpha: (dark ? 0.11 : 0.065) * power),
            accent.withValues(alpha: 0),
          ],
          stops: const <double>[0, 0.32, 1],
        ).createShader(lightBounds),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: (dark ? 0.65 : 0.80) * power),
            accent.withValues(alpha: 0.34 * power),
            accent.withValues(alpha: 0),
          ],
          stops: const <double>[0, 0.45, 1],
        ).createShader(lightBounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(RodinTouchLightPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.radius != radius ||
      oldDelegate.dark != dark ||
      oldDelegate.point != point ||
      oldDelegate.strength != strength;

  @override
  bool? hitTest(Offset position) => false;
}
