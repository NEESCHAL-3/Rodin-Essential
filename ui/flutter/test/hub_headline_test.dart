import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/hub_headline.dart';
import 'package:rodin_essential_ui/page_motion.dart';

void main() {
  Widget page({
    bool hidden = false,
    bool moving = false,
    bool reduced = false,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduced,
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            child: TickerMode(
              enabled: !hidden,
              child: RodinMotionViewportScope(
                inFlight: moving,
                child: const HubHeadline(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  String title(WidgetTester tester) => tester
      .widget<RichText>(
        find
            .descendant(
              of: find.byType(HubHeadline),
              matching: find.byType(RichText),
            )
            .first,
      )
      .text
      .toPlainText();

  testWidgets('all twelve headlines rotate without changing the card height', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    final height = tester.getSize(find.byType(HubHeadline)).height;
    for (final copy in hubHeadlines) {
      expect(title(tester), '${copy.lead}\n${copy.emphasis}');
      expect(find.text(copy.description), findsOneWidget);
      expect(tester.getSize(find.byType(HubHeadline)).height, height);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      // Text swaps only at zero opacity, never two layers of lettering.
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(0, 0.00001),
      );
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, false);
    }
    expect(title(tester), 'Control\nbeyond cores.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hidden, moving, background and reduced-motion states pause rotation',
    (tester) async {
      for (final config in [
        page(hidden: true),
        page(moving: true),
        page(reduced: true),
      ]) {
        await tester.pumpWidget(config);
        final before = title(tester);
        await tester.pump(const Duration(seconds: 30));
        expect(title(tester), before);
        expect(tester.binding.hasScheduledFrame, false);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.pumpWidget(page());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 30));
      expect(title(tester), 'Control\nbeyond cores.');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(title(tester), 'Go\nbeyond defaults.');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('scrolling the hero offscreen pauses it and retains its phrase', (
    tester,
  ) async {
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: const Column(
              children: [HubHeadline(), SizedBox(height: 1800)],
            ),
          ),
        ),
      ),
    );
    final before = title(tester);
    scroll.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(title(tester), before);
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(title(tester), 'Go\nbeyond defaults.');
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets(
    'large text fits in both themes and emphasis has readable contrast',
    (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(page(brightness: brightness, scale: 1.5));
        for (final copy in hubHeadlines) {
          final accent = brightness == Brightness.dark ? copy.dark : copy.light;
          final surface = brightness == Brightness.dark
              ? const Color(0xFF121212)
              : Colors.white;
          final light = accent.computeLuminance(),
              base = surface.computeLuminance();
          final contrast =
              (light > base ? light + 0.05 : base + 0.05) /
              (light > base ? base + 0.05 : light + 0.05);
          expect(contrast, greaterThanOrEqualTo(3), reason: copy.emphasis);
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
