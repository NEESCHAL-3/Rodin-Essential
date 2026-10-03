import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/service_confirmation.dart';

void main() {
  for (final bool reset in <bool>[false, true]) {
    for (final bool confirm in <bool>[false, true]) {
      testWidgets(
        '${reset ? "reset" : "disable"}: ${confirm ? "confirm" : "cancel"}',
        (tester) async {
          bool? result;
          int confirmHaptics = 0;
          int cancelHaptics = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      result = await showDialog<bool>(
                        context: context,
                        builder: (_) => RodinServiceConfirmation(
                          reset: reset,
                          cornerRadius: 16,
                          accent: const Color(0xFF35C997),
                          onConfirmHaptic: () => confirmHaptics++,
                          onCancelHaptic: () => cancelHaptics++,
                          surfaceBuilder: (child) => Material(
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final FilledButton actionButton = tester.widget(
            find.byType(FilledButton),
          );
          expect(
            actionButton.style!.backgroundColor!.resolve(<WidgetState>{}),
            const Color(0xFF35C997),
          );
          expect(
            find.textContaining('captured original values'),
            findsOneWidget,
          );
          await tester.ensureVisible(
            find.text(
              confirm
                  ? reset
                        ? 'Reset all settings'
                        : 'Disable Rodin Essential'
                  : 'Cancel',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(
              confirm
                  ? reset
                        ? 'Reset all settings'
                        : 'Disable Rodin Essential'
                  : 'Cancel',
            ),
          );
          await tester.pumpAndSettle();
          expect(result, confirm);
          expect(confirmHaptics, confirm ? 1 : 0);
          expect(cancelHaptics, confirm ? 0 : 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('small screen and large text stay scrollable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: RodinServiceConfirmation(
            reset: true,
            cornerRadius: 16,
            accent: const Color(0xFF35C997),
            surfaceBuilder: (child) => Material(
              child: Padding(padding: const EdgeInsets.all(22), child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    expect(tester.takeException(), isNull);
  });
}
