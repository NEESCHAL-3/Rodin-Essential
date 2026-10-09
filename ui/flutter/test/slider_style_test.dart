import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/slider_style.dart';

void main() {
  const accent = Color(0xFF4CAADD);
  final style = rodinSliderTheme(accent: accent, outline: Colors.grey);

  test('single and range sliders share the compact drop indicator', () {
    expect(style.valueIndicatorShape, isA<DropSliderValueIndicatorShape>());
    expect(
      style.rangeValueIndicatorShape,
      isA<DropRangeSliderValueIndicatorShape>(),
    );
    expect(style.valueIndicatorColor, accent);
    final label = TextPainter(
      text: const TextSpan(text: '1.7 GHz', style: TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(
      (style.valueIndicatorShape! as DropSliderValueIndicatorShape)
          .getPreferredSize(
            true,
            true,
            labelPainter: label,
            textScaleFactor: 1,
          ),
      (style.rangeValueIndicatorShape! as DropRangeSliderValueIndicatorShape)
          .getPreferredSize(
            true,
            true,
            labelPainter: label,
            textScaleFactor: 1,
          ),
    );
    label.dispose();
  });

  for (final brightness in Brightness.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'range drag and exact lock stay usable: $brightness $direction',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var exact = 8.0;
          var range = const RangeValues(2, 15);
          var changes = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness, sliderTheme: style),
              home: Directionality(
                textDirection: direction,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: Scaffold(
                    body: StatefulBuilder(
                      builder: (context, update) => Column(
                        children: [
                          const SizedBox(height: 100),
                          RangeSlider(
                            values: range,
                            max: 18,
                            divisions: 18,
                            activeColor: accent,
                            labels: RangeLabels(
                              '${range.start.round()} MHz',
                              '${range.end.round()} MHz',
                            ),
                            onChanged: (next) => update(() {
                              range = next;
                              changes++;
                            }),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(
                              context,
                            ).copyWith(valueIndicatorColor: Colors.purple),
                            child: Slider(
                              value: exact,
                              max: 18,
                              divisions: 18,
                              label: '${exact.round()} MHz',
                              onChanged: (next) => update(() {
                                exact = next;
                                changes++;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (final slider in [
            find.byType(RangeSlider),
            find.byType(Slider),
          ]) {
            final rect = tester.getRect(slider);
            final gesture = await tester.startGesture(
              Offset(rect.left + rect.width * 0.45, rect.center.dy),
            );
            await tester.pump(const Duration(milliseconds: 200));
            await gesture.moveBy(const Offset(35, 0));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
            await gesture.up();
            await tester.pumpAndSettle();
          }
          expect(changes, greaterThan(1));
          final inherited = SliderTheme.of(tester.element(find.byType(Slider)));
          expect(inherited.valueIndicatorColor, Colors.purple);
          expect(
            inherited.rangeValueIndicatorShape,
            isA<DropRangeSliderValueIndicatorShape>(),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
