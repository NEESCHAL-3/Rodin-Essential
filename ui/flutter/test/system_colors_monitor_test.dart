import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/system_colors_monitor.dart';

void main() {
  testWidgets('palette completion is delivered without the dashboard delay', (
    tester,
  ) async {
    (int, int) stamp = (1, 4);
    int reads = 0;
    final List<(int, int)> delivered = <(int, int)>[];
    final RodinSystemColorsMonitor monitor = RodinSystemColorsMonitor(
      readStamp: () {
        reads++;
        return stamp;
      },
      onChanged: () => delivered.add(stamp),
    );
    addTearDown(monitor.dispose);
    monitor.watch();
    await tester.pump(RodinSystemColorsMonitor.interval);
    expect(delivered, <(int, int)>[(1, 4)]);
    await tester.pump(RodinSystemColorsMonitor.interval);
    expect(
      delivered,
      hasLength(1),
      reason: 'no repeated UI refresh while busy',
    );
    stamp = (2, 5);
    await tester.pump(RodinSystemColorsMonitor.interval);
    expect(delivered.last, (2, 5));
    final int completedReads = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, completedReads, reason: 'no idle polling');
  });

  testWidgets('a completion can start the next watch without losing it', (
    tester,
  ) async {
    (int, int) stamp = (1, 4);
    final List<(int, int)> delivered = <(int, int)>[];
    late final RodinSystemColorsMonitor monitor;
    monitor = RodinSystemColorsMonitor(
      readStamp: () => stamp,
      onChanged: () {
        delivered.add(stamp);
        if (stamp == (2, 5)) {
          stamp = (1, 5);
          monitor.watch();
        }
      },
    );
    addTearDown(monitor.dispose);
    monitor.watch();
    stamp = (2, 5);
    await tester.pump(RodinSystemColorsMonitor.interval);
    await tester.pump(RodinSystemColorsMonitor.interval);
    expect(delivered, <(int, int)>[(2, 5), (1, 5)]);
    stamp = (-1, 6);
    await tester.pump(RodinSystemColorsMonitor.interval);
    expect(delivered.last, (-1, 6));
    await tester.pump(const Duration(seconds: 1));
    expect(delivered, hasLength(3));
  });

  testWidgets('watching is bounded even if a native worker stops replying', (
    tester,
  ) async {
    int reads = 0;
    final RodinSystemColorsMonitor monitor = RodinSystemColorsMonitor(
      readStamp: () {
        reads++;
        return (1, 0);
      },
      onChanged: () {},
    );
    addTearDown(monitor.dispose);
    monitor.watch();
    await tester.pump(const Duration(seconds: 91));
    final int boundedReads = reads;
    expect(boundedReads, lessThan(2850));
    await tester.pump(const Duration(seconds: 1));
    expect(reads, boundedReads);
    monitor.watch();
    monitor.dispose();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, boundedReads);
  });
}
