import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/bottom_feedback.dart';

const message = 'Applied Gaming Dynamic · Full Range (260–1300 MHz)';

Widget harness({
  double inset = 0,
  double scale = 1,
  bool visible = true,
  Brightness brightness = Brightness.dark,
  bool reduced = false,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 640),
      viewPadding: EdgeInsets.only(bottom: inset),
      padding: EdgeInsets.only(bottom: inset),
      textScaler: TextScaler.linear(scale),
      disableAnimations: reduced,
    ),
    child: Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Colors.black),
          Positioned(
            key: const ValueKey('dock'),
            bottom:
                RodinBottomLayout.navigationClearance(context) +
                RodinBottomLayout.dockGap,
            left: 10,
            right: 10,
            height: RodinBottomLayout.dockHeight,
            child: const ColoredBox(color: Colors.grey),
          ),
          RodinFeedbackOverlay(
            tag: 'GPU PRESET',
            message: message,
            icon: Icons.sports_esports_rounded,
            accent: Colors.amber,
            visible: visible,
          ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final inset in <double>[0, 24, 48]) {
    for (final brightness in Brightness.values) {
      testWidgets('feedback clears dock: inset $inset, $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          harness(inset: inset, scale: 1.6, brightness: brightness),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byType(RodinFeedbackCard));
        final dock = tester.getRect(find.byKey(const ValueKey('dock')));
        expect(card.bottom, lessThanOrEqualTo(dock.top - 12));
        expect(card.top, greaterThan(0));
        final text = tester.widget<Text>(find.text(message));
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('feedback fades out and does not intercept input', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpWidget(harness(visible: false));
    await tester.pump(const Duration(milliseconds: 100));
    final fading = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(RodinFeedbackOverlay),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fading.opacity.value, greaterThan(0));
    expect(fading.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byType(RodinFeedbackOverlay),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isTrue,
    );
  });

  testWidgets('reduced motion disables slide and fade', (tester) async {
    await tester.pumpWidget(harness(reduced: true));
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
      Duration.zero,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).duration,
      Duration.zero,
    );
  });
}
