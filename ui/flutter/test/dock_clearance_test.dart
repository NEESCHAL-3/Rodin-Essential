import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  for (final double inset in <double>[0, 24, 48]) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('dock clearance: $inset, $brightness', (tester) async {
        final controller = PageController();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: MediaQueryData(
                padding: EdgeInsets.only(bottom: inset),
                viewPadding: EdgeInsets.only(bottom: inset),
              ),
              child: Scaffold(
                bottomNavigationBar: RodinBottomBar(
                  controller: controller,
                  currentRoot: RodinScreen.home,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        final dock = tester.getRect(find.byType(BackdropFilter));
        final screen =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(
          screen - dock.bottom,
          closeTo((inset > 0 ? inset : 16) + 12, 0.01),
        );
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Hubs'), findsOneWidget);
        expect(find.text('Support'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }
}
