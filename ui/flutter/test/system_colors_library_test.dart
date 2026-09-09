import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/backend/system_colors_library.dart';

void main() {
  late Directory temporary;
  late File storage;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('rodin-colors-test-');
    storage = File('${temporary.path}/library.json');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('confirmed recents persist, deduplicate, and stay bounded', () async {
    final RodinSystemColorsLibrary library = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    for (int index = 0; index < 10; index++) {
      await library.record(0x100000 + index, index % 7);
    }
    await library.record(0x100005, 5);

    final RodinSystemColorsLibrary restored = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    await restored.load();
    expect(restored.recents, hasLength(8));
    expect(restored.recents.first, (0x100005, 5));
    expect(
      restored.recents.where((item) => item == (0x100005, 5)),
      hasLength(1),
    );
  });

  test('saved names replace case-insensitively and can be removed', () async {
    final RodinSystemColorsLibrary library = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    await library.save('Night', 0x112233, 0);
    await library.save('night', 0x445566, 2);
    expect(library.saved, hasLength(1));
    expect(library.saved.single.seed, 0x445566);

    await library.remove(library.saved.single);
    final RodinSystemColorsLibrary restored = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    await restored.load();
    expect(restored.saved, isEmpty);
  });

  test('malformed or oversized local data is ignored safely', () async {
    await storage.writeAsString('{broken');
    final RodinSystemColorsLibrary malformed = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    await malformed.load();
    expect(malformed.recents, isEmpty);
    expect(malformed.saved, isEmpty);

    await storage.writeAsString('x' * (16 * 1024 + 1));
    final RodinSystemColorsLibrary oversized = RodinSystemColorsLibrary(
      storageFile: storage,
    );
    await oversized.load();
    expect(oversized.recents, isEmpty);
    expect(oversized.saved, isEmpty);
  });
}
