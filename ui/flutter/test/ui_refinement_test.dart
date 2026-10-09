import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/main.dart';

void main() {
  testWidgets('Home and Hubs pin service status to the card trailing edge', (
    tester,
  ) async {
    for (final page in <Widget>[
      HomeScreen(onOpen: (_) {}, onHubs: () {}, onSupport: () {}),
      HubsScreen(onOpen: (_) {}),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
      await tester.pumpAndSettle();
      final badge = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_HomeLiveBadge',
      );
      final card = find
          .ancestor(of: badge, matching: find.byType(SurfaceCard))
          .first;
      final trailingGap =
          tester.getRect(card).right - tester.getRect(badge).right;
      expect(trailingGap, inInclusiveRange(15, 20));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'Support emblem aligns with the product name, not the badge stack',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SupportScreen())),
      );
      await tester.pumpAndSettle();
      final emblem = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_RodinAppEmblem',
      );
      expect(
        (tester.getRect(emblem).top -
                tester.getRect(find.text('Rodin Essential')).top)
            .abs(),
        lessThan(3),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  final pages = <String, Widget Function()>{
    'CPU': () => CpuControlScreen(onBack: () {}),
    'Resolution': () => ResolutionScreen(onBack: () {}),
    'ZRAM': () => ZramSwapScreen(onBack: () {}),
    'Support': () => const SupportScreen(),
    'Hubs': () => HubsScreen(onOpen: (_) {}),
  };
  for (final brightness in Brightness.values) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} wraps on narrow screens ($brightness)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint(details.toString());
          previous?.call(details);
        };
        addTearDown(() => FlutterError.onError = previous);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.35)),
              child: child!,
            ),
            home: Scaffold(body: entry.value()),
          ),
        );
        await tester.pumpAndSettle();
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason: error is FlutterError
              ? error.diagnostics.map((item) => item.toStringDeep()).join('\n')
              : null,
        );
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final details = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_DiagnosticRow',
          ),
          matching: find.byType(Text),
        );
        for (final text in tester.widgetList<Text>(details)) {
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(text.maxLines, isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
