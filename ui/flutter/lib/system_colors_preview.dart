import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';

typedef RodinPaletteKey = (int seed, int style, bool dark);

const List<DynamicSchemeVariant> _variants = <DynamicSchemeVariant>[
  DynamicSchemeVariant.tonalSpot,
  DynamicSchemeVariant.vibrant,
  DynamicSchemeVariant.expressive,
  DynamicSchemeVariant.neutral,
  DynamicSchemeVariant.rainbow,
  DynamicSchemeVariant.fruitSalad,
  DynamicSchemeVariant.monochrome,
];

// Send only primitive colors across the isolate boundary. No widget, native
// handle, backend connection or UI state is captured by the worker.
List<int> _generatePalette(RodinPaletteKey key) {
  final (int seed, int style, bool dark) = key;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: Color(0xff000000 | seed),
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: _variants[style],
  );
  return <Color>[
    scheme.surfaceContainerLow,
    scheme.outlineVariant,
    scheme.onSurface,
    scheme.tertiaryContainer,
    scheme.onTertiaryContainer,
    scheme.primaryContainer,
    scheme.onPrimaryContainer,
    scheme.primary,
    scheme.onPrimary,
    scheme.surfaceContainerHighest,
    scheme.secondaryContainer,
    scheme.onSecondaryContainer,
  ].map((Color color) => color.toARGB32()).toList(growable: false);
}

ColorScheme rodinPreviewScheme(List<int> colors, bool dark) {
  if (colors.length != 12) throw const FormatException('Invalid preview');
  return (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    surfaceContainerLow: Color(colors[0]),
    outlineVariant: Color(colors[1]),
    onSurface: Color(colors[2]),
    tertiaryContainer: Color(colors[3]),
    onTertiaryContainer: Color(colors[4]),
    primaryContainer: Color(colors[5]),
    onPrimaryContainer: Color(colors[6]),
    primary: Color(colors[7]),
    onPrimary: Color(colors[8]),
    surfaceContainerHighest: Color(colors[9]),
    secondaryContainer: Color(colors[10]),
    onSecondaryContainer: Color(colors[11]),
  );
}

void _paletteWorker(SendPort replies) {
  final ReceivePort requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((dynamic message) {
    final (int id, RodinPaletteKey key) = message as (int, RodinPaletteKey);
    try {
      replies.send(<Object>[id, _generatePalette(key)]);
    } catch (error) {
      replies.send(<Object>[id, error.toString()]);
    }
  });
}

/// A single on-demand worker for the visible preview. It has no timer or
/// background system writes and is stopped when the color screen is closed.
final class RodinPalettePreviewWorker {
  ReceivePort? _events;
  Isolate? _isolate;
  SendPort? _requests;
  Completer<void>? _ready;
  final Map<int, Completer<List<int>>> _pending = <int, Completer<List<int>>>{};
  int _nextId = 0;
  bool _disposed = false;
  Object? _failure;

  Future<void> _start() async {
    if (_disposed) throw StateError('Preview worker is closed');
    if (_failure != null) throw _failure!;
    if (_ready == null) {
      _ready = Completer<void>();
      final ReceivePort events = _events = ReceivePort();
      events.listen(_receive);
      unawaited(
        Isolate.spawn<SendPort>(
          _paletteWorker,
          events.sendPort,
          onError: events.sendPort,
          onExit: events.sendPort,
          debugName: 'Rodin palette preview',
        ).then((Isolate isolate) {
          if (_disposed) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
        }, onError: (Object error, StackTrace stack) => _fail(error)),
      );
    }
    await _ready!.future;
  }

  void _receive(dynamic message) {
    if (_disposed) return;
    if (message is SendPort) {
      _requests = message;
      if (!_ready!.isCompleted) _ready!.complete();
    } else if (message is List && message.length == 2 && message[0] is int) {
      final Completer<List<int>>? reply = _pending.remove(message[0]);
      if (reply == null) return;
      if (message[1] is List<int>) {
        reply.complete(message[1] as List<int>);
      } else {
        reply.completeError(StateError('${message[1]}'));
      }
    } else {
      _fail(StateError('Preview worker stopped'));
    }
  }

  void _fail(Object error) {
    _failure = error;
    if (_ready != null && !_ready!.isCompleted) _ready!.completeError(error);
    for (final Completer<List<int>> reply in _pending.values) {
      reply.completeError(error);
    }
    _pending.clear();
  }

  Future<List<int>> generate(RodinPaletteKey key) async {
    await _start();
    if (_disposed) throw StateError('Preview worker is closed');
    if (_failure != null) throw _failure!;
    final int id = _nextId++;
    final Completer<List<int>> reply = Completer<List<int>>();
    _pending[id] = reply;
    _requests!.send((id, key));
    return reply.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fail(StateError('Preview worker is closed'));
    _isolate?.kill(priority: Isolate.immediate);
    _events?.close();
  }
}
