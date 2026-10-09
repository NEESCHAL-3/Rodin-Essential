import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';
import 'package:rodin_essential_ui/page_motion.dart';

void main() {
  test('scroll momentum and spring are bounded', () {
    const physics = RodinScrollPhysics();
    expect(physics.maxFlingVelocity, 6500);
    expect(physics.carriedMomentum(20000), lessThanOrEqualTo(3500));
    expect(physics.carriedMomentum(-20000), greaterThanOrEqualTo(-3500));
    expect(physics.spring.mass, 0.65);
    expect(const RodinSpringCurve().transform(0), 0);
    expect(const RodinSpringCurve().transform(1), 1);
  });
  for (final brightness in Brightness.values) {
    testWidgets('new Home fits small screens and larger type ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: HomeScreen(onOpen: (_) {}, onHubs: () {}, onSupport: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('8400-Ultra'), findsNothing);
      expect(find.text('GPU PROFILE'), findsNothing);
      expect(find.text('DEVICE PULSE'), findsOneWidget);
      final error = tester.takeException();
      expect(
        error,
        isNull,
        reason: error is FlutterError
            ? error.diagnostics.map((item) => item.toStringDeep()).join('\n')
            : null,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('inertia layer returns to rest without rebuilding its content', (
    tester,
  ) async {
    final velocity = ValueNotifier<double>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: RodinScrollMotionScope(
          velocity: velocity,
          child: const RodinInertiaLayer(
            child: SizedBox(width: 200, height: 100),
          ),
        ),
      ),
    );
    velocity.value = 4000;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    velocity.value = 0;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    velocity.dispose();
  });
}
