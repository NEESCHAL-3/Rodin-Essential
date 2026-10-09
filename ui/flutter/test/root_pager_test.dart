import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/page_motion.dart';
import 'package:rodin_essential_ui/root_pager.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets('settling back toward Home never crosses the adjacent layer', (
    tester,
  ) async {
    final controller = PageController();
    final key = GlobalKey<RodinRootPagerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinRootPager(
            key: key,
            controller: controller,
            swipeEnabled: true,
            physics: const PageScrollPhysics(),
            onDragStart: () {},
            onPageChanged: (_) {},
            children: <Widget>[
              for (var index = 0; index < 4; index++)
                _Probe(index: index, onCreate: (_) {}),
            ],
          ),
        ),
      ),
    );
    double offset(int index) => tester
        .widget<FractionalTranslation>(
          find
              .ancestor(
                of: find.text('Page $index'),
                matching: find.byType(FractionalTranslation),
              )
              .first,
        )
        .translation
        .dx;
    controller.jumpTo(controller.position.viewportDimension * 0.35);
    await tester.pump();
    key.currentState!.prepareJump(0);
    controller.jumpTo(controller.position.viewportDimension * 0.175);
    await tester.pump();
    expect(offset(1) - offset(0), closeTo(1, 0.00001));
    key.currentState!.finishJump();
    controller.jumpToPage(0);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('every adjacent dock settle keeps pages one viewport apart', (
    tester,
  ) async {
    final controller = PageController();
    final key = GlobalKey<RodinRootPagerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinRootPager(
            key: key,
            controller: controller,
            swipeEnabled: true,
            physics: const PageScrollPhysics(),
            onDragStart: () {},
            onPageChanged: (_) {},
            children: <Widget>[
              for (var index = 0; index < 4; index++)
                _Probe(index: index, onCreate: (_) {}),
            ],
          ),
        ),
      ),
    );
    double offset(int index) => tester
        .widget<FractionalTranslation>(
          find
              .ancestor(
                of: find.text('Page $index'),
                matching: find.byType(FractionalTranslation),
              )
              .first,
        )
        .translation
        .dx;
    for (var lower = 0; lower < 3; lower++) {
      for (final fraction in <double>[0.35, 0.65]) {
        for (final target in <int>[lower, lower + 1]) {
          final start = lower + fraction;
          controller.jumpTo(controller.position.viewportDimension * start);
          await tester.pump();
          key.currentState!.prepareJump(target);
          for (final progress in <double>[0.25, 0.5, 0.75]) {
            controller.jumpTo(
              controller.position.viewportDimension *
                  (start + (target - start) * progress),
            );
            await tester.pump();
            expect(
              offset(lower + 1) - offset(lower),
              closeTo(1, 0.00001),
              reason: '$start → $target at $progress must never cross layers',
            );
          }
          controller.jumpToPage(target);
          key.currentState!.finishJump();
          await tester.pumpAndSettle();
          expect(find.text('Page $target'), findsOneWidget);
        }
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('non-adjacent tab taps move only source and destination', () {
    final handoff = RodinTabHandoff(
      startPage: 0,
      target: 3,
      positions: <int, double>{0: 0},
      direction: 1,
    );
    expect(handoff.positionsAt(1.5), <int, double>{0: -0.5, 3: 0.5});
    expect(handoff.positionsAt(3), <int, double>{0: -1, 3: 0});
  });

  test('rapid reversal preserves the current page geometry', () {
    final first = RodinTabHandoff(
      startPage: 0,
      target: 3,
      positions: <int, double>{0: 0},
      direction: 1,
    );
    final positions = first.positionsAt(1.2);
    final reverse = RodinTabHandoff(
      startPage: 1.2,
      target: 0,
      positions: positions,
      direction: -1,
    );
    expect(reverse.positionsAt(1.2), positions);
    expect(reverse.positionsAt(0)[0], 0);
    expect(reverse.positionsAt(0)[3], 1);
  });

  testWidgets('direct handoff skips intermediate builds and preserves state', (
    tester,
  ) async {
    final controller = PageController();
    final key = GlobalKey<RodinRootPagerState>();
    final creations = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinRootPager(
            key: key,
            controller: controller,
            swipeEnabled: true,
            physics: const PageScrollPhysics(),
            onDragStart: () {},
            onPageChanged: (_) {},
            children: <Widget>[
              for (var index = 0; index < 4; index++)
                _Probe(index: index, onCreate: creations.add),
            ],
          ),
        ),
      ),
    );
    expect(creations, <int>[0]);
    key.currentState!.prepareJump(3);
    controller.animateToPage(
      3,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(creations, <int>[0, 3]);
    await tester.pumpAndSettle();
    key.currentState!.finishJump();
    await tester.pump();
    expect(find.text('Page 3'), findsOneWidget);
    key.currentState!.prepareJump(0);
    controller.jumpToPage(0);
    key.currentState!.finishJump();
    await tester.pumpAndSettle();
    expect(creations, <int>[0, 3]);
    expect(find.text('Page 0'), findsOneWidget);
    final scope = find
        .ancestor(
          of: find.text('Page 0'),
          matching: find.byType(RodinMotionViewportScope),
        )
        .first;
    expect(tester.widget<RodinMotionViewportScope>(scope).inFlight, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('swiping pages still uses real PageController fling physics', (
    tester,
  ) async {
    final controller = PageController();
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinRootPager(
            controller: controller,
            swipeEnabled: true,
            physics: const PageScrollPhysics(),
            onDragStart: () => starts++,
            onPageChanged: (_) {},
            children: const <Widget>[
              ColoredBox(color: Colors.red, child: Text('First')),
              ColoredBox(color: Colors.blue, child: Text('Second')),
            ],
          ),
        ),
      ),
    );
    await tester.fling(
      find.byType(RodinRootPager),
      const Offset(-600, 0),
      1200,
    );
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(controller.page, closeTo(1, 0.001));
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a page-owned horizontal slider can disable root swiping', (
    tester,
  ) async {
    final controller = PageController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinRootPager(
            controller: controller,
            swipeEnabled: false,
            physics: const PageScrollPhysics(),
            onDragStart: () => fail('swipe must be disabled'),
            onPageChanged: (_) {},
            children: const <Widget>[Text('First'), Text('Second')],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(RodinRootPager), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('shell rapid A-B-A-C taps settle on the newest tab', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RodinShell()));
    await tester.pump(const Duration(milliseconds: 100));
    final dock = find.byType(RodinBottomBar);
    Future<void> tapTab(String label) async {
      await tester.tap(find.descendant(of: dock, matching: find.text(label)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
    }

    await tapTab('Settings');
    await tapTab('Home');
    await tapTab('Settings');
    await tapTab('Support');
    await tester.pumpAndSettle();
    expect(
      tester.widget<RodinBottomBar>(dock).currentRoot,
      RodinScreen.support,
    );
    expect(find.byType(SupportScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(tester.takeException(), isNull);
    // Tapping the settled tab again must not replay a transition.
    await tapTab('Support');
    await tester.pumpAndSettle();
    expect(
      tester.widget<RodinBottomBar>(dock).currentRoot,
      RodinScreen.support,
    );
    expect(tester.binding.hasScheduledFrame, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dock dragging can interrupt a direct tab handoff', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RodinShell()));
    await tester.pump(const Duration(milliseconds: 100));
    final dock = find.byType(RodinBottomBar);
    await tester.tap(
      find.descendant(of: dock, matching: find.text('Settings')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final home = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Home')),
    );
    final hubs = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Hubs')),
    );
    final gesture = await tester.startGesture(home);
    await gesture.moveTo(hubs);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveTo(hubs + const Offset(2, 0));
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<RodinBottomBar>(dock).currentRoot, RodinScreen.hubs);
    expect(find.byType(HubsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dock stays under a held finger between tabs, then reverses', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RodinShell()));
    await tester.pump(const Duration(milliseconds: 100));
    final dock = find.byType(RodinBottomBar);
    final controller = tester.widget<RodinBottomBar>(dock).controller;
    final home = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Home')),
    );
    final hubs = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Hubs')),
    );
    final gesture = await tester.startGesture(home);
    await gesture.moveTo(home + const Offset(22, 0));
    await tester.pump();
    await gesture.moveTo(Offset.lerp(home, hubs, 0.65)!);
    await tester.pump();
    final heldPage = controller.page!;
    expect(heldPage, closeTo(0.65, 0.04));
    // A first-visit destination must not freeze its card reveal at opacity 0
    // while its parent disables tickers during the finger-owned transition.
    for (final opacity in tester.widgetList<Opacity>(
      find.descendant(
        of: find.byType(HubsScreen),
        matching: find.byType(Opacity),
      ),
    )) {
      expect(opacity.opacity, greaterThan(0.99));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.page, closeTo(heldPage, 0.00001));
    await gesture.moveTo(Offset.lerp(home, hubs, 0.30)!);
    await tester.pump();
    final reversedPage = controller.page!;
    expect(reversedPage, closeTo(0.30, 0.04));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.page, closeTo(reversedPage, 0.00001));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(0, 0.00001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dock clamps edge holds and cancellation settles only once', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RodinShell()));
    await tester.pump(const Duration(milliseconds: 100));
    final dock = find.byType(RodinBottomBar);
    final controller = tester.widget<RodinBottomBar>(dock).controller;
    final home = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Home')),
    );
    final settings = tester.getCenter(
      find.descendant(of: dock, matching: find.text('Settings')),
    );
    final gesture = await tester.startGesture(home);
    await gesture.moveTo(home + const Offset(22, 0));
    await tester.pump();
    await gesture.moveTo(settings + const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.page, closeTo(3, 0.00001));
    await gesture.moveTo(Offset.lerp(home, settings, 0.48)!);
    await tester.pump();
    final heldPage = controller.page!;
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.page, closeTo(heldPage, 0.00001));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(1, 0.00001));
    await tester.tap(find.descendant(of: dock, matching: find.text('Support')));
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(2, 0.00001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced-motion tab taps settle directly without an animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RodinShell(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final dock = find.byType(RodinBottomBar);
    await tester.tap(
      find.descendant(of: dock, matching: find.text('Settings')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<RodinBottomBar>(dock).currentRoot,
      RodinScreen.settings,
    );
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.index, required this.onCreate});
  final int index;
  final ValueChanged<int> onCreate;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate(widget.index);
  }

  @override
  Widget build(BuildContext context) => Text('Page ${widget.index}');
}
