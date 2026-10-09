import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';
import 'package:rodin_essential_ui/page_motion.dart';

void main() {
  testWidgets('header preserves backdrop but blocks covered taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RodinHeaderHitRegion(
            top: 80,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ColoredBox), findsWidgets);
    await tester.tapAt(const Offset(100, 40));
    expect(taps, 0);
    await tester.tapAt(const Offset(100, 140));
    expect(taps, 1);
  });
  testWidgets('restored scroll offset restores the collapsed header', (
    tester,
  ) async {
    final visible = ValueNotifier<bool>(true);
    final bucket = PageStorageBucket();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: bucket,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, shown, child) => shown
                  ? RodinScrollPage(
                      key: const PageStorageKey<String>('remembered-detail'),
                      children: <Widget>[
                        DetailHeader(title: 'Saved page', onBack: () {}),
                        const SizedBox(height: 2400),
                      ],
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(300);
    await tester.pump();
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    await tester.pump();
    final clip = find.byKey(
      const ValueKey<String>('rodin-header-content-clip'),
    );
    expect(tester.widget<RodinHeaderHitRegion>(clip).top, 66);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
  for (final bool slivers in <bool>[false, true]) {
    testWidgets('restore scroll prefetch after motion (slivers=$slivers)', (
      tester,
    ) async {
      final moving = ValueNotifier<bool>(true);
      addTearDown(moving.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: moving,
            child: RodinScrollPage(
              slivers: slivers
                  ? const [SliverToBoxAdapter(child: SizedBox(height: 2000))]
                  : null,
              children: const [SizedBox(height: 2000)],
            ),
            builder: (_, inFlight, child) =>
                RodinMotionViewportScope(inFlight: inFlight, child: child!),
          ),
        ),
      );
      double? cacheExtent() => slivers
          ? tester
                .widget<CustomScrollView>(find.byType(CustomScrollView))
                .scrollCacheExtent
                ?.value
          : tester
                .widget<ListView>(find.byType(ListView))
                .scrollCacheExtent
                ?.value;
      expect(cacheExtent(), 0);
      moving.value = false;
      await tester.pump();
      expect(cacheExtent(), 250);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
    testWidgets('header excludes scrolling content (slivers=$slivers)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RodinScrollPage(
              header: slivers
                  ? DetailHeader(title: 'Per-App Controls', onBack: () {})
                  : null,
              slivers: slivers
                  ? <Widget>[
                      const SliverToBoxAdapter(child: SizedBox(height: 1800)),
                    ]
                  : null,
              children: <Widget>[
                DetailHeader(title: 'Per-App Controls', onBack: () {}),
                const TextField(
                  decoration: InputDecoration(
                    hintText: 'Search installed apps',
                  ),
                ),
                const SizedBox(height: 1800),
              ],
            ),
          ),
        ),
      );
      final Finder clip = find.byKey(
        const ValueKey<String>('rodin-header-content-clip'),
      );
      double clipTop() {
        return tester.widget<RodinHeaderHitRegion>(clip).top;
      }

      expect(clipTop(), 78); // Fallback inset 24 + expanded header 54.
      final ScrollableState scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      for (final double offset in <double>[20, 58, 300, 600]) {
        scroll.position.jumpTo(offset);
        await tester.pump();
        expect(clipTop(), greaterThanOrEqualTo(66));
        if (offset >= 58) expect(clipTop(), 66);
        expect(find.text('Per-App Controls'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      scroll.position.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(clipTop(), 78);
    });
  }
}
