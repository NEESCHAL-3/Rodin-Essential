import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/bypass_threshold_selector.dart';

void main() {
  Widget page({
    required ValueChanged<int> commit,
    ValueChanged<int>? preview,
    bool enabled = true,
    double scale = 1,
    Brightness brightness = Brightness.dark,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Center(
          child: SizedBox(
            width: 300,
            child: RodinBypassThresholdSelector(
              value: 20,
              enabled: enabled,
              onChanged: commit,
              onPreview: preview,
              accent: const Color(0xFF9B7CFF),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('drag previews without submitting until release', (tester) async {
    final commits = <int>[];
    final previews = <int>[];
    await tester.pumpWidget(page(commit: commits.add, preview: previews.add));
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await drag.moveBy(const Offset(85, 0));
    await tester.pump();
    expect(commits, isEmpty);
    expect(previews, isNotEmpty);
    final value = tester.widget<Slider>(find.byType(Slider)).value;
    // A periodic telemetry rebuild must not reset an in-progress drag.
    await tester.pumpWidget(page(commit: commits.add, preview: previews.add));
    expect(tester.widget<Slider>(find.byType(Slider)).value, value);
    await drag.up();
    await tester.pump();
    expect(commits.length, 1);
    expect(<int>[0, 20, 40, 80, 90], contains(commits.single));
  });

  testWidgets('unsupported or busy slider cannot submit changes', (
    tester,
  ) async {
    final commits = <int>[];
    await tester.pumpWidget(page(commit: commits.add, enabled: false));
    await tester.tap(find.byType(Slider));
    expect(commits, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets('large labels fit in $brightness', (tester) async {
      await tester.pumpWidget(
        page(commit: (_) {}, scale: 1.8, brightness: brightness),
      );
      for (final label in <String>['Now', '20%', '40%', '80%', '90%']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
