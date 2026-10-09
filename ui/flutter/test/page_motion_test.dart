import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/page_motion.dart';

void main() {
  testWidgets('Back moves immediately and reveals a solid destination', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
      value: 1,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RodinDetailTransition(
          animation: controller,
          forward: false,
          active: false,
          child: const SizedBox.expand(child: Text('Departing page')),
        ),
      ),
    );
    controller.reverse();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final translation = tester
        .widget<FractionalTranslation>(
          find.descendant(
            of: find.byType(RodinDetailTransition),
            matching: find.byType(FractionalTranslation),
          ),
        )
        .translation;
    expect(translation.dx, greaterThan(0.3));
    expect(translation.dx, lessThan(0.6));
    expect(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested Back keeps the departing surface above its destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: rodinDetailLayout(
          const ColoredBox(key: ValueKey('destination'), color: Colors.blue),
          const <Widget>[
            ColoredBox(key: ValueKey('departing'), color: Colors.red),
          ],
          forward: false,
        ),
      ),
    );
    final stack = tester.widget<Stack>(
      find
          .descendant(
            of: find.byType(ClipRect).first,
            matching: find.byType(Stack),
          )
          .first,
    );
    expect(stack.children.first.key, const ValueKey('destination'));
    expect(stack.children.last.key, const ValueKey('departing'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation reveal closes on Back without leaving its page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRodinDialog<void>(
                context: context,
                builder: (_) => const Dialog(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Confirm action'),
                  ),
                ),
              ),
              child: const Text('Open confirmation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open confirmation'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm action'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Confirm action'), findsNothing);
    expect(find.text('Open confirmation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('detail motion preserves size and blocks outgoing taps', (
    tester,
  ) async {
    int taps = 0;
    Widget page(bool active, double value, {bool reduced = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: RodinDetailTransition(
              animation: AlwaysStoppedAnimation(value),
              active: active,
              child: GestureDetector(
                onTap: () => taps++,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        );
    await tester.pumpWidget(page(true, 0.5));
    expect(find.byType(ScaleTransition), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
    await tester.pumpWidget(page(false, 0.5));
    await tester.tapAt(const Offset(400, 300));
    expect(taps, 1);
    expect(
      tester.widget<TickerMode>(find.byType(TickerMode).last).enabled,
      false,
    );
    await tester.pumpWidget(page(true, 0, reduced: true));
    expect(
      find.descendant(
        of: find.byType(RodinDetailTransition),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<FractionalTranslation>(
            find.descendant(
              of: find.byType(RodinDetailTransition),
              matching: find.byType(FractionalTranslation),
            ),
          )
          .translation,
      Offset.zero,
    );
  });

  testWidgets('solid depth motion mirrors its travel in RTL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: RodinDetailTransition(
            animation: AlwaysStoppedAnimation(0),
            active: true,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FractionalTranslation>(
            find.descendant(
              of: find.byType(RodinDetailTransition),
              matching: find.byType(FractionalTranslation),
            ),
          )
          .translation
          .dx,
      -1,
    );
  });
}
