import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

typedef _ExchangeNative =
    Int32 Function(Pointer<Uint8>, Int32, Pointer<Uint8>, Int32);
typedef _Exchange = int Function(Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _AllocateNative = Pointer<Void> Function(IntPtr);
typedef _Allocate = Pointer<Void> Function(int);
typedef _ReleaseNative = Void Function(Pointer<Void>);
typedef _Release = void Function(Pointer<Void>);

/// Daemon-owned profiles, never a second preference owner in the UI process.
/// Blocking Android/IPC work stays off the Flutter rendering isolate.
class PerAppBackend {
  PerAppBackend._();
  static final PerAppBackend instance = PerAppBackend._();
  Future<void> _tail = Future<void>.value();

  Future<Map<String, Uint8List>> icons(List<String> packages) async {
    final String input = jsonEncode(packages.take(40).toList());
    final String raw = await _runIcons(input);
    final Map<String, dynamic> reply = jsonDecode(raw) as Map<String, dynamic>;
    return reply.map(
      (String package, dynamic png) =>
          MapEntry<String, Uint8List>(package, base64Decode(png as String)),
    );
  }

  Future<dynamic> command(String command) {
    final Completer<dynamic> result = Completer<dynamic>();
    _tail = _tail.then((_) async {
      try {
        final String raw = await _runExchange(command);
        final Map<String, dynamic> reply =
            jsonDecode(raw) as Map<String, dynamic>;
        if (reply['ok'] != true) throw StateError('${reply['error']}');
        final dynamic data = reply['data'];
        if (command == 'GET app.list' && data is List) {
          final String packages = jsonEncode(
            data.map((dynamic app) => app['package']).toList(),
          );
          try {
            final String rawLabels = await _runLabels(packages);
            final Map<String, dynamic> labels =
                jsonDecode(rawLabels) as Map<String, dynamic>;
            for (final dynamic app in data) {
              app['label'] = labels[app['package']] ?? app['package'];
            }
          } catch (_) {
            /* Labels are optional; never hide installed apps. */
          }
        }
        result.complete(data);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  // Separate capture scopes prevent the queue's Completer from being sent
  // along with an otherwise simple string request to the worker isolate.
  static Future<String> _runExchange(String command) =>
      Isolate.run(() => _exchange(command));

  static Future<String> _runLabels(String packages) =>
      Isolate.run(() => _native(packages, 'rodin_host_app_labels'));

  static Future<String> _runIcons(String packages) =>
      Isolate.run(() => _native(packages, 'rodin_host_app_icons'));

  static String _exchange(String command) {
    return _native(command, 'rodin_backend_app_controls_exchange');
  }

  static String _native(String command, String symbol) {
    final DynamicLibrary host = DynamicLibrary.open(
      'librodin_essential_host.so',
    );
    final DynamicLibrary libc = DynamicLibrary.open('libc.so');
    final _Allocate allocate = libc.lookupFunction<_AllocateNative, _Allocate>(
      'malloc',
    );
    final _Release release = libc.lookupFunction<_ReleaseNative, _Release>(
      'free',
    );
    final _Exchange exchange = host.lookupFunction<_ExchangeNative, _Exchange>(
      symbol,
    );
    final List<int> bytes = utf8.encode(command);
    if (bytes.isEmpty ||
        bytes.length >
            (symbol == 'rodin_backend_app_controls_exchange' ? 4096 : 262144))
      throw StateError('Profile request is too large');
    const int capacity = 1048576;
    final Pointer<Void> input = allocate(bytes.length);
    final Pointer<Void> output = allocate(capacity);
    if (input == nullptr || output == nullptr) {
      if (input != nullptr) release(input);
      if (output != nullptr) release(output);
      throw StateError('Unable to allocate profile exchange');
    }
    try {
      input.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
      final int length = exchange(
        input.cast<Uint8>(),
        bytes.length,
        output.cast<Uint8>(),
        capacity,
      );
      if (length < 0 || length > capacity)
        throw StateError('Per-App Controls exchange failed ($length)');
      return utf8.decode(output.cast<Uint8>().asTypedList(length));
    } finally {
      release(input);
      release(output);
    }
  }
}
