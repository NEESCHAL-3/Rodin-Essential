import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/touch_light.dart';
import 'package:rodin_essential_ui/main.dart';

RodinTouchLightPainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.foregroundPainter)
    .whereType<RodinTouchLightPainter>()
    .single;

void main() {
  Widget surface(Widget child, {bool reduced = false, bool enabled = true}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: RodinTouchLight(
              accent: Colors.cyan,
              enabled: enabled,
              child: SizedBox(width: 240, height: 100, child: child),
            ),
          ),
        ),
      );

  testWidgets('light follows a held pointer without rebuilding the content', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      surface(
        Builder(
          builder: (_) {
            builds++;
            return const Text('Stable control');
          },
        ),
      ),
    );
    final box = tester.getRect(find.byType(RodinTouchLight));
    final gesture = await tester.startGesture(
      box.topLeft + const Offset(20, 40),
    );
    expect(painter(tester).strength.value, greaterThan(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter(tester).strength.value, 1);
    await gesture.moveTo(box.topLeft + const Offset(160, 40));
    await tester.pump();
    expect(painter(tester).point.value, const Offset(160, 40));
    expect(builds, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, false);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(painter(tester).strength.value, 0);
    expect(builds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light does not intercept taps, and cancellation clears it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      surface(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const Text('Tap'),
        ),
      ),
    );
    await tester.tap(find.byType(RodinTouchLight));
    await tester.pumpAndSettle();
    expect(taps, 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RodinTouchLight)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(painter(tester).strength.value, 0);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses instantaneous static touch feedback', (
    tester,
  ) async {
    await tester.pumpWidget(surface(const Text('Ready'), reduced: true));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RodinTouchLight)),
    );
    await tester.pump();
    expect(painter(tester).strength.value, 1);
    await gesture.up();
    await tester.pump();
    expect(painter(tester).strength.value, 0);
    expect(tester.binding.hasScheduledFrame, false);
  });

  testWidgets(
    'pointer exit releases the light and disabled surfaces allocate none',
    (tester) async {
      await tester.pumpWidget(surface(const Text('Ready')));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(RodinTouchLight)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(painter(tester).strength.value, 0);
      await gesture.up();
      await tester.pumpWidget(surface(const Text('Ready'), enabled: false));
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where(
              (widget) => widget.foregroundPainter is RodinTouchLightPainter,
            ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scroll cancellation releases card light without triggering a tap',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                PressScale(
                  onTap: () => taps++,
                  child: const SizedBox(height: 120, child: Text('Card')),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(200, 80));
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(painter(tester).strength.value, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
