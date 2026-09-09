import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/backend_connection.dart';

void main() {
  test('only a successful handshake is Live', () {
    expect(RodinConnectionState.fromNative(1), RodinConnectionState.online);
    expect(RodinConnectionState.fromNative(1).badgeLabel, 'LIVE');
  });

  test('startup and a confirmed connection failure remain distinct', () {
    expect(
      RodinConnectionState.fromNative(-1),
      RodinConnectionState.connecting,
    );
    expect(RodinConnectionState.fromNative(-1).badgeLabel, 'CONNECTING');
    expect(RodinConnectionState.fromNative(0), RodinConnectionState.offline);
    expect(RodinConnectionState.fromNative(0).badgeLabel, 'OFFLINE');
  });
}
