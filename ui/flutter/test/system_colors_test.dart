import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/backend_connection.dart';
import 'package:rodin_essential_ui/backend/system_colors_state.dart';
import 'package:rodin_essential_ui/main.dart';

RodinSystemColorsState nativePalette({
  int operationState = 2,
  bool supported = true,
  int mode = 0,
  int seed = -1,
  int style = 0,
  int sdk = 36,
  int outcome = 0,
  int revision = 1,
  int error = 0,
}) => RodinSystemColorsState(
  operationState: operationState,
  supported: supported,
  mode: mode,
  seed: seed,
  style: style,
  primary: 0x112233,
  secondary: 0x445566,
  tertiary: 0x778899,
  neutral: 0x888888,
  neutralVariant: 0x999999,
  sdk: sdk,
  user: 0,
  outcome: outcome,
  error: error,
  revision: revision,
);

Future<void> showPanel(
  WidgetTester tester, {
  RodinSystemColorsState? palette,
  bool online = true,
  RodinConnectionState? connection,
  double width = 390,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool Function(bool, int, int)? onApply,
  bool Function()? onRefresh,
  VoidCallback? onSelectionFeedback,
  bool Function()? isNativeBusy,
  RodinSystemColorsSelection? selection,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1100),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SystemColorsPanel(
              palette: palette ?? nativePalette(),
              connection:
                  connection ??
                  (online
                      ? RodinConnectionState.online
                      : RodinConnectionState.offline),
              onApply: onApply ?? (_, _, _) => false,
              onRefresh: onRefresh ?? () => true,
              onSelectionFeedback: onSelectionFeedback ?? () {},
              isNativeBusy: isNativeBusy,
              selection: selection,
              previewBuilder: (seed, style, dark, scrubbing) =>
                  const SizedBox(height: 225),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> tapText(WidgetTester tester, String label) async {
  final Finder target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  test('cache mapping keeps unknown values separate from native colors', () {
    const RodinSystemColorsState empty = RodinSystemColorsState();
    expect(empty.hasReadback, isFalse);
    expect(empty.ready, isFalse);
    final RodinSystemColorsState decoded = RodinSystemColorsState.fromNative(
      (int index) =>
          <int, int>{
            81: 2,
            82: 1,
            83: 0x008577,
            84: 2,
            85: 1,
            86: 2,
            87: 3,
            88: 4,
            89: 5,
            90: 37,
            91: 10,
            92: 1,
            93: 0,
            94: 9,
            95: 1,
          }[index] ??
          -1,
    );
    expect(decoded.nativeColors, <int>[1, 2, 3, 4, 5]);
    expect(decoded.hasReadback, isTrue);
    expect(decoded.supported, isTrue);
    expect(decoded.seed, 0x008577);
    expect(decoded.user, 10);
    expect(decoded.revision, 9);
  });

  testWidgets('choices apply on tap and rapid edits coalesce to the latest', (
    WidgetTester tester,
  ) async {
    final List<(bool, int, int)> writes = <(bool, int, int)>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add((wallpaper, seed, style));
      return true;
    }

    await showPanel(tester, onApply: record);
    await tapText(tester, 'Custom color');
    expect(writes, <(bool, int, int)>[(false, 0x008577, 0)]);
    expect(find.byKey(const ValueKey<String>('palette-apply')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('palette-seed-Iris')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('palette-seed-Iris')));
    await tester.pump(const Duration(milliseconds: 350));
    await tapText(tester, 'Vibrant');
    expect(writes, hasLength(1));
    final Container swatch = tester.widget<Container>(
      find.byKey(const ValueKey<String>('palette-native-0')),
    );
    expect(
      (swatch.decoration! as BoxDecoration).color,
      const Color(0xff112233),
    );
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577, outcome: 1, revision: 2),
      onApply: record,
    );
    expect(writes, <(bool, int, int)>[
      (false, 0x008577, 0),
      (false, 0x7655ca, 1),
    ]);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Vibrant'))
          .selected,
      isTrue,
    );
    await showPanel(
      tester,
      palette: nativePalette(
        mode: 1,
        seed: 0x7655ca,
        style: 1,
        outcome: 1,
        revision: 3,
      ),
      onApply: record,
    );
    expect(writes, hasLength(2));
    expect(find.textContaining('System colors updated'), findsOneWidget);
  });

  testWidgets('completion is not missed after observing a busy revision', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add(seed);
      return true;
    }

    await showPanel(tester, onApply: record);
    await tapText(tester, 'Custom color');
    await tapText(tester, 'Ocean');
    expect(writes, <int>[0x008577]);
    await showPanel(
      tester,
      palette: nativePalette(operationState: 1, revision: 2),
      onApply: record,
    );
    expect(writes, hasLength(1));
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577, revision: 2),
      onApply: record,
    );
    expect(writes, <int>[0x008577, 0x386bd5]);
  });

  testWidgets('offline and unsupported states never enable writes', (
    WidgetTester tester,
  ) async {
    final List<bool> writes = <bool>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add(wallpaper);
      return true;
    }

    await showPanel(
      tester,
      online: false,
      palette: const RodinSystemColorsState(),
      onApply: record,
    );
    await tapText(tester, 'Custom color');
    expect(find.textContaining('Preview only'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('palette-native-0')),
      findsNothing,
    );
    expect(writes, isEmpty);
    await showPanel(
      tester,
      palette: nativePalette(supported: false),
      onApply: record,
    );
    expect(find.textContaining('does not expose Android’s native'), findsOneWidget);
    await tapText(tester, 'Vibrant');
    expect(writes, isEmpty);
  });

  testWidgets(
    'one seed tap submits without another frame and without a late vibration',
    (tester) async {
      int feedback = 0;
      final List<int> writes = <int>[];
      bool record(bool wallpaper, int seed, int style) {
        writes.add(seed);
        return true;
      }

      await showPanel(
        tester,
        palette: nativePalette(mode: 1, seed: 0x008577),
        onApply: record,
        onSelectionFeedback: () => feedback++,
      );
      final Finder seed = find.byKey(
        const ValueKey<String>('palette-seed-Iris'),
      );
      await tester.ensureVisible(seed);
      await tester.tap(seed);
      expect(feedback, 1);
      expect(writes, <int>[
        0x7655ca,
      ], reason: 'no second rendering frame or tap is needed');
      await tester.pump();
      expect(
        find.descendant(of: seed, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
      expect(writes, <int>[0x7655ca]);
      final PressScale press = tester.widget<PressScale>(
        find.ancestor(of: seed, matching: find.byType(PressScale)).first,
      );
      expect(
        press.enableHaptics,
        isFalse,
        reason: 'only one gesture owns feedback',
      );
      await showPanel(
        tester,
        palette: nativePalette(
          mode: 1,
          seed: 0x7655ca,
          outcome: 1,
          revision: 2,
        ),
        onApply: record,
        onSelectionFeedback: () => feedback++,
      );
      expect(feedback, 1, reason: 'asynchronous success must not vibrate');
      expect(writes, hasLength(1));
    },
  );

  testWidgets('Android 12 exposes only its supported style', (
    WidgetTester tester,
  ) async {
    await showPanel(tester, palette: nativePalette(sdk: 31));
    await tapText(tester, 'Custom color');
    expect(find.widgetWithText(ChoiceChip, 'Tonal'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Vibrant'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Monochrome'), findsNothing);
  });

  testWidgets(
    'a selection during initial discovery is applied after the read',
    (tester) async {
      final List<int> writes = <int>[];
      bool record(bool wallpaper, int seed, int style) {
        writes.add(seed);
        return true;
      }

      await showPanel(
        tester,
        palette: const RodinSystemColorsState(operationState: 1),
        onApply: record,
      );
      await tapText(tester, 'Custom color');
      final Finder iris = find.byKey(
        const ValueKey<String>('palette-seed-Iris'),
      );
      await tester.ensureVisible(iris);
      await tester.tap(iris);
      await tester.pump();
      expect(writes, isEmpty);
      await showPanel(tester, palette: nativePalette(), onApply: record);
      expect(writes, <int>[0x7655ca]);
    },
  );

  testWidgets('a native refresh ahead of the UI snapshot does not lose a tap', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    bool nativeBusy = true;
    bool record(bool wallpaper, int seed, int style) {
      writes.add(seed);
      return true;
    }

    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577),
      onApply: record,
      isNativeBusy: () => nativeBusy,
    );
    final Finder iris = find.byKey(const ValueKey<String>('palette-seed-Iris'));
    await tester.ensureVisible(iris);
    await tester.tap(iris);
    await tester.pump();
    expect(writes, isEmpty);
    nativeBusy = false;
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577, revision: 2),
      onApply: record,
      isNativeBusy: () => nativeBusy,
    );
    expect(writes, <int>[0x7655ca]);
  });

  testWidgets('cached custom choice is visible during a cold-start read', (
    tester,
  ) async {
    await showPanel(
      tester,
      palette: const RodinSystemColorsState(operationState: 1),
      selection: const RodinSystemColorsSelection(
        wallpaper: false,
        seed: 0xad477b,
        style: 2,
      ),
    );
    expect(find.text('Seed color'), findsOneWidget);
    final Finder rose = find.byKey(const ValueKey<String>('palette-seed-Rose'));
    expect(
      find.descendant(of: rose, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Expressive'))
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey<String>('palette-native-0')),
      findsNothing,
    );
  });

  testWidgets('an unknown source is never shown as selected Wallpaper', (
    tester,
  ) async {
    await showPanel(
      tester,
      palette: const RodinSystemColorsState(operationState: 1),
    );
    expect(find.textContaining('No source is selected yet'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  test('only valid confirmed choices can be restored from the UI cache', () {
    const RodinSystemColorsSelection choice = RodinSystemColorsSelection(
      wallpaper: false,
      seed: 0xad477b,
      style: 2,
    );
    expect(RodinSystemColorsSelection.fromJson(choice.toJson()), choice);
    expect(
      RodinSystemColorsSelection.fromNative(const RodinSystemColorsState()),
      isNull,
    );
    for (final Object? invalid in <Object?>[
      null,
      <String, Object>{},
      <String, Object>{...choice.toJson(), 'seed': -1},
      <String, Object>{...choice.toJson(), 'style': 7},
      <String, Object>{...choice.toJson(), 'wallpaper': 'false'},
    ]) {
      expect(RodinSystemColorsSelection.fromJson(invalid), isNull);
    }
  });

  testWidgets(
    'wallpaper selection resets immediately without an Apply button',
    (WidgetTester tester) async {
      final List<bool> writes = <bool>[];
      await showPanel(
        tester,
        palette: nativePalette(mode: 1, seed: 0x008577),
        onApply: (bool wallpaper, _, _) {
          writes.add(wallpaper);
          return true;
        },
      );
      await tapText(tester, 'Wallpaper');
      expect(writes, <bool>[true]);
      expect(find.byKey(const ValueKey<String>('palette-apply')), findsNothing);
    },
  );

  testWidgets('unchanged wallpaper output is described without a false change', (
    WidgetTester tester,
  ) async {
    await showPanel(tester, onApply: (_, _, _) => true);
    await tapText(tester, 'Custom color');
    await showPanel(
      tester,
      palette: nativePalette(mode: 0, outcome: 2, revision: 2),
    );
    expect(
      find.textContaining('Wallpaper following restored'),
      findsOneWidget,
    );
    expect(find.textContaining('System colors updated'), findsNothing);
  });

  testWidgets('reconnecting does not silently apply an offline preview', (
    WidgetTester tester,
  ) async {
    final List<bool> writes = <bool>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add(wallpaper);
      return true;
    }

    await showPanel(tester, online: false, onApply: record);
    await tapText(tester, 'Custom color');
    await tapText(tester, 'Expressive');
    await showPanel(
      tester,
      palette: nativePalette(revision: 2),
      onApply: record,
    );
    expect(writes, isEmpty);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Expressive'))
          .selected,
      isTrue,
    );
    expect(find.text('Seed color'), findsOneWidget);
  });

  testWidgets('sliders apply once after settling, not during movement', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577),
      onApply: (_, int seed, _) {
        writes.add(seed);
        return true;
      },
    );
    expect(find.byType(ExpansionTile), findsNothing);
    final Slider slider = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('palette-slider-Hue')),
    );
    slider.onChangeStart!(30);
    slider.onChanged!(30);
    slider.onChanged!(60);
    await tester.pump();
    expect(writes, isEmpty);
    slider.onChangeEnd!(60);
    await tester.pump();
    expect(writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 280));
    expect(writes, hasLength(1));
    expect(writes.single, isNot(0x008577));
  });

  testWidgets('a second slider responds while the first edit is settling', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    Slider slider(String label) => tester.widget<Slider>(
      find.byKey(ValueKey<String>('palette-slider-$label')),
    );
    slider('Hue').onChangeStart!(slider('Hue').value);
    slider('Hue').onChanged!(125);
    slider('Hue').onChangeEnd!(125);
    await tester.pump(const Duration(milliseconds: 100));
    expect(writes, isEmpty);

    slider('Intensity').onChangeStart!(slider('Intensity').value);
    slider('Intensity').onChanged!(0.25);
    await tester.pump(const Duration(milliseconds: 500));
    expect(slider('Hue').value, 125);
    expect(slider('Intensity').value, 0.25);
    expect(writes, isEmpty, reason: 'no overlay write between gestures');
    slider('Intensity').onChangeEnd!(0.25);
    await tester.pump(const Duration(milliseconds: 279));
    expect(writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(writes, hasLength(1));
    final int expected =
        HSLColor.fromColor(
          const Color(0xff7655ca),
        ).withHue(125).withSaturation(0.25).toColor().toARGB32() &
        0xffffff;
    expect(writes.single, expected);
  });

  testWidgets('pointer down defers a pending edit before gesture recognition', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    final Slider hue = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('palette-slider-Hue')),
    );
    hue.onChangeStart!(hue.value);
    hue.onChanged!(160);
    hue.onChangeEnd!(160);
    await tester.pump(const Duration(milliseconds: 100));
    // Hold on non-interactive custom guidance: no Slider onChangeStart or
    // button callback can cancel the timer on our behalf.
    final Finder guidance = find.text(
      'Reset restores your starting seed. Your palette style stays the same.',
    );
    await tester.ensureVisible(guidance);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(guidance),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, isEmpty);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 280));
    expect(writes, hasLength(1));
  });

  testWidgets('a seed tap replaces a settling slider edit immediately', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    final Slider hue = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('palette-slider-Hue')),
    );
    hue.onChangeStart!(hue.value);
    hue.onChanged!(160);
    hue.onChangeEnd!(160);
    await tester.pump(const Duration(milliseconds: 100));
    final Finder ocean = find.byKey(
      const ValueKey<String>('palette-seed-Ocean'),
    );
    await tester.ensureVisible(ocean);
    await tester.tap(ocean);
    expect(writes, <int>[0x386bd5]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, hasLength(1));
  });

  testWidgets('leaving after a completed drag flushes its pending choice', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    final Slider hue = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('palette-slider-Hue')),
    );
    hue.onChangeStart!(hue.value);
    hue.onChanged!(160);
    hue.onChangeEnd!(160);
    await tester.pump();
    expect(writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(writes, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(writes, hasLength(1));
  });

  testWidgets('fine tuning is always open and all sliders are continuous', (
    tester,
  ) async {
    await showPanel(tester, palette: nativePalette(mode: 1, seed: 0x7655ca));
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Fine-tune color'), findsOneWidget);
    for (final String label in <String>['Hue', 'Intensity', 'Lightness']) {
      final Slider slider = tester.widget<Slider>(
        find.byKey(ValueKey<String>('palette-slider-$label')),
      );
      expect(
        slider.divisions,
        isNull,
        reason: 'no trailing stepped-thumb animation',
      );
      expect(slider.onChanged, isNotNull);
    }
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey<String>('palette-reset-tuning')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'HSL remains precise through gray, black, white and hue endpoints',
    (tester) async {
      await showPanel(
        tester,
        online: false,
        palette: nativePalette(mode: 1, seed: 0x7655ca),
      );
      Slider slider(String label) => tester.widget<Slider>(
        find.byKey(ValueKey<String>('palette-slider-$label')),
      );
      Future<void> move(String label, double value) async {
        slider(label).onChangeStart!(slider(label).value);
        slider(label).onChanged!(value);
        await tester.pump();
        slider(label).onChangeEnd!(value);
        await tester.pump();
      }

      await move('Hue', 360);
      expect(slider('Hue').value, 360);
      await move('Hue', 219.375);
      await move('Intensity', 0);
      expect(slider('Hue').value, 219.375);
      await move('Intensity', 0.8125);
      await move('Lightness', 0);
      expect(slider('Hue').value, 219.375);
      expect(slider('Intensity').value, 0.8125);
      await move('Lightness', 1);
      expect(slider('Hue').value, 219.375);
      expect(slider('Intensity').value, 0.8125);
      await move('Lightness', 0.54321);
      expect(slider('Lightness').value, 0.54321);
      await move('Hue', 0);
      expect(slider('Hue').value, 0);
    },
  );

  testWidgets('reset restores the seed after readback and keeps the style', (
    tester,
  ) async {
    final List<(int, int)> writes = <(int, int)>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add((seed, style));
      return true;
    }

    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca, style: 2),
      onApply: record,
    );
    final Slider hue = tester.widget<Slider>(
      find.byKey(const ValueKey<String>('palette-slider-Hue')),
    );
    hue.onChangeStart!(hue.value);
    hue.onChanged!(95.5);
    hue.onChangeEnd!(95.5);
    await tester.pump(const Duration(milliseconds: 280));
    expect(writes, hasLength(1));
    expect(writes.single.$2, 2);
    await showPanel(
      tester,
      palette: nativePalette(
        mode: 1,
        seed: writes.single.$1,
        style: 2,
        revision: 2,
        outcome: 1,
      ),
      onApply: record,
    );
    final Finder reset = find.byKey(
      const ValueKey<String>('palette-reset-tuning'),
    );
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(writes.last, (0x7655ca, 2));
    expect(writes, hasLength(2));
  });

  testWidgets('seed labels and padding belong to the full touch target', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    final Finder tile = find.byKey(
      const ValueKey<String>('palette-seed-Ocean'),
    );
    await tester.ensureVisible(tile);
    final Size size = tester.getSize(tile);
    expect(size.width, greaterThanOrEqualTo(60));
    expect(size.height, greaterThanOrEqualTo(60));
    await tester.tap(find.text('Ocean'));
    expect(writes, <int>[0x386bd5]);
  });

  testWidgets('scrolling from a seed does not apply it accidentally', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x7655ca),
      onApply: (_, seed, _) {
        writes.add(seed);
        return true;
      },
    );
    final Finder tile = find.byKey(
      const ValueKey<String>('palette-seed-Ocean'),
    );
    await tester.ensureVisible(tile);
    await tester.drag(tile, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
  });

  testWidgets('source-specific guidance stays with its own controls', (
    tester,
  ) async {
    await showPanel(tester);
    expect(
      find.textContaining('Use colors from your wallpaper'),
      findsOneWidget,
    );
    expect(find.textContaining('Tap a seed or style'), findsNothing);
    expect(find.text('Fine-tune color'), findsNothing);
    await tapText(tester, 'Custom color');
    expect(find.textContaining('Use colors from your wallpaper'), findsNothing);
    expect(find.textContaining('Tap a seed or style'), findsOneWidget);
    expect(find.text('Fine-tune color'), findsOneWidget);
  });

  testWidgets('a failed transaction drops queued edits without a retry loop', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    bool record(bool wallpaper, int seed, int style) {
      writes.add(seed);
      return true;
    }

    await showPanel(tester, onApply: record);
    await tapText(tester, 'Custom color');
    final Finder seed = find.byKey(const ValueKey<String>('palette-seed-Iris'));
    await tester.ensureVisible(seed);
    await tester.tap(seed);
    await tester.pump();
    expect(writes, hasLength(1));
    await showPanel(
      tester,
      palette: nativePalette(operationState: -1, error: 4, revision: 2),
      onApply: record,
    );
    await showPanel(
      tester,
      palette: nativePalette(revision: 3),
      onApply: record,
    );
    expect(writes, hasLength(1));
  });

  testWidgets('tapping the active choice does not rewrite Android settings', (
    tester,
  ) async {
    final List<int> writes = <int>[];
    await showPanel(
      tester,
      palette: nativePalette(mode: 1, seed: 0x008577),
      onApply: (_, int seed, _) {
        writes.add(seed);
        return true;
      },
    );
    await tapText(tester, 'Custom color');
    await tapText(tester, 'Tonal');
    expect(writes, isEmpty);
  });

  testWidgets('an initial connection is not labelled Offline', (tester) async {
    await showPanel(
      tester,
      connection: RodinConnectionState.connecting,
      palette: const RodinSystemColorsState(),
    );
    expect(
      find.textContaining('Connecting to the system service'),
      findsOneWidget,
    );
    expect(find.textContaining('service is offline'), findsNothing);
  });

  for (final Brightness brightness in Brightness.values) {
    testWidgets(
      'small width and large text have no overflow in ${brightness.name}',
      (WidgetTester tester) async {
        await showPanel(tester, width: 320, scale: 1.8, brightness: brightness);
        await tapText(tester, 'Custom color');
        expect(find.byType(ExpansionTile), findsNothing);
        await tester.ensureVisible(find.text('Android’s current colors'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
