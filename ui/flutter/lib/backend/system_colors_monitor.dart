import 'dart:async';

/// Observes only the native palette cache while one transaction is running.
/// No IPC, hardware polling or system writes are performed by this timer.
final class RodinSystemColorsMonitor {
  RodinSystemColorsMonitor({required this.readStamp, required this.onChanged});

  final (int state, int revision) Function() readStamp;
  final void Function() onChanged;
  static const Duration interval = Duration(milliseconds: 32);
  static const int _maxSamples = 2813; // Bounded to 90 seconds per operation.
  Timer? _timer;
  (int, int)? _previous;
  int _samples = 0;

  void watch() {
    _previous = null;
    _samples = 0;
    _timer ??= Timer.periodic(interval, (_) => _sample());
  }

  void _sample() {
    final (int state, int revision) stamp = readStamp();
    final bool changed = stamp != _previous;
    _previous = stamp;
    if (stamp.$1 != 1 || ++_samples >= _maxSamples) {
      // Stop before notifying: the completion callback can queue another
      // operation and start a new watch without this one cancelling it.
      _timer?.cancel();
      _timer = null;
    }
    if (changed) onChanged();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _previous = null;
  }
}
