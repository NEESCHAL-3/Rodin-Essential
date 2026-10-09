import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/per_app_backend.dart';

void main() {
  test(
    'queued native requests do not capture an unsendable completer',
    () async {
      // The desktop test host cannot load the Android library. Reaching that
      // loader failure proves the queued request crossed the isolate boundary.
      for (int i = 0; i < 2; i++) {
        try {
          await PerAppBackend.instance.command('GET app.controls');
          fail('The desktop host should not load the Android native library');
        } catch (error) {
          expect('$error', isNot(contains('unsendable')));
          expect('$error', contains('dynamic library'));
        }
      }
    },
  );
}
