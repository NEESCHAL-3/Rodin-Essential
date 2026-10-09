import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

Map<String, dynamic> status() => <String, dynamic>{
  'error': null,
  for (final key in <String>['memory', 'storage'])
    key: <String, dynamic>{
      'supported': true,
      'restore_pending': false,
      'remaining_seconds': 0,
      'frequencies_hz': key == 'memory'
          ? <int>[757000000, 1542000000, 8533000000]
          : <int>[273000000, 499200000],
      'driver_hz': key == 'memory' ? 757000000 : 273000000,
      'min_hz': key == 'memory' ? 757000000 : 273000000,
      'max_hz': key == 'memory' ? 8533000000 : 499200000,
    },
};

void main() {
  testWidgets('dynamic range survives telemetry edits and sends both bounds', (
    tester,
  ) async {
    final commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubsystemClocksScreen(
            onBack: () {},
            exchange: (command) async {
              commands.add(command);
              return status();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('range-memory'));
    tester.widget<RangeSlider>(finder).onChanged!(const RangeValues(0, 1));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.widget<RangeSlider>(finder).values.end, 1);
    expect(commands.where((c) => c.startsWith('ACTION')), isEmpty);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('apply-memory'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-memory')));
    await tester.pumpAndSettle();
    expect(commands.where((c) => c.startsWith('ACTION')).toList(), <String>[
      'ACTION subsystem.clocks.range memory 757000000 1542000000',
    ]);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('live telemetry stops while backgrounded', (tester) async {
    final commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubsystemClocksScreen(
            onBack: () {},
            exchange: (command) async {
              commands.add(command);
              return status();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(commands, <String>['GET subsystem.clocks']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(commands, <String>['GET subsystem.clocks', 'GET subsystem.clocks']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('CPU-style exact lock previews and applies supported bounds', (
    tester,
  ) async {
    final commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubsystemClocksScreen(
            onBack: () {},
            exchange: (command) async {
              commands.add(command);
              return status();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Exact Lock').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exact Lock').first);
    await tester.pumpAndSettle();
    final sliderFinder = find.byKey(const ValueKey('frequency-memory'));
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.onChangeStart, isNotNull);
    slider.onChangeStart!(0);
    slider.onChanged!(0);
    await tester.pumpAndSettle();
    expect(commands, <String>['GET subsystem.clocks']);
    expect(tester.widget<Slider>(sliderFinder).value, 0);
    tester.widget<Slider>(sliderFinder).onChangeEnd!(0);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('apply-memory'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-memory')));
    await tester.pumpAndSettle();
    // Animation settling can span another legitimate telemetry poll. Hardware
    // writes must still occur exactly once and use the selected supported OPP.
    expect(commands.where((command) => !command.startsWith('GET ')), <String>[
      'ACTION subsystem.clocks.range memory 757000000 757000000',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final brightness in Brightness.values) {
    testWidgets('subsystem cards wrap and never auto-apply ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SubsystemClocksScreen(
              onBack: () {},
              exchange: (command) async {
                commands.add(command);
                return status();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('UFS 4.0 Storage'), 180);
      await tester.pumpAndSettle();
      expect(commands, <String>['GET subsystem.clocks']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'one slider per device without redundant chips or trial buttons',
    (tester) async {
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubsystemClocksScreen(
              onBack: () {},
              exchange: (command) async {
                commands.add(command);
                return status();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Test maximum · 30 seconds'), findsNothing);
      expect(find.byKey(const ValueKey('range-memory')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('range-storage')),
        180,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RangeSlider>(find.byKey(const ValueKey('range-storage')))
            .divisions,
        1,
      );
      expect(commands, <String>['GET subsystem.clocks']);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
