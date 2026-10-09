import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets(
    'holding R arms the game; release opens it; pause and back work',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RodinVersionSecret(version: 'v1.18.5')),
        ),
      );
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('v1.18.5'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final logo = find.byKey(const ValueKey('secret-logo'));
      final gesture = await tester.startGesture(tester.getCenter(logo));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Release to drift.'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Aurora Drift'), findsOneWidget);
      await tester.tap(find.text('Let’s drift'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Pause game'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(RodinNestedBackController.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Aurora Drift'), findsNothing);
      RodinNestedBackController.handleBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'secret room fits narrow screens with large text and reduced motion ($brightness)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: const Scaffold(body: RodinVersionSecret(version: 'v1.18.4')),
          ),
        );
        for (int i = 0; i < 4; i++) {
          await tester.tap(find.text('v1.18.4'));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.text('The secret room'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Play Aurora Drift'));
        await tester.tap(find.text('Play Aurora Drift'));
        await tester.pumpAndSettle();
        expect(find.text('Aurora Drift'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(RodinNestedBackController.handleBack(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Aurora Drift'), findsNothing);
        await tester.ensureVisible(find.text('One more joke'));
        await tester.tap(find.text('One more joke'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        RodinNestedBackController.handleBack();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('four version taps reveal user jokes, not three', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RodinVersionSecret(version: 'v1.18.4')),
      ),
    );
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('v1.18.4'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RodinSecretRoom), findsNothing);
    await tester.tap(find.text('v1.18.4'));
    await tester.pumpAndSettle();
    expect(find.text('Four taps. Zero secret overclock.'), findsOneWidget);
    await tester.tap(find.text('One more joke'));
    await tester.pumpAndSettle();
    expect(
      find.text('I asked the GPU for a sandwich. It rendered the bread.'),
      findsOneWidget,
    );
    expect(RodinNestedBackController.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(RodinSecretRoom), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slow taps reset the secret sequence', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RodinVersionSecret(version: 'v1.18.4')),
      ),
    );
    await tester.tap(find.text('v1.18.4'));
    await tester.pump(const Duration(seconds: 3));
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('v1.18.4'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RodinSecretRoom), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
