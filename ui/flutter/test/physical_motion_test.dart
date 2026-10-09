import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/page_motion.dart';

void main() {
  tearDown(() {
    RodinBackMotion.progress.value = 0;
    RodinBackMotion.nested = false;
    RodinBackMotion.rightEdge = false;
    RodinBackMotion.committedProgress = 0;
  });
  testWidgets('previewed destination cannot receive taps during Back', (
    tester,
  ) async {
    var taps = 0;
    RodinBackMotion.progress.value = 0.8;
    await tester.pumpWidget(
      MaterialApp(
        home: RodinPredictivePlane(
          destination: GestureDetector(
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(2, 200));
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'predictive progress exposes a solid destination and cancels cleanly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RodinPredictivePlane(
            destination: Text('Destination'),
            child: Text('Current page'),
          ),
        ),
      );
      expect(find.text('Destination'), findsNothing);
      RodinBackMotion.progress.value = 0.5;
      await tester.pump();
      expect(find.text('Destination'), findsOneWidget);
      final transforms = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(RodinPredictivePlane),
              matching: find.byType(Transform),
            ),
          )
          .toList();
      expect(transforms.first.transform.storage[12], greaterThan(0));
      RodinBackMotion.progress.value = 0;
      await tester.pump();
      expect(find.text('Destination'), findsNothing);
      expect(find.text('Current page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('nested predictive motion does not transform the parent twice', (
    tester,
  ) async {
    RodinBackMotion.nested = true;
    RodinBackMotion.progress.value = 0.5;
    await tester.pumpWidget(
      const MaterialApp(
        home: RodinPredictivePlane(
          child: RodinPredictivePlane(
            nested: true,
            destination: Text('App list'),
            child: Text('App editor'),
          ),
        ),
      ),
    );
    expect(find.text('App list'), findsOneWidget);
    final transforms = tester
        .widgetList<Transform>(find.byType(Transform))
        .toList();
    expect(transforms.length, 4);
    expect(transforms[0].transform.storage[12], 0);
    expect(transforms[1].transform.storage[0], 1);
    expect(transforms[2].transform.storage[12], greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion removes gesture transforms and arrival delay', (
    tester,
  ) async {
    RodinBackMotion.progress.value = 0.7;
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RodinPredictivePlane(
            child: RodinArrival(order: 20, child: Text('Ready')),
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('rapid teardown cancels delayed reveals without leaked tickers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RodinArrival(order: 9, child: Text('Card'))),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('right-edge Back follows the right edge', (tester) async {
    RodinBackMotion.rightEdge = true;
    RodinBackMotion.progress.value = 0.6;
    await tester.pumpWidget(
      const MaterialApp(home: RodinPredictivePlane(child: Text('Current'))),
    );
    final transform = tester
        .widgetList<Transform>(find.byType(Transform))
        .first;
    expect(transform.transform.storage[12], lessThan(0));
  });
  testWidgets('gesture start and cancellation preserve page state', (
    tester,
  ) async {
    var creations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RodinPredictivePlane(
          destination: const Text('Preview destination'),
          child: _StateProbe(onCreate: () => creations++),
        ),
      ),
    );
    expect(creations, 1);
    RodinBackMotion.progress.value = 0.4;
    await tester.pump();
    RodinBackMotion.progress.value = 0;
    await tester.pump();
    expect(creations, 1);
  });
  test(
    'preview is bounded, mirrored, and shrinks to the Android surface size',
    () {
      expect(RodinBackGeometry.scale(0), 1);
      expect(RodinBackGeometry.scale(1), closeTo(0.9, 0.00001));
      expect(RodinBackGeometry.shift(400, 1, false), 12);
      expect(RodinBackGeometry.shift(400, 1, true), -12);
      expect(RodinBackGeometry.shift(100, 1, true), 0);
      expect(RodinBackGeometry.radius(1), 20);
    },
  );
  testWidgets('gesture completion starts at the exact preview geometry', (
    tester,
  ) async {
    RodinBackMotion.rightEdge = true;
    RodinBackMotion.committedProgress = 0.65;
    await tester.pumpWidget(
      MaterialApp(
        home: RodinDetailTransition(
          animation: const AlwaysStoppedAnimation(1),
          forward: false,
          active: false,
          child: const SizedBox.expand(),
        ),
      ),
    );
    final scale = tester.widget<Transform>(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Transform),
      ),
    );
    expect(
      scale.transform.storage[0],
      closeTo(RodinBackGeometry.scale(0.65), 0.00001),
    );
    final translation = tester.widget<FractionalTranslation>(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(FractionalTranslation),
      ),
    );
    final width = tester.getSize(find.byType(RodinDetailTransition)).width;
    expect(
      translation.translation.dx * width,
      closeTo(RodinBackGeometry.shift(width, 0.65, true), 0.00001),
    );
    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      clip.borderRadius,
      BorderRadius.circular(RodinBackGeometry.radius(0.65)),
    );
  });
  testWidgets('root preview has no opaque wrapper hiding its destination', (
    tester,
  ) async {
    RodinBackMotion.progress.value = 0.5;
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            ColoredBox(color: Colors.red, child: SizedBox.expand()),
            RodinDetailTransition(
              animation: AlwaysStoppedAnimation(1),
              active: true,
              previewThrough: true,
              child: RodinPredictivePlane(child: Text('Foreground')),
            ),
          ],
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Material),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled spring releases the snapshot at exactly zero', (
    tester,
  ) async {
    final controller = AnimationController.unbounded(
      vsync: tester,
      value: 0.65,
    );
    controller.addListener(() {
      RodinBackMotion.progress.value = controller.value.clamp(0.0, 1.0);
    });
    RodinBackMotion.progress.value = controller.value;
    await tester.pumpWidget(
      const MaterialApp(
        home: RodinPredictivePlane(
          destination: Text('Destination'),
          child: Text('Live page'),
        ),
      ),
    );
    controller.animateWith(RodinMotion.cancelBack(controller.value));
    await tester.pumpAndSettle();
    expect(controller.value, 0);
    expect(RodinBackMotion.progress.value, 0);
    expect(find.text('Destination'), findsNothing);
    expect(
      tester
          .widget<RodinSurfaceSnapshot>(find.byType(RodinSurfaceSnapshot))
          .enabled,
      false,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested preview keeps no duplicate full-size opaque surface', (
    tester,
  ) async {
    RodinBackMotion.nested = true;
    RodinBackMotion.progress.value = 0.5;
    await tester.pumpWidget(
      const MaterialApp(
        home: RodinDetailTransition(
          animation: AlwaysStoppedAnimation(1),
          active: true,
          previewThrough: true,
          child: RodinPredictivePlane(
            nested: true,
            destination: Text('Previous nested page'),
            child: Text('Nested foreground'),
          ),
        ),
      ),
    );
    // One material belongs to the previous page, the other shrinks with the
    // foreground. A third outer material would cover the preview again.
    expect(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Material),
      ),
      findsNWidgets(2),
    );
    expect(find.text('Previous nested page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion viewport changes at boundaries, not every frame', (
    tester,
  ) async {
    var builds = 0;
    final cacheExtents = <double>[];
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
    );
    addTearDown(controller.dispose);
    controller.forward();
    await tester.pumpWidget(
      MaterialApp(
        home: RodinDetailTransition(
          animation: controller,
          active: true,
          child: RodinPredictivePlane(
            child: Builder(
              builder: (context) {
                builds++;
                cacheExtents.add(
                  RodinMotionViewportScope.scrollCacheExtentOf(context),
                );
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    expect(cacheExtents.last, 0);
    final firstBuilds = builds;
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, firstBuilds);
    await tester.pumpAndSettle();
    expect(cacheExtents.last, 250);
    expect(builds, firstBuilds + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live samples coalesce during motion and resume at latest', (
    tester,
  ) async {
    final stream = StreamController<int>.broadcast();
    final moving = ValueNotifier<bool>(false);
    final visible = ValueNotifier<bool>(true);
    var latest = 1;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: visible,
          child: ValueListenableBuilder<bool>(
            valueListenable: moving,
            child: RodinMotionStreamBuilder<int>(
              stream: stream.stream,
              readLatest: () => latest,
              builder: (value) {
                builds++;
                return Text('Reading $value');
              },
            ),
            builder: (_, inFlight, child) =>
                RodinMotionViewportScope(inFlight: inFlight, child: child!),
          ),
          builder: (_, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
        ),
      ),
    );
    latest = 2;
    stream.add(latest);
    await tester.pump();
    expect(find.text('Reading 2'), findsOneWidget);
    moving.value = true;
    await tester.pump();
    final motionBuilds = builds;
    latest = 3;
    stream.add(latest);
    latest = 4;
    stream.add(latest);
    await tester.pump();
    expect(builds, motionBuilds);
    expect(find.text('Reading 2'), findsOneWidget);
    moving.value = false;
    await tester.pump();
    expect(find.text('Reading 4'), findsOneWidget);
    visible.value = false;
    await tester.pump();
    final hiddenBuilds = builds;
    latest = 5;
    stream.add(latest);
    await tester.pump();
    expect(builds, hiddenBuilds);
    visible.value = true;
    await tester.pump();
    expect(find.text('Reading 5'), findsOneWidget);
    stream.addError(StateError('temporary read failure'));
    await tester.pump();
    expect(find.text('Reading 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(stream.hasListener, false);
    await stream.close();
    moving.dispose();
    visible.dispose();
  });

  testWidgets('cold surface paints before snapshot allocation', (tester) async {
    final enabled = ValueNotifier<bool>(true);
    final initialSnapshotStates = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          child: Builder(
            builder: (context) {
              initialSnapshotStates.add(
                context
                    .findAncestorWidgetOfExactType<SnapshotWidget>()!
                    .controller
                    .allowSnapshotting,
              );
              return const SizedBox.expand();
            },
          ),
          builder: (_, capture, child) =>
              RodinSurfaceSnapshot(enabled: capture, child: child!),
        ),
      ),
    );
    expect(initialSnapshotStates, [false]);
    final controller = tester
        .widget<SnapshotWidget>(find.byType(SnapshotWidget))
        .controller;
    expect(controller.allowSnapshotting, true);
    enabled.value = false;
    await tester.pump();
    expect(controller.allowSnapshotting, false);
    await tester.pumpWidget(const SizedBox());
    enabled.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested Back also gates the parent telemetry presentation', (
    tester,
  ) async {
    RodinBackMotion.nested = true;
    RodinBackMotion.progress.value = 0.5;
    await tester.pumpWidget(
      MaterialApp(
        home: RodinPredictivePlane(
          child: Builder(
            builder: (context) => Text(
              'Cache ${RodinMotionViewportScope.scrollCacheExtentOf(context)}',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Cache 0.0'), findsOneWidget);
    final scale = tester.widgetList<Transform>(find.byType(Transform)).last;
    expect(scale.transform.storage[0], 1);
    RodinBackMotion.progress.value = 0;
    await tester.pump();
    expect(find.text('Cache 250.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.onCreate});
  final VoidCallback onCreate;
  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
