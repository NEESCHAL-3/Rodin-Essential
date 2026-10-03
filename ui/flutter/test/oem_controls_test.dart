import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets('hero keeps full descriptions at narrow width', (tester) async {
    const description =
        'Rodin Essential override released · ROM-managed timing · Goodix GT9916 · Vendor HAL ready';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: HeroCard(
              icon: Icons.auto_awesome_rounded,
              accent: Colors.blue,
              title: 'OEM Control',
              subtitle: description,
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(description),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch offers OEM without removing fixed modes', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TouchBoostScreen(onBack: () {})),
      ),
    );
    await tester.pump();
    expect(find.text('OEM Control'), findsNWidgets(2));
    expect(find.text('Default · No fixed-rate override'), findsOneWidget);
    expect(find.text('250 Hz'), findsOneWidget);
    expect(find.text('500 Hz'), findsOneWidget);
    expect(find.text('1000 Hz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
