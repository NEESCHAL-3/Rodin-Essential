import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets(
    'portrait and landscape positions and selected apps persist independently',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('rodin-monitor-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/game-monitor.json');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameMonitorScreen(
              onBack: () {},
              configFile: file,
              loadApps: () async => [
                {'package': 'test.racer', 'label': 'Racer', 'system': false},
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detailed view'));
      await tester.pumpAndSettle();
      expect(jsonDecode(file.readAsStringSync())['details'], true);
      await tester.drag(find.textContaining('CPU 32%'), const Offset(60, 30));
      await tester.pumpAndSettle();
      final positions = jsonDecode(file.readAsStringSync())['positions'];
      expect(positions['landscapex'], greaterThan(.03));
      final center =
          tester.getCenter(find.textContaining('CPU 32%')) +
          const Offset(35, 10);
      final left = await tester.startGesture(
        center - const Offset(10, 0),
        pointer: 41,
      );
      final right = await tester.startGesture(
        center + const Offset(10, 0),
        pointer: 42,
      );
      await right.moveBy(const Offset(20, 0));
      await tester.pump();
      await right.moveBy(const Offset(-26, 0));
      await tester.pump();
      await right.up();
      await left.up();
      await tester.pumpAndSettle();
      expect(jsonDecode(file.readAsStringSync())['scale'], .75);
      await tester.tap(find.text('Portrait'));
      await tester.pumpAndSettle();
      await tester.drag(find.textContaining('CPU 32%'), const Offset(8, 35));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Selected apps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Racer'));
      await tester.pumpAndSettle();
      expect(find.text('Monitoring · 1'), findsOneWidget);
      final config = jsonDecode(file.readAsStringSync());
      expect(config['apps']['test.racer'], true);
      expect(config['positions']['landscapex'], positions['landscapex']);
      expect(config['positions']['portraity'], greaterThan(.05));
    },
  );
  testWidgets(
    'history derives session metrics from samples and skips unavailable FPS',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('rodin-history-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final logs = Directory('${dir.path}/game-history')..createSync();
      File(
        '${logs.path}/0.jsonl',
      ).writeAsStringSync(jsonEncode(['start', 500, 'com.demo', 'Demo game']));
      File('${logs.path}/1.jsonl').writeAsStringSync(
        [
          ['start', 1000, 'com.demo', 'Demo game'],
          ['sample', 1000, 60, 320, null, 15],
          ['sample', 2000, null, 330],
          ['sample', 3000, 40, 340, 20, 25],
          ['end', 4000],
        ].map(jsonEncode).join('\n'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameMonitorScreen(
              onBack: () {},
              configFile: File('${dir.path}/config.json'),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      for (
        int i = 0;
        i < 8 &&
            find.text('Performance history').hitTestable().evaluate().isEmpty;
        i++
      ) {
        await tester.dragFrom(const Offset(14, 490), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        await tester.tap(find.text('Performance history'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await tester.tap(find.text('Demo game'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('20.0%'), findsNWidgets(2));
      expect(find.text('50.0'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('34.0 °C'), findsOneWidget);
      expect(find.text('2.0 °C'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'GPU'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'GPU'));
      await tester.pumpAndSettle();
      expect(find.text('Device GPU %'), findsOneWidget);
      expect(find.text('15.0 – 25.0'), findsOneWidget);
    },
  );
}
