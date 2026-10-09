import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  for (final Brightness brightness in Brightness.values) {
    testWidgets('community descriptions wrap at large text ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const Scaffold(body: SupportScreen()),
        ),
      );
      for (final description in <String>[
        'Star, fork, and inspect the open-source code',
        'Join device discussions, chat & get instant support',
      ]) {
        final finder = find.text(description);
        await tester.scrollUntilVisible(finder, 150);
        await tester.pumpAndSettle();
        final text = tester.widget<Text>(finder);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.softWrap, isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
