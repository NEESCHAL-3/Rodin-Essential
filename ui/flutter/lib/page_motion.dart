import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'dart:async';

/// One restrained motion vocabulary. NEESCHAL: a control should feel alive,
/// but it should never make the user wait for the decoration to finish.
class RodinMotion {
  static final SpringDescription settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.94,
  );
  static final SpringDescription reveal = SpringDescription.withDampingRatio(
    mass: 0.8,
    stiffness: 420,
    ratio: 0.86,
  );

  static SpringSimulation cancelBack(double progress) => SpringSimulation(
    settle,
    progress,
    0,
    0,
    // A tiny positive residue would keep the predictive snapshot enabled.
    snapToEnd: true,
  );
}

class RodinBackMotion {
  static final ValueNotifier<double> progress = ValueNotifier<double>(0);
  static bool nested = false;
  static bool rightEdge = false;
  static double committedProgress = 0;
}

/// Bounded full-screen preview, shared by the gesture and its release animation.
/// A 90% surface leaves room for an 8dp edge gap; it must not follow the finger
/// all the way off-screen before Android has decided whether Back commits.
class RodinBackGeometry {
  static double eased(double progress) =>
      Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
  static double scale(double progress) => 1 - 0.10 * eased(progress);
  static double radius(double progress) => 20 * eased(progress);
  static double maxShift(double width) =>
      (width * 0.05 - 8).clamp(0.0, double.infinity);
  static double shift(double width, double progress, bool rightEdge) =>
      (rightEdge ? -1 : 1) * maxShift(width) * eased(progress);
}

/// Spend the opening frame on visible controls, not speculative scroll cache.
/// This inherited value changes only at the boundaries of a transition; it
/// does not ask descendants to rebuild for every animation tick.
class RodinMotionViewportScope extends InheritedWidget {
  const RodinMotionViewportScope({
    required this.inFlight,
    required super.child,
    super.key,
  });
  final bool inFlight;

  static bool inFlightOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RodinMotionViewportScope>()
          ?.inFlight ??
      false;

  static double scrollCacheExtentOf(BuildContext context) =>
      inFlightOf(context) ? 0 : 250;

  @override
  bool updateShouldNotify(RodinMotionViewportScope oldWidget) =>
      oldWidget.inFlight != inFlight;
}

/// Keep receiving real data while a page is moving or hidden, but do not
/// rebuild its expensive controls for each live sample. On return to rest,
/// render the latest reading immediately; this never queues hardware writes.
class RodinMotionStreamBuilder<T> extends StatefulWidget {
  const RodinMotionStreamBuilder({
    required this.stream,
    required this.readLatest,
    required this.builder,
    super.key,
  });
  final Stream<T> stream;
  final T Function() readLatest;
  final Widget Function(T value) builder;

  @override
  State<RodinMotionStreamBuilder<T>> createState() =>
      _RodinMotionStreamBuilderState<T>();
}

class _RodinMotionStreamBuilderState<T>
    extends State<RodinMotionStreamBuilder<T>> {
  late T _latest;
  StreamSubscription<T>? _subscription;
  bool _canPresent = false;

  @override
  void initState() {
    super.initState();
    _latest = widget.readLatest();
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.stream.listen(
      (value) {
        _latest = value;
        if (mounted && _canPresent) setState(() {});
      },
      // Preserve the last acknowledged reading, as the previous StreamBuilder
      // did; a presentation error must not become an unhandled stream error.
      onError: (Object error, StackTrace trace) {},
    );
  }

  @override
  void didUpdateWidget(RodinMotionStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _subscription?.cancel();
      _latest = widget.readLatest();
      _subscribe();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _canPresent =
        TickerMode.valuesOf(context).enabled &&
        !RodinMotionViewportScope.inFlightOf(context);
    if (_canPresent) _latest = widget.readLatest();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_latest);
}

/// Flutter's texture-backed snapshot keeps scale animations from repeatedly
/// rasterizing every shadow, blur and glyph. The real subtree stays mounted;
/// its live paint resumes immediately when this bounded motion finishes.
class RodinSurfaceSnapshot extends StatefulWidget {
  const RodinSurfaceSnapshot({
    required this.enabled,
    required this.child,
    super.key,
  });
  final bool enabled;
  final Widget child;
  @override
  State<RodinSurfaceSnapshot> createState() => _RodinSurfaceSnapshotState();
}

class _RodinSurfaceSnapshotState extends State<RodinSurfaceSnapshot> {
  final SnapshotController controller = SnapshotController();
  bool _painted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _painted = true;
      // A new page already has its first layout/paint to do. Do not allocate
      // its full-screen snapshot in that same cold frame as well. Its normal
      // surface moves immediately; following frames use the cached texture.
      controller.allowSnapshotting = widget.enabled;
    });
  }

  @override
  void didUpdateWidget(RodinSurfaceSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    controller.allowSnapshotting = _painted && widget.enabled;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: controller,
    mode: SnapshotMode.permissive,
    autoresize: true,
    child: widget.child,
  );
}

/// Progress comes from Android's edge gesture, not a simulated timed swipe.
class RodinPredictivePlane extends StatelessWidget {
  const RodinPredictivePlane({
    required this.child,
    this.destination,
    this.nested = false,
    super.key,
  });
  final Widget child;
  final Widget? destination;
  final bool nested;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: RodinBackMotion.progress,
    child: child,
    builder: (context, _, child) {
      final value =
          RodinBackMotion.nested == nested &&
              !MediaQuery.disableAnimationsOf(context)
          ? RodinBackMotion.progress.value
          : 0.0;
      final color = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF090C11)
          : const Color(0xFFF3F6FA);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (destination != null && value > 0)
            IgnorePointer(
              child: ExcludeSemantics(
                child: TickerMode(
                  enabled: false,
                  child: Material(color: color, child: destination),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(
              RodinBackGeometry.shift(
                MediaQuery.sizeOf(context).width,
                value,
                RodinBackMotion.rightEdge,
              ),
              0,
            ),
            child: Transform.scale(
              scale: RodinBackGeometry.scale(value),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  RodinBackGeometry.radius(value),
                ),
                child: RodinSurfaceSnapshot(
                  enabled: value > 0,
                  child: RodinMotionViewportScope(
                    inFlight:
                        (!MediaQuery.disableAnimationsOf(context) &&
                            RodinBackMotion.progress.value > 0) ||
                        RodinMotionViewportScope.inFlightOf(context),
                    child: Material(color: color, child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Short, bounded arrivals; controls remain hit-testable during the reveal.
/// No ticker survives at rest, and reduced-motion skips both delay and spring.
class RodinArrival extends StatefulWidget {
  const RodinArrival({required this.child, required this.order, super.key});
  final Widget child;
  final int order;
  @override
  State<RodinArrival> createState() => _RodinArrivalState();
}

class _RodinArrivalState extends State<RodinArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  Timer? delay;
  bool started = false;
  @override
  void initState() {
    super.initState();
    motion = AnimationController.unbounded(vsync: this, value: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        RodinMotionViewportScope.inFlightOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      delay?.cancel();
      motion.stop();
      motion.value = 1;
      started = true;
      return;
    }
    if (started) return;
    started = true;
    delay = Timer(Duration(milliseconds: (widget.order * 8).clamp(0, 48)), () {
      if (mounted)
        motion.animateWith(
          SpringSimulation(RodinMotion.reveal, motion.value, 1, 0),
        );
    });
  }

  @override
  void dispose() {
    delay?.cancel();
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) {
      final progress = motion.value.clamp(0.0, 1.04);
      return Transform.translate(
        offset: Offset(0, 7 * (1 - progress)),
        child: Transform.scale(
          scale: 0.995 + 0.005 * progress,
          alignment: Alignment.topCenter,
          child: Opacity(opacity: progress.clamp(0.0, 1.0), child: child),
        ),
      );
    },
  );
}

class RodinScrollPhysics extends BouncingScrollPhysics {
  const RodinScrollPhysics({super.parent})
    : super(decelerationRate: ScrollDecelerationRate.fast);
  @override
  RodinScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      RodinScrollPhysics(parent: buildParent(ancestor));
  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.65,
    stiffness: 210,
    ratio: 0.98,
  );
  @override
  double get maxFlingVelocity => 6500;
  @override
  double carriedMomentum(double velocity) =>
      super.carriedMomentum(velocity).clamp(-3500.0, 3500.0);
}

class RodinScrollBehavior extends MaterialScrollBehavior {
  const RodinScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const RodinScrollPhysics();
}

class RodinScrollMotionScope extends InheritedWidget {
  const RodinScrollMotionScope({
    required this.velocity,
    required super.child,
    super.key,
  });
  final ValueNotifier<double> velocity;
  static ValueNotifier<double>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RodinScrollMotionScope>()
      ?.velocity;
  @override
  bool updateShouldNotify(RodinScrollMotionScope oldWidget) =>
      velocity != oldWidget.velocity;
}

/// Velocity supplies the impulse; the spring supplies the return to rest.
/// Cached content never rebuilds for these transforms. No perpetual ticker.
class RodinInertiaLayer extends StatefulWidget {
  const RodinInertiaLayer({required this.child, super.key});
  final Widget child;
  @override
  State<RodinInertiaLayer> createState() => _RodinInertiaLayerState();
}

class _RodinInertiaLayerState extends State<RodinInertiaLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _depth = AnimationController.unbounded(
    vsync: this,
  );
  ValueNotifier<double>? _velocity;
  bool _reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    final next = RodinScrollMotionScope.of(context);
    if (next != _velocity) {
      _velocity?.removeListener(_followVelocity);
      _velocity = next;
      _velocity?.addListener(_followVelocity);
    }
    if (_reduced) _depth.value = 0;
  }

  void _followVelocity() {
    if (_reduced || !mounted) return;
    final target = ((_velocity?.value ?? 0) / 4000).clamp(-1.0, 1.0);
    _depth.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 0.9,
          stiffness: 280,
          ratio: 0.9,
        ),
        _depth.value,
        target,
        _depth.velocity.clamp(-4.0, 4.0),
      ),
    );
  }

  @override
  void dispose() {
    _velocity?.removeListener(_followVelocity);
    _depth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _depth,
    child: RepaintBoundary(child: widget.child),
    builder: (_, child) {
      final depth = _reduced ? 0.0 : _depth.value.clamp(-1.0, 1.0);
      return Transform.translate(
        offset: Offset(0, depth * 3),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(depth * 0.004),
          child: child,
        ),
      );
    },
  );
}

/// Sample a damped spring instead of stacking unrelated easing curves.
/// Position may settle just past the target; opacity never overshoots.
class RodinSpringCurve extends Curve {
  const RodinSpringCurve();
  static final SpringSimulation _spring = SpringSimulation(
    const SpringDescription(mass: 1, stiffness: 330, damping: 29),
    0,
    1,
    1.5,
  );
  @override
  double transformInternal(double t) => _spring.x(t * 0.48);
}

/// One restrained reveal for confirmation dialogs. Keep inherited appearance
/// captured at the caller, rather than silently falling back to theme defaults.
Future<T?> showRodinDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 240),
    pageBuilder: (context, _, secondary) =>
        themes.wrap(SafeArea(child: Builder(builder: builder))),
    transitionBuilder: (context, animation, secondary, child) =>
        AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final progress = animation.status == AnimationStatus.reverse
                ? 1 - const RodinSpringCurve().transform(1 - animation.value)
                : const RodinSpringCurve().transform(animation.value);
            return Opacity(
              opacity: progress.clamp(0.0, 1.0),
              child: FractionalTranslation(
                translation: Offset(0, 0.025 * (1 - progress)),
                child: Transform.scale(
                  scale: 0.975 + 0.025 * progress,
                  child: child,
                ),
              ),
            );
          },
        ),
  );
}

/// Keep the departing detail above the destination during Back, so its solid
/// surface reveals the destination continuously instead of fading text together.
Widget rodinDetailLayout(
  Widget? current,
  List<Widget> previous, {
  required bool forward,
}) => ClipRect(
  child: Stack(
    fit: StackFit.expand,
    children: forward
        ? <Widget>[...previous, if (current != null) current]
        : <Widget>[if (current != null) current, ...previous],
  ),
);

/// A solid page plane: outgoing text must never blend with the page underneath.
/// Back returns along the same path; nested pages order the departing page last.
class RodinDetailTransition extends StatelessWidget {
  const RodinDetailTransition({
    required this.animation,
    required this.child,
    required this.active,
    this.forward = true,
    this.previewThrough = false,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final bool active;
  final bool forward;

  /// The child already owns its opaque surface. Do not paint a second full-size
  /// background behind it, or its predictive shrink hides the real back page.
  final bool previewThrough;

  @override
  Widget build(BuildContext context) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final double direction = Directionality.of(context) == TextDirection.rtl
        ? -1
        : 1;
    // Capture inherited appearance here, not from a deactivated outgoing page.
    final Color background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF090C11)
        : const Color(0xFFF3F6FA);
    // Capture the gesture's final geometry once for this outgoing transition;
    // later gestures must not change a page which is already departing.
    final committed = !forward && !active
        ? RodinBackMotion.committedProgress
        : 0.0;
    final gestureEdge = RodinBackMotion.rightEdge ? -1.0 : 1.0;
    final width = MediaQuery.sizeOf(context).width;
    final startShift = width > 0
        ? RodinBackGeometry.maxShift(width) *
              RodinBackGeometry.eased(committed) /
              width
        : 0.0;
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: TickerMode(
          enabled: active,
          child: AnimatedBuilder(
            animation: animation,
            child: RepaintBoundary(
              child: previewThrough
                  ? SizedBox.expand(child: child)
                  : Material(
                      color: background,
                      child: SizedBox.expand(child: child),
                    ),
            ),
            builder: (BuildContext context, Widget? child) {
              final inFlight =
                  !reduced &&
                  animation.status != AnimationStatus.completed &&
                  animation.status != AnimationStatus.dismissed;
              final double raw = animation.value.clamp(0.0, 1.0);
              final double progress = reduced
                  ? 1
                  : animation.status == AnimationStatus.reverse
                  ? 1 - Curves.easeOutCubic.transform(1 - raw)
                  : Curves.easeOutCubic.transform(raw);
              final double travel = forward
                  ? (active ? 1.0 : -0.10)
                  : (active ? -0.10 : 1.0);
              return FractionalTranslation(
                translation: Offset(
                  (committed > 0 ? gestureEdge : direction) *
                      (committed > 0
                          ? startShift + (1 - startShift) * (1 - progress)
                          : travel * (1 - progress)),
                  0,
                ),
                child: Transform.scale(
                  scale: reduced
                      ? 1
                      : committed > 0
                      ? RodinBackGeometry.scale(committed)
                      : 0.985 + 0.015 * progress,
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      committed > 0
                          ? RodinBackGeometry.radius(committed) +
                                (20 - RodinBackGeometry.radius(committed)) *
                                    (1 - progress)
                          : 12 * (1 - progress).clamp(0.0, 1.0),
                    ),
                    child: RodinSurfaceSnapshot(
                      enabled: inFlight,
                      child: RodinMotionViewportScope(
                        inFlight:
                            inFlight ||
                            RodinMotionViewportScope.inFlightOf(context),
                        child: child!,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
