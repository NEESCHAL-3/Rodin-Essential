part of 'main.dart';

class SubsystemClocksScreen extends StatefulWidget {
  const SubsystemClocksScreen({required this.onBack, this.exchange, super.key});
  final VoidCallback onBack;
  final Future<dynamic> Function(String)? exchange;
  @override
  State<SubsystemClocksScreen> createState() => _SubsystemClocksScreenState();
}

class _SubsystemClocksScreenState extends State<SubsystemClocksScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _state;
  String? _error, _busy;
  bool _reading = false, _visible = true;
  Timer? _refresh;
  Completer<void>? _readCompletion;
  Future<dynamic> _exchange(String command) =>
      (widget.exchange ?? PerAppBackend.instance.command)(command);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_read());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _refresh?.cancel();
    if (_visible) unawaited(_read());
  }

  void _schedule() {
    _refresh?.cancel();
    if (mounted && _visible)
      _refresh = Timer(const Duration(seconds: 2), () => unawaited(_read()));
  }

  Future<void> _read() async {
    if (_reading || _busy != null) {
      _schedule();
      return;
    }
    _reading = true;
    final completion = Completer<void>();
    _readCompletion = completion;
    try {
      final data = await _exchange('GET subsystem.clocks');
      if (mounted)
        setState(() {
          _state = Map<String, dynamic>.from(data as Map);
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      _reading = false;
      completion.complete();
      _schedule();
    }
  }

  Future<bool> _action(String command, String key) async {
    if (_busy != null) return false;
    // Serialize behind any in-flight read, so stale telemetry cannot overwrite
    // a newly acknowledged selection. The hardware command stays off the isolate.
    _refresh?.cancel();
    setState(() => _busy = key);
    try {
      await _readCompletion?.future;
      if (!mounted) return false;
      final data = await _exchange(command);
      if (mounted)
        setState(() {
          _state = Map<String, dynamic>.from(data as Map);
          _error = null;
        });
      RodinHaptics.confirm();
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      RodinHaptics.reject();
      return false;
    } finally {
      if (mounted) setState(() => _busy = null);
      _schedule();
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _section(
    String key,
    String title,
    String subtitle,
    IconData icon,
    Color accent,
  ) {
    final item = Map<String, dynamic>.from(
      (_state?[key] as Map?) ?? const <String, dynamic>{},
    );
    return Column(
      children: <Widget>[
        HeroCard(
          icon: icon,
          accent: accent,
          title: title,
          subtitle: subtitle,
          leading: _SubsystemHardwareIcon(
            storage: key == 'storage',
            accent: accent,
          ),
        ),
        const SizedBox(height: 12),
        _SubsystemFrequencyCard(
          key: ValueKey('card-$key'),
          subsystem: key,
          title: title,
          accent: accent,
          item: item,
          enabled: _busy == null && _state?['error'] == null,
          onApply: (min, max) =>
              _action('ACTION subsystem.clocks.range $key $min $max', key),
          onReset: () => _action('ACTION subsystem.clocks.oem $key', key),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RodinScrollPage(
    children: <Widget>[
      DetailHeader(title: 'Memory DVFS & UFS', onBack: widget.onBack),
      const SizedBox(height: 4),
      Text(
        'DRAM and storage frequency ranges, exact locks and OEM control',
        style: TextStyle(
          fontSize: 13.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 14),
      if (_error != null || _state?['error'] != null)
        SurfaceCard(child: Text(_error ?? '${_state!['error']}')),
      if (_state == null && _error == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      _section(
        'memory',
        'LPDDR5X RAM',
        'Memory DVFS · DRAM frequency coordinator',
        Icons.memory_rounded,
        const Color(0xFFB087FF),
      ),
      const SizedBox(height: 20),
      _section(
        'storage',
        'UFS 4.0 Storage',
        'Storage controller · Clock ranges and exact locks',
        Icons.storage_rounded,
        const Color(0xFF67C2FF),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: _busy == null ? _read : null,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Refresh readings'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          'Settings remain active when Rodin Essential closes. For now, reboot or daemon restart restores OEM settings. Thermal protection and suspend remain active.',
          style: TextStyle(fontSize: 11, height: 1.5),
        ),
      ),
    ],
  );
}

/// NEESCHAL: recognisable hardware, not another CPU icon wearing a RAM label.
class _SubsystemHardwareIcon extends StatelessWidget {
  const _SubsystemHardwareIcon({required this.storage, required this.accent});
  final bool storage;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(17),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          accent.withValues(alpha: 0.23),
          accent.withValues(alpha: 0.07),
        ],
      ),
      border: Border.all(color: accent.withValues(alpha: 0.25)),
    ),
    child: CustomPaint(painter: _SubsystemHardwarePainter(storage, accent)),
  );
}

class _SubsystemHardwarePainter extends CustomPainter {
  const _SubsystemHardwarePainter(this.storage, this.accent);
  final bool storage;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = accent.withValues(alpha: 0.18);
    if (storage) {
      final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(9, 6, 22, 28),
        const Radius.circular(4),
      );
      canvas.drawRRect(body, fill);
      canvas.drawRRect(body, line);
      for (final y in <double>[12, 20, 28]) {
        canvas.drawLine(Offset(5, y), Offset(9, y), line);
        canvas.drawLine(Offset(31, y), Offset(35, y), line);
      }
      for (final y in <double>[14, 20, 26]) {
        canvas.drawLine(Offset(15, y), Offset(25, y), line);
      }
    } else {
      final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 11, 34, 19),
        const Radius.circular(3),
      );
      canvas.drawRRect(body, fill);
      canvas.drawRRect(body, line);
      for (final x in <double>[8, 16, 24]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 16, 5, 8),
            const Radius.circular(1),
          ),
          line,
        );
      }
      for (final x in <double>[8, 14, 20, 26, 32]) {
        canvas.drawLine(Offset(x, 30), Offset(x, 34), line);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SubsystemHardwarePainter old) =>
      storage != old.storage || accent != old.accent;
}

class _SubsystemFrequencyCard extends StatefulWidget {
  const _SubsystemFrequencyCard({
    required this.subsystem,
    required this.title,
    required this.accent,
    required this.item,
    required this.enabled,
    required this.onApply,
    required this.onReset,
    super.key,
  });
  final String subsystem, title;
  final Color accent;
  final Map<String, dynamic> item;
  final bool enabled;
  final Future<bool> Function(int, int) onApply;
  final Future<bool> Function() onReset;
  @override
  State<_SubsystemFrequencyCard> createState() =>
      _SubsystemFrequencyCardState();
}

class _SubsystemFrequencyCardState extends State<_SubsystemFrequencyCard> {
  int _min = 0, _max = 0;
  bool _exact = false, _dirty = false, _sending = false;
  List<int> get _levels {
    final ceiling =
        (widget.item['oem_max_hz'] ?? widget.item['max_hz']) as num?;
    return ((widget.item['frequencies_hz'] as List?) ?? const <dynamic>[])
        .whereType<num>()
        .map((v) => v.toInt())
        .where((hz) => ceiling == null || hz <= ceiling)
        .toList();
  }

  int _nearest(int hz) {
    final levels = _levels;
    if (levels.isEmpty) return 0;
    return levels.reduce((a, b) => (a - hz).abs() <= (b - hz).abs() ? a : b);
  }

  void _sync() {
    if (_dirty || _sending || _levels.isEmpty) return;
    _min = _nearest(
      ((widget.item['target_min_hz'] ?? widget.item['min_hz']) as num?)
              ?.toInt() ??
          _levels.first,
    );
    _max = _nearest(
      ((widget.item['target_max_hz'] ?? widget.item['max_hz']) as num?)
              ?.toInt() ??
          _levels.last,
    );
    _exact = widget.item['controlled'] == true && _min == _max;
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _SubsystemFrequencyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  String _hz(dynamic hz) => hz is num
      ? '${(hz / 1000000).toStringAsFixed(hz % 1000000 == 0 ? 0 : 1)} MHz'
      : 'Unavailable';
  void _mode(bool exact) {
    if (_exact == exact) return;
    RodinHaptics.segment();
    setState(() {
      _exact = exact;
      if (exact) {
        _min = _max;
      } else if (_min == _max) {
        _min = _levels.first;
      }
      _dirty = true;
    });
  }

  Future<void> _apply() async {
    setState(() => _sending = true);
    final accepted = await widget.onApply(_min, _max);
    if (mounted)
      setState(() {
        _sending = false;
        if (accepted) _dirty = false;
      });
  }

  Future<void> _reset() async {
    RodinHaptics.tap();
    setState(() => _sending = true);
    final accepted = await widget.onReset();
    if (mounted)
      setState(() {
        _sending = false;
        if (accepted) {
          _dirty = false;
          _sync();
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final levels = _levels;
    final ready = levels.length > 1;
    final enabled =
        widget.enabled &&
        ready &&
        widget.item['supported'] == true &&
        !_sending;
    final maxIndex = ready ? levels.length - 1 : 1;
    final minIndex = ready
        ? levels.indexOf(_nearest(_min)).clamp(0, maxIndex)
        : 0;
    final upperIndex = ready
        ? levels.indexOf(_nearest(_max)).clamp(minIndex, maxIndex)
        : 1;
    final accent = widget.accent;
    final colors = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Frequency control',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusPill(
                label: _sending
                    ? 'APPLYING'
                    : _dirty
                    ? 'EDITING'
                    : widget.item['controlled'] != true
                    ? 'OEM'
                    : _min == _max
                    ? 'LOCKED'
                    : 'RANGE',
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _CpuFrequencyMetric(
                    label: widget.subsystem == 'memory'
                        ? 'REPORTED CURRENT'
                        : 'CURRENT',
                    value: _hz(widget.item['driver_hz']),
                    accent: accent,
                  ),
                ),
                Container(
                  width: 1,
                  height: 35,
                  color: colors.outline.withValues(alpha: 0.28),
                ),
                Expanded(
                  child: _CpuFrequencyMetric(
                    label: 'LIVE LIMITS',
                    value:
                        '${_hz(widget.item['min_hz'])} – ${_hz(widget.item['max_hz'])}',
                    accent: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              Text(
                'Live governor: ${widget.item['governor'] ?? 'Unavailable'}',
                style: TextStyle(
                  fontSize: 10.8,
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                '${levels.length} supported clocks',
                style: TextStyle(
                  fontSize: 10.2,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _CpuModeButton(
                  label: 'Dynamic Range',
                  icon: Icons.swap_horiz_rounded,
                  selected: !_exact,
                  accent: accent,
                  enabled: enabled,
                  onTap: () => _mode(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CpuModeButton(
                  label: 'Exact Lock',
                  icon: Icons.lock_rounded,
                  selected: _exact,
                  accent: accent,
                  enabled: enabled,
                  onTap: () => _mode(true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: RodinInteractionSettings.motionDuration(220),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: RodinInteractionSettings.motionDuration(180),
              child: !ready
                  ? const Padding(
                      key: ValueKey('unavailable'),
                      padding: EdgeInsets.all(16),
                      child: Text('No supported frequency table available'),
                    )
                  : _exact
                  ? Column(
                      key: const ValueKey('exact'),
                      children: <Widget>[
                        _CpuRangeLabels(
                          leftLabel: 'LOCK TARGET',
                          leftValue: _hz(_max),
                          rightLabel: 'MIN = MAX',
                          rightValue: _hz(_max),
                          accent: accent,
                        ),
                        Slider(
                          key: ValueKey('frequency-${widget.subsystem}'),
                          value: upperIndex.toDouble(),
                          min: 0,
                          max: maxIndex.toDouble(),
                          divisions: maxIndex,
                          activeColor: accent,
                          label: _hz(_max),
                          onChangeStart: enabled
                              ? (_) => RodinHaptics.segment()
                              : null,
                          onChanged: enabled
                              ? (value) {
                                  final hz = levels[value.round()];
                                  if (_max == hz) return;
                                  setState(() {
                                    _min = hz;
                                    _max = hz;
                                    _dirty = true;
                                  });
                                  RodinHaptics.frequentSegment();
                                }
                              : null,
                          onChangeEnd: enabled
                              ? (_) => RodinHaptics.confirm()
                              : null,
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('range'),
                      children: <Widget>[
                        _CpuRangeLabels(
                          leftLabel: 'MINIMUM',
                          leftValue: _hz(_min),
                          rightLabel: 'MAXIMUM',
                          rightValue: _hz(_max),
                          accent: accent,
                        ),
                        RangeSlider(
                          key: ValueKey('range-${widget.subsystem}'),
                          values: RangeValues(
                            minIndex.toDouble(),
                            upperIndex.toDouble(),
                          ),
                          min: 0,
                          max: maxIndex.toDouble(),
                          divisions: maxIndex,
                          activeColor: accent,
                          labels: RangeLabels(_hz(_min), _hz(_max)),
                          onChangeStart: enabled
                              ? (_) => RodinHaptics.segment()
                              : null,
                          onChanged: enabled
                              ? (value) {
                                  final min = levels[value.start.round()],
                                      max = levels[value.end.round()];
                                  if (_min == min && _max == max) return;
                                  setState(() {
                                    _min = min;
                                    _max = max;
                                    _dirty = true;
                                  });
                                  RodinHaptics.frequentSegment();
                                }
                              : null,
                          onChangeEnd: enabled
                              ? (_) => RodinHaptics.confirm()
                              : null,
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.item['controlled'] != true
                ? 'OEM managed'
                : widget.item['verified'] == true
                ? 'Target verified'
                : 'Requested target · live limits differ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              TextButton.icon(
                onPressed:
                    widget.enabled &&
                        !_sending &&
                        widget.item['restore_pending'] == true
                    ? _reset
                    : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                label: const Text('OEM Reset'),
              ),
              FilledButton.tonalIcon(
                key: ValueKey('apply-${widget.subsystem}'),
                onPressed: enabled && _dirty ? _apply : null,
                icon: Icon(
                  _sending ? Icons.hourglass_top_rounded : Icons.check_rounded,
                  size: 17,
                ),
                label: Text(_sending ? 'Applying…' : 'Apply'),
              ),
            ],
          ),
          if (widget.subsystem == 'memory')
            Text(
              'DVFSRC reports a cached DRAM request, not independent physical RAM-clock telemetry.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: colors.onSurfaceVariant,
              ),
            ),
          if (widget.subsystem == 'storage' && levels.length == 2)
            Text(
              'This kernel exposes ${_hz(levels.first)} and ${_hz(levels.last)} only. Intermediate clocks are not supported.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: colors.onSurfaceVariant,
              ),
            ),
          if (widget.item['supported'] != true && widget.item['reason'] != null)
            Text('${widget.item['reason']}'),
        ],
      ),
    );
  }
}
