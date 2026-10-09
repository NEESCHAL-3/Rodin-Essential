import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets('tile preferences focuses bypass on cold and repeated opens', (
    tester,
  ) async {
    Widget screen(int request) => MaterialApp(
      home: Scaffold(
        body: ChargingScreen(onBack: () {}, focusRequest: request),
      ),
    );
    await tester.pumpWidget(screen(1));
    await tester.pumpAndSettle();
    final bypass = find.text('Bypass Charging');
    expect(bypass, findsOneWidget);
    final first = tester.getRect(bypass);
    expect(first.top, greaterThan(0));
    expect(first.bottom, lessThan(500));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pumpWidget(screen(2));
    await tester.pumpAndSettle();
    expect(tester.getRect(bypass).top, closeTo(first.top, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
