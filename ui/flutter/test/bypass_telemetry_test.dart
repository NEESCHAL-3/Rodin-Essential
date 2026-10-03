import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/bypass_telemetry.dart';

void main() {
  bool confirmed({
    bool ready = true,
    bool enabled = true,
    bool active = true,
    int online = 1,
    double? current = 0,
  }) => isBypassDirectPowerConfirmed(
    ready: ready,
    enabled: enabled,
    kernelActive: active,
    usbOnline: online,
    batteryCurrentA: current,
  );

  test('confirmed snapshot is immediately reusable after page recreation', () {
    expect(confirmed(), isTrue);
    expect(confirmed(), isTrue);
  });
  test('request alone never confirms direct power', () {
    expect(confirmed(active: false), isFalse);
    expect(confirmed(enabled: false), isFalse);
  });
  test('missing backend or charger invalidates confirmation', () {
    expect(confirmed(ready: false), isFalse);
    expect(confirmed(online: 0), isFalse);
    expect(confirmed(online: -1), isFalse);
  });
  test('charging or battery supplementation invalidates confirmation', () {
    expect(confirmed(current: -0.4), isFalse);
    expect(confirmed(current: 0.4), isFalse);
    expect(confirmed(current: -0.1), isTrue);
    expect(confirmed(current: 0.1), isTrue);
  });
  test('unknown or invalid current is never accepted', () {
    expect(confirmed(current: null), isFalse);
    expect(confirmed(current: double.nan), isFalse);
    expect(confirmed(current: double.infinity), isFalse);
  });
}
