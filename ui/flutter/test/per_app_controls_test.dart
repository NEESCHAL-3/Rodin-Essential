import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

Map<String, dynamic> state() => <String, dynamic>{
  'config': <String, dynamic>{'enabled': false, 'profiles': <dynamic>[]},
  'status': 'global',
  'owner': null,
  'error': null,
  'serviceEnabled': true,
};
Future<void> show(
  WidgetTester tester,
  List<String> commands, {
  double width = 390,
  double scale = 1,
  bool reject = false,
  int extraApps = 0,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: PerAppControlsScreen(
          onBack: () {},
          exchange: (String cmd) async {
            commands.add(cmd);
            if (cmd == 'GET app.capabilities')
              return <String, dynamic>{
                'touch': <int>[0, 1, 2, 3],
                'gpu': <int>[0, 1, 2, 3],
                'refresh': <int>[0, 60, 120],
                'cpu': <String, dynamic>{
                  '0': <String, dynamic>{
                    'frequencies': <int>[300, 1000, 2100],
                    'governors': <String>['schedutil', 'performance'],
                  },
                },
                'cores': true,
              };
            if (cmd == 'GET app.list')
              return <dynamic>[
                <String, dynamic>{
                  'user': 0,
                  'package': 'com.example.game',
                  'system': false,
                },
                <String, dynamic>{
                  'user': 0,
                  'package': 'com.android.settings',
                  'system': true,
                },
                for (int i = 0; i < extraApps; i++)
                  <String, dynamic>{
                    'user': 0,
                    'package':
                        'com.example.extra.${i.toString().padLeft(3, '0')}',
                    'system': false,
                  },
              ];
            if (reject && cmd.startsWith('ACTION '))
              throw StateError('Restore rejected');
            return state();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'scrolling reaches every installed app without a Show More button',
    (WidgetTester tester) async {
      await show(tester, <String>[], extraApps: 85);
      await tester.dragUntilVisible(
        find.text('com.example.extra.084'),
        find.byType(Scrollable).first,
        const Offset(0, -600),
        maxIteration: 35,
      );
      await tester.pumpAndSettle();
      expect(find.text('com.example.extra.084'), findsOneWidget);
      expect(find.text('Show more apps'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'system apps start hidden and can be shown without removing third-party apps',
    (WidgetTester tester) async {
      await show(tester, <String>[]);
      expect(find.text('com.android.settings'), findsNothing);
      expect(find.text('com.example.game'), findsOneWidget);
      await tester.ensureVisible(find.text('Show system apps'));
      await tester.tap(find.text('Show system apps'));
      await tester.pumpAndSettle();
      expect(find.text('com.android.settings'), findsOneWidget);
      expect(find.text('com.example.game'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'searchable system and third party apps use real package identities',
    (WidgetTester tester) async {
      final List<String> commands = <String>[];
      await show(tester, commands);
      await tester.tap(find.text('Show system apps'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'settings');
      await tester.pumpAndSettle();
      expect(find.text('com.android.settings'), findsOneWidget);
      expect(find.text('com.example.game'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'native back returns to the app list before leaving the section',
    (WidgetTester tester) async {
      await show(tester, <String>[]);
      await tester.ensureVisible(find.text('com.example.game'));
      await tester.tap(find.text('com.example.game'));
      await tester.pumpAndSettle();
      expect(RodinNestedBackController.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('Search installed apps'), findsOneWidget);
      expect(RodinNestedBackController.handleBack(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('new profile follows global and saves only selected controls', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await show(tester, commands);
    await tester.ensureVisible(find.text('com.example.game'));
    await tester.tap(find.text('com.example.game'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.scrollUntilVisible(
      find.text('OEM adaptive').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('OEM adaptive').first);
    await tester.pumpAndSettle();
    expect(find.text('Save app profile'), findsNothing);
    final String command = commands.firstWhere(
      (String c) => c.startsWith('SET app.profile '),
    );
    final Map<String, dynamic> saved =
        jsonDecode(command.substring('SET app.profile '.length))
            as Map<String, dynamic>;
    expect(saved['package'], 'com.example.game');
    expect(saved['profile'], <String, dynamic>{'enabled': true, 'touch': 0});
    expect(commands.where((String c) => c == 'SET app.enabled 1'), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('disabled overrides are explicit and require deliberate enable', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await show(tester, commands);
    await tester.ensureVisible(find.text('com.example.game'));
    await tester.tap(find.text('com.example.game'));
    await tester.pumpAndSettle();
    expect(find.text('Overrides are off'), findsOneWidget);
    expect(commands.where((String c) => c == 'SET app.enabled 1'), isEmpty);
    await tester.ensureVisible(find.text('Enable Per-App Controls'));
    await tester.tap(find.text('Enable Per-App Controls'));
    await tester.pumpAndSettle();
    expect(
      commands.where((String c) => c == 'SET app.enabled 1'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unsupported refresh modes are absent', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await show(tester, commands);
    await tester.ensureVisible(find.text('com.example.game'));
    await tester.tap(find.text('com.example.game'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('120 Hz'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('90 Hz'), findsNothing);
    expect(find.text('120 Hz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('stepped frequency sliders keep governors independent', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await show(tester, commands);
    await tester.ensureVisible(find.text('com.example.game'));
    await tester.tap(find.text('com.example.game'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Set minimum and maximum'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set minimum and maximum'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Maximum frequency'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final Slider maximum = tester.widgetList<Slider>(find.byType(Slider)).last;
    maximum.onChanged!(1);
    maximum.onChangeEnd!(1);
    await tester.pumpAndSettle();
    final String command = commands.lastWhere(
      (String c) => c.startsWith('SET app.profile '),
    );
    final Map<String, dynamic> saved =
        jsonDecode(command.substring('SET app.profile '.length))
            as Map<String, dynamic>;
    expect(saved['profile']['cpu'], <String, dynamic>{
      '0': <String, dynamic>{
        'range': <int>[300, 1000],
      },
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('small display and large text do not overflow', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await show(tester, commands, width: 320, scale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('com.example.game'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('com.example.game'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
