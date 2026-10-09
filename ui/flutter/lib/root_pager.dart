import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'page_motion.dart';

/// A tab tap has one destination, not a sightseeing tour of the other hubs.
/// NEESCHAL: keep the route direct, and keep the user's page state intact.
class RodinTabHandoff {
  RodinTabHandoff({
    required this.startPage,
    required this.target,
    required Map<int, double> positions,
    required int direction,
  }) : starts = Map<int, double>.of(positions),
       ends = <int, double>{
         for (final index in positions.keys) index: -direction.toDouble(),
       } {
    starts.putIfAbsent(target, () => direction.toDouble());
    ends[target] = 0;
  }

  final double startPage;
  final int target;
  final Map<int, double> starts;
  final Map<int, double> ends;

  Map<int, double> positionsAt(double page) {
    final distance = target - startPage;
    final progress = distance.abs() < 0.00001
        ? 1.0
        : ((page - startPage) / distance).clamp(0.0, 1.0);
    return <int, double>{
      for (final index in starts.keys)
        index: starts[index]! + (ends[index]! - starts[index]!) * progress,
    };
  }
}

/// PageController remains the single source of drag/fling and dock progress.
/// Its inexpensive page slots do not render the content. Content has stable
/// keyed slots here, so a direct tab handoff never mounts an intermediate page
/// and never reparents a visited page to a fresh subtree.
class RodinRootPager extends StatefulWidget {
  const RodinRootPager({
    required this.controller,
    required this.children,
    required this.onPageChanged,
    required this.onDragStart,
    required this.swipeEnabled,
    required this.physics,
    super.key,
  });
  final PageController controller;
  final List<Widget> children;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onDragStart;
  final bool swipeEnabled;
  final ScrollPhysics physics;

  @override
  State<RodinRootPager> createState() => RodinRootPagerState();
}

class RodinRootPagerState extends State<RodinRootPager> {
  RodinTabHandoff? _handoff;
  final Set<int> _visited = <int>{};
  Drag? _drag;

  double get _page => widget.controller.hasClients
      ? widget.controller.page ?? widget.controller.initialPage.toDouble()
      : widget.controller.initialPage.toDouble();

  Map<int, double> _positions() =>
      _handoff?.positionsAt(_page) ??
      <int, double>{
        for (var index = 0; index < widget.children.length; index++)
          if ((index - _page).abs() < 1.00001) index: index - _page,
      };

  int get visibleIndex {
    final positions = _positions();
    return positions.keys.reduce(
      (a, b) => positions[a]!.abs() <= positions[b]!.abs() ? a : b,
    );
  }

  void prepareJump(int target) {
    final positions = Map<int, double>.of(_positions())
      ..removeWhere((_, offset) => offset.abs() >= 0.99999);
    final startPage = _page;
    // Capture the current geometry, not the previous animation's endpoint.
    // Reversing A→B→A therefore starts where the surfaces actually are.
    setState(() {
      _handoff = RodinTabHandoff(
        startPage: startPage,
        target: target,
        positions: positions,
        // A drag may already be closest to its destination, but still need
        // to settle LEFT. Comparing rounded indices makes the other surface
        // cross over it. Keep adjacent pages exactly one viewport apart.
        direction: target >= startPage ? 1 : -1,
      );
    });
  }

  void finishJump() {
    if (!mounted || _handoff == null) return;
    setState(() => _handoff = null);
  }

  void _startDrag(DragStartDetails details) {
    widget.onDragStart();
    _drag?.cancel();
    _drag = widget.controller.position.drag(details, () => _drag = null);
  }

  @override
  void dispose() {
    _drag?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: widget.swipeEnabled ? _startDrag : null,
    onHorizontalDragUpdate: widget.swipeEnabled
        ? (details) => _drag?.update(details)
        : null,
    onHorizontalDragEnd: widget.swipeEnabled
        ? (details) => _drag?.end(details)
        : null,
    onHorizontalDragCancel: widget.swipeEnabled ? () => _drag?.cancel() : null,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: ExcludeSemantics(
            child: PageView(
              controller: widget.controller,
              physics: widget.physics,
              onPageChanged: widget.onPageChanged,
              children: <Widget>[
                for (var index = 0; index < widget.children.length; index++)
                  const SizedBox.expand(),
              ],
            ),
          ),
        ),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final positions = _positions();
            final active = visibleIndex;
            final moving =
                _handoff != null || (_page - _page.round()).abs() > 0.00001;
            final direction = Directionality.of(context) == TextDirection.rtl
                ? -1.0
                : 1.0;
            for (final entry in positions.entries) {
              if (entry.value.abs() < 1) _visited.add(entry.key);
            }
            if (_handoff != null) _visited.add(_handoff!.target);
            // Every page retains the same keyed parent and position in the
            // tree. Offstage pages keep their state but do not paint/tick.
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  for (var index = 0; index < widget.children.length; index++)
                    Offstage(
                      key: ValueKey<int>(index),
                      offstage: (positions[index] ?? 2).abs() >= 1,
                      child: ExcludeSemantics(
                        excluding: moving || index != active,
                        child: IgnorePointer(
                          ignoring: moving || index != active,
                          child: TickerMode(
                            enabled: !moving && index == active,
                            child: FractionalTranslation(
                              translation: Offset(
                                (positions[index] ?? 2) * direction,
                                0,
                              ),
                              child: RodinMotionViewportScope(
                                inFlight: moving,
                                // This is translation, not rescaling a page.
                                // Stable display lists are enough; capturing
                                // two full-screen images adds a cold GPU spike.
                                child: _visited.contains(index)
                                    ? widget.children[index]
                                    : const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
