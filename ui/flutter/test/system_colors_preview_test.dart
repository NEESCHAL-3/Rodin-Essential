import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/system_colors_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background preview matches Material colors in every style', () async {
    final RodinPalettePreviewWorker worker = RodinPalettePreviewWorker();
    addTearDown(worker.dispose);
    const List<DynamicSchemeVariant> variants = <DynamicSchemeVariant>[
      DynamicSchemeVariant.tonalSpot,
      DynamicSchemeVariant.vibrant,
      DynamicSchemeVariant.expressive,
      DynamicSchemeVariant.neutral,
      DynamicSchemeVariant.rainbow,
      DynamicSchemeVariant.fruitSalad,
      DynamicSchemeVariant.monochrome,
    ];
    for (final bool dark in <bool>[false, true]) {
      for (int style = 0; style < variants.length; style++) {
        final List<int> colors = await worker.generate((0x7655ca, style, dark));
        final List<List<int>> families = rodinPreviewTonalFamilies(colors);
        expect(colors, hasLength(77));
        expect(families, hasLength(5));
        for (final List<int> family in families) {
          expect(family, hasLength(13));
          expect(family.first, 0xff000000);
          expect(family.last, 0xffffffff);
        }
        final ColorScheme preview = rodinPreviewScheme(colors, dark);
        final ColorScheme expected = ColorScheme.fromSeed(
          seedColor: const Color(0xff7655ca),
          brightness: dark ? Brightness.dark : Brightness.light,
          dynamicSchemeVariant: variants[style],
        );
        expect(preview.primary, expected.primary);
        expect(preview.onPrimary, expected.onPrimary);
        expect(preview.primaryContainer, expected.primaryContainer);
        expect(preview.onPrimaryContainer, expected.onPrimaryContainer);
        expect(preview.secondaryContainer, expected.secondaryContainer);
        expect(preview.onSecondaryContainer, expected.onSecondaryContainer);
        expect(preview.tertiaryContainer, expected.tertiaryContainer);
        expect(preview.onTertiaryContainer, expected.onTertiaryContainer);
        expect(preview.surfaceContainerLow, expected.surfaceContainerLow);
        expect(
          preview.surfaceContainerHighest,
          expected.surfaceContainerHighest,
        );
        expect(preview.outlineVariant, expected.outlineVariant);
        expect(preview.onSurface, expected.onSurface);
      }
    }
  });

  test(
    'closing a preview completes pending work without leaving an isolate',
    () async {
      final RodinPalettePreviewWorker worker = RodinPalettePreviewWorker();
      final Future<void> pending = expectLater(
        worker.generate((0x008577, 0, false)),
        throwsStateError,
      );
      worker.dispose();
      await pending;
      await expectLater(worker.generate((0, 0, false)), throwsStateError);
      worker.dispose();
    },
  );

  test('one failed preview request does not poison the worker', () async {
    final RodinPalettePreviewWorker worker = RodinPalettePreviewWorker();
    addTearDown(worker.dispose);
    await expectLater(worker.generate((0, 20, false)), throwsStateError);
    expect(await worker.generate((0x008577, 0, false)), hasLength(77));
  });
}
