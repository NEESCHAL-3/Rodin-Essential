import 'dart:convert';
import 'dart:io';

import 'system_colors_state.dart';

/// A UI-only hint. Android remains the owner of the actual palette.
final class RodinSystemColorsPreferences {
  static File get _file => File(
    '${Directory.systemTemp.parent.path}/files/rodin-system-colors.json',
  );

  static Future<RodinSystemColorsSelection?> read() async {
    try {
      final File file = _file;
      if (!await file.exists() || await file.length() > 1024) return null;
      return RodinSystemColorsSelection.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(RodinSystemColorsSelection? selection) async {
    try {
      final File file = _file;
      await file.parent.create(recursive: true);
      final File pending = File('${file.path}.pending');
      await pending.writeAsString(
        jsonEncode(selection?.toJson()),
        flush: false,
      );
      await pending.rename(file.path);
    } catch (_) {
      // A missing UI hint must not affect Android's saved palette.
    }
  }
}
