import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Development-only measurements, never an always-running production ticker.
/// Enable with RODIN_MOTION_TRACE=true; records durations, not user content.
class RodinMotionDiagnostics {
  static const enabled = bool.fromEnvironment('RODIN_MOTION_TRACE');
  static final List<FrameTiming> _frames = [];
  static Timer? _finish;
  static bool _attached = false;
  static String _edge = '';

  static void begin(bool rightEdge, {String? label}) {
    if (!enabled) return;
    if (_attached) _report();
    _edge = label ?? (rightEdge ? 'right' : 'left');
    _frames.clear();
    _finish?.cancel();
    SchedulerBinding.instance.addTimingsCallback(_collect);
    _attached = true;
    // Lifecycle loss must not leave diagnostics collecting indefinitely.
    _finish = Timer(const Duration(seconds: 4), _report);
  }

  static void _collect(List<FrameTiming> frames) => _frames.addAll(frames);

  static void end() {
    if (!enabled || !_attached) return;
    _finish?.cancel();
    // Release Flutter batches timings; wait long enough for the final batch,
    // rather than dropping a short opening animation before its report arrives.
    _finish = Timer(const Duration(milliseconds: 1500), _report);
  }

  static void _report() {
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _attached = false;
    _finish?.cancel();
    if (_frames.isEmpty) return;
    final build = _frames.map((f) => f.buildDuration.inMicroseconds).toList()
      ..sort();
    final raster = _frames.map((f) => f.rasterDuration.inMicroseconds).toList()
      ..sort();
    final slow120 = _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 8333 ||
              f.rasterDuration.inMicroseconds > 8333,
        )
        .length;
    final slow60 = _frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > 16667 ||
              f.rasterDuration.inMicroseconds > 16667,
        )
        .length;
    final p95 = ((_frames.length - 1) * 0.95).round();
    debugPrint(
      'RODIN_BACK_TIMINGS edge=$_edge frames=${_frames.length} '
      'build_p95_us=${build[p95]} raster_p95_us=${raster[p95]} '
      'build_max_us=${build.last} raster_max_us=${raster.last} '
      'over_8ms=$slow120 over_16ms=$slow60',
    );
    _frames.clear();
  }
}
