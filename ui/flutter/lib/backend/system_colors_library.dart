import 'dart:convert';
import 'dart:io';

final class RodinSavedPalette {
  const RodinSavedPalette({
    required this.name,
    required this.seed,
    required this.style,
  });

  final String name;
  final int seed;
  final int style;

  static RodinSavedPalette? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final Object? name = value['name'];
    final Object? seed = value['seed'];
    final Object? style = value['style'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 32 ||
        seed is! int ||
        seed < 0 ||
        seed > 0xffffff ||
        style is! int ||
        style < 0 ||
        style > 6) {
      return null;
    }
    return RodinSavedPalette(name: name.trim(), seed: seed, style: style);
  }

  Map<String, Object> toJson() => <String, Object>{
    'name': name,
    'seed': seed,
    'style': style,
  };
}

final class RodinSystemColorsLibrary {
  RodinSystemColorsLibrary({File? storageFile}) : _storageFile = storageFile;

  final File? _storageFile;
  File get _file =>
      _storageFile ??
      File(
        '${Directory.systemTemp.parent.path}/files/rodin-system-colors-library.json',
      );

  List<(int, int)> recents = <(int, int)>[];
  List<RodinSavedPalette> saved = <RodinSavedPalette>[];

  Future<void> load() async {
    try {
      final File file = _file;
      if (!await file.exists() || await file.length() > 16 * 1024) return;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) return;
      final Object? recentJson = decoded['recents'];
      final Object? savedJson = decoded['saved'];
      if (recentJson is List) {
        recents = recentJson
            .whereType<List<dynamic>>()
            .where((List<dynamic> item) => item.length == 2)
            .map<(int, int)?>(
              (List<dynamic> item) =>
                  item[0] is int &&
                      item[1] is int &&
                      (item[0] as int) >= 0 &&
                      (item[0] as int) <= 0xffffff &&
                      (item[1] as int) >= 0 &&
                      (item[1] as int) <= 6
                  ? (item[0] as int, item[1] as int)
                  : null,
            )
            .whereType<(int, int)>()
            .take(8)
            .toList();
      }
      if (savedJson is List) {
        saved = savedJson
            .map(RodinSavedPalette.fromJson)
            .whereType<RodinSavedPalette>()
            .take(12)
            .toList();
      }
    } catch (_) {
      recents = <(int, int)>[];
      saved = <RodinSavedPalette>[];
    }
  }

  Future<void> record(int seed, int style) async {
    recents.removeWhere(
      ((int, int) item) => item.$1 == seed && item.$2 == style,
    );
    recents.insert(0, (seed, style));
    if (recents.length > 8) recents.removeRange(8, recents.length);
    await _write();
  }

  Future<void> save(String name, int seed, int style) async {
    saved.removeWhere(
      (RodinSavedPalette item) =>
          item.name.toLowerCase() == name.trim().toLowerCase(),
    );
    saved.insert(
      0,
      RodinSavedPalette(name: name.trim(), seed: seed, style: style),
    );
    if (saved.length > 12) saved.removeRange(12, saved.length);
    await _write();
  }

  Future<void> remove(RodinSavedPalette palette) async {
    saved.remove(palette);
    await _write();
  }

  Future<void> _write() async {
    try {
      final File file = _file;
      await file.parent.create(recursive: true);
      final File pending = File('${file.path}.pending');
      await pending.writeAsString(
        jsonEncode(<String, Object>{
          'schema': 1,
          'recents': recents.map((item) => <int>[item.$1, item.$2]).toList(),
          'saved': saved.map((item) => item.toJson()).toList(),
        }),
        flush: false,
      );
      await pending.rename(file.path);
    } catch (_) {
      // Palette application remains independent from optional local history.
    }
  }
}
