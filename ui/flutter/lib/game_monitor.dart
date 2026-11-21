part of 'main.dart';

class GameMonitorScreen extends StatefulWidget {
  const GameMonitorScreen({
    super.key,
    required this.onBack,
    this.configFile,
    this.loadApps,
  });
  final VoidCallback onBack;
  final File? configFile;
  final Future<List<Map<String, dynamic>>> Function()? loadApps;
  @override
  State<GameMonitorScreen> createState() => _GameMonitorScreenState();
}

class _GameMonitorScreenState extends State<GameMonitorScreen>
    with WidgetsBindingObserver {
  bool locked = false;
  bool dragging = false;
  double scale = 1;
  bool details = false;
  bool landscape = true;
  bool loaded = false;
  String? error;
  Map<String, bool> apps = {};
  Map<String, double> positions = {};
  File get file =>
      widget.configFile ??
      File('${Directory.systemTemp.parent.path}/files/game-monitor.json');
  String get orientation => landscape ? 'landscape' : 'portrait';
  double coord(String axis) =>
      positions['$orientation$axis'] ?? (axis == 'x' ? .03 : .05);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map;
        scale = ((data['scale'] as num?)?.toDouble() ?? 1).clamp(.75, 1.5);
        details = data['details'] == true;
        locked = data['locked'] == true;
        apps = Map<String, bool>.from(data['apps'] ?? {});
        positions = {
          for (final entry in (data['positions'] as Map? ?? {}).entries)
            entry.key as String: (entry.value as num).toDouble().clamp(0, 1),
        };
      }
      loaded = true;
    } catch (_) {
      error = 'Couldn’t read the saved overlay settings.';
    }
    if (mounted) setState(() {});
  }

  void _save() {
    try {
      final temp = File('${file.path}.tmp');
      file.parent.createSync(recursive: true);
      temp.writeAsStringSync(
        jsonEncode({
          'scale': scale,
          'details': details,
          'locked': locked,
          'apps': apps,
          'positions': positions,
        }),
      );
      temp.renameSync(file.path);
      error = null;
    } on FileSystemException {
      error = 'Couldn’t save the overlay settings.';
    }
    setState(() {});
  }

  Future<void> _choose() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _MonitorAppPicker(
        selected: apps.keys.where((k) => apps[k] == true).toSet(),
        load:
            widget.loadApps ??
            () async =>
                (await PerAppBackend.instance.command('GET app.list') as List)
                    .map((a) => Map<String, dynamic>.from(a as Map))
                    .toList(),
        onChange: (pkg, on) {
          if (on) {
            apps[pkg] = true;
          } else {
            apps.remove(pkg);
          }
          _save();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selected = apps.values.where((v) => v).length;
    return RodinScrollPage(
      children: [
        DetailHeader(title: 'Game Monitor', onBack: widget.onBack),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.open_with_rounded,
                    color: colors.primary,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Overlay position', style: text.titleMedium),
                  ),
                  Text('${(scale * 100).round()}%', style: text.labelMedium),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Sample readings · Drag to move. Pinch to resize.',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: landscape ? 480 : 125),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.outlineVariant,
                          colors.surfaceContainerHighest,
                          colors.outlineVariant,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: AspectRatio(
                        aspectRatio: landscape ? 2.17 : 1 / 2.17,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final chipWidth = math.min(
                              (details ? 115.0 : 64.0) * scale,
                              constraints.maxWidth,
                            );
                            final chipHeight = (details ? 44.0 : 28.0) * scale;
                            final dx = math.max(
                              0.0,
                              constraints.maxWidth - chipWidth,
                            );
                            final dy = math.max(
                              0.0,
                              constraints.maxHeight - chipHeight,
                            );
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _OverlayGestures(
                                enabled: loaded,
                                scale: scale,
                                onScale: (value) =>
                                    setState(() => scale = value),
                                onMove: (delta) => setState(() {
                                  dragging = true;
                                  if (dx > 0)
                                    positions['${orientation}x'] =
                                        (coord('x') + delta.dx / dx).clamp(
                                          0,
                                          1,
                                        );
                                  if (dy > 0)
                                    positions['${orientation}y'] =
                                        (coord('y') + delta.dy / dy).clamp(
                                          0,
                                          1,
                                        );
                                }),
                                onEnd: () {
                                  dragging = false;
                                  _save();
                                },
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _FrostedPreview(
                                          colors.brightness,
                                        ),
                                      ),
                                    ),
                                    if (dragging) ...[
                                      Positioned(
                                        left: dx * coord('x') + chipWidth / 2,
                                        top: 0,
                                        bottom: 0,
                                        width: 1,
                                        child: ColoredBox(
                                          color: Colors.white.withValues(
                                            alpha: .5,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: dy * coord('y') + chipHeight / 2,
                                        left: 0,
                                        right: 0,
                                        height: 1,
                                        child: ColoredBox(
                                          color: Colors.white.withValues(
                                            alpha: .5,
                                          ),
                                        ),
                                      ),
                                    ],
                                    Positioned(
                                      left: dx * coord('x'),
                                      top: dy * coord('y'),
                                      width: chipWidth,
                                      height: chipHeight,
                                      child: Semantics(
                                        label: 'Overlay position preview',
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Color(0x61334551),
                                                Color(0x59212C37),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              7 * scale,
                                            ),
                                            border: Border.all(
                                              color: const Color(0x47FFFFFF),
                                              width: .6,
                                            ),
                                          ),
                                          child: DefaultTextStyle.merge(
                                            style: const TextStyle(
                                              shadows: [
                                                Shadow(
                                                  color: Color(0xdd000000),
                                                  blurRadius: 1.5,
                                                  offset: Offset(0, .75),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 2,
                                                  ),
                                              child: FittedBox(
                                                fit: BoxFit.contain,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .baseline,
                                                      textBaseline: TextBaseline
                                                          .alphabetic,
                                                      children: [
                                                        const Text(
                                                          '60',
                                                          style: TextStyle(
                                                            fontSize: 17,
                                                            height: 1.1,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        const Text(
                                                          'FPS',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            letterSpacing: .4,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: Color(
                                                              0xffa9dfd2,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (details)
                                                      const Text(
                                                        'CPU 32%   GPU 68%',
                                                        style: TextStyle(
                                                          fontFamily:
                                                              'monospace',
                                                          fontSize: 10,
                                                          height: 1.4,
                                                          color: Color(
                                                            0xffdce6e6,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Landscape'),
                      icon: Icon(Icons.stay_current_landscape_rounded),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Portrait'),
                      icon: Icon(Icons.stay_current_portrait_rounded),
                    ),
                  ],
                  selected: {landscape},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => landscape = v.first),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: locked,
                onChanged: loaded
                    ? (v) {
                        locked = v;
                        _save();
                      }
                    : null,
                title: const Text('Lock overlay'),
                subtitle: Text(
                  locked
                      ? 'Touches pass through the counter'
                      : 'Drag to move. Hold the counter, lift, then pinch anywhere to resize.',
                ),
              ),
              const _HubControlDivider(),
              SwitchListTile.adaptive(
                value: details,
                onChanged: loaded
                    ? (v) {
                        details = v;
                        _save();
                      }
                    : null,
                title: const Text('Detailed view'),
                subtitle: const Text('Device CPU and GPU usage below FPS'),
              ),
              const _HubControlDivider(),
              _HubControlRow(
                title: 'Selected apps',
                subtitle: selected == 0
                    ? 'Choose where the counter appears'
                    : '$selected selected',
                icon: Icons.sports_esports_rounded,
                accent: colors.primary,
                onTap: () {
                  if (loaded) _choose();
                },
              ),
              const _HubControlDivider(),
              _HubControlRow(
                title: 'Overlay access',
                subtitle: 'Enable Rodin Game Monitor in Accessibility',
                icon: Icons.layers_outlined,
                accent: colors.secondary,
                onTap: () {
                  ffi.DynamicLibrary.open(
                    'librodin_essential_host.so',
                  ).lookupFunction<ffi.Int32 Function(), int Function()>(
                    'rodin_host_open_game_monitor_access',
                  )();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.all(10),
          child: _HubControlRow(
            title: 'Performance history',
            subtitle: 'Session FPS, stability and battery temperature',
            icon: Icons.timeline_rounded,
            accent: colors.primary,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _MonitorHistory(
                directory: Directory('${file.parent.path}/game-history'),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
      ],
    );
  }
}

class _MonitorAppPicker extends StatefulWidget {
  const _MonitorAppPicker({
    required this.selected,
    required this.load,
    required this.onChange,
  });
  final Set<String> selected;
  final Future<List<Map<String, dynamic>>> Function() load;
  final void Function(String, bool) onChange;
  @override
  State<_MonitorAppPicker> createState() => _MonitorAppPickerState();
}

class _MonitorAppPickerState extends State<_MonitorAppPicker> {
  late Future<List<Map<String, dynamic>>> apps;
  String query = '';
  bool system = false;
  @override
  void initState() {
    super.initState();
    apps = widget.load();
  }

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .85,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected apps', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => query = v.toLowerCase().trim()),
            decoration: const InputDecoration(
              hintText: 'Search installed apps',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show system apps'),
            value: system,
            onChanged: (v) => setState(() => system = v),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: apps,
              builder: (context, snap) {
                if (snap.hasError)
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() => apps = widget.load()),
                      child: const Text('Retry app list'),
                    ),
                  );
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final list =
                    snap.data!
                        .where(
                          (a) =>
                              (system ||
                                  a['system'] != true ||
                                  widget.selected.contains(a['package'])) &&
                              '${a['label']} ${a['package']}'
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .toList()
                      ..sort(
                        (a, b) => '${a['label']}'.toLowerCase().compareTo(
                          '${b['label']}'.toLowerCase(),
                        ),
                      );
                if (list.isEmpty)
                  return const Center(child: Text('No matching apps'));
                final selected = list
                    .where((app) => widget.selected.contains(app['package']))
                    .toList();
                final available = list
                    .where((app) => !widget.selected.contains(app['package']))
                    .toList();
                final rows = <Object>[
                  if (selected.isNotEmpty) 'Monitoring · ${selected.length}',
                  ...selected,
                  if (available.isNotEmpty) 'Available · ${available.length}',
                  ...available,
                ];
                return ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    if (row is String)
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
                        child: Text(
                          row,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      );
                    final app = row as Map<String, dynamic>,
                        pkg = app['package'] as String;
                    return CheckboxListTile(
                      secondary: _MonitorIcon(key: ValueKey(pkg), package: pkg),
                      contentPadding: EdgeInsets.zero,
                      title: Text('${app['label'] ?? pkg}'),
                      subtitle: Text(
                        pkg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      value: widget.selected.contains(pkg),
                      onChanged: (v) {
                        final on = v == true;
                        setState(() {
                          if (on) {
                            widget.selected.add(pkg);
                          } else {
                            widget.selected.remove(pkg);
                          }
                        });
                        widget.onChange(pkg, on);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _OverlayGestures extends StatefulWidget {
  const _OverlayGestures({
    required this.enabled,
    required this.scale,
    required this.onScale,
    required this.onMove,
    required this.onEnd,
    required this.child,
  });
  final bool enabled;
  final double scale;
  final ValueChanged<double> onScale;
  final ValueChanged<Offset> onMove;
  final VoidCallback onEnd;
  final Widget child;
  @override
  State<_OverlayGestures> createState() => _OverlayGesturesState();
}

class _OverlayGesturesState extends State<_OverlayGestures> {
  final points = <int, Offset>{};
  double span = 0, base = 1;
  bool pinched = false, changed = false;
  double get distance => (points.values.first - points.values.last).distance;
  void finish(int id) {
    points.remove(id);
    if (points.length == 2) {
      span = distance;
      base = widget.scale;
    }
    if (points.isEmpty) {
      if (changed) widget.onEnd();
      pinched = false;
      changed = false;
    }
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      EagerGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (!widget.enabled) return;
        points[e.pointer] = e.position;
        if (points.length == 2) {
          pinched = true;
          span = distance;
          base = widget.scale;
        }
      },
      onPointerMove: (e) {
        if (!points.containsKey(e.pointer)) return;
        points[e.pointer] = e.position;
        if (points.length == 2 && span > 0) {
          changed = true;
          widget.onScale((base * distance / span).clamp(.75, 1.5));
        } else if (points.length == 1 && !pinched) {
          changed = true;
          widget.onMove(e.delta);
        }
      },
      onPointerUp: (e) => finish(e.pointer),
      onPointerCancel: (e) => finish(e.pointer),
      child: widget.child,
    ),
  );
}

class _FrostedPreview extends CustomPainter {
  const _FrostedPreview(this.brightness);
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = brightness == Brightness.dark;
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xff25364b), Color(0xff183e47), Color(0xff272b45)]
            : const [Color(0xffd8e6ee), Color(0xffaccdcf), Color(0xffb8bfd9)],
      ).createShader(rect);
    canvas.drawRect(rect, base);
    final radius = size.shortestSide;
    void glow(Offset center, double scale, Color color) {
      final area = Rect.fromCircle(center: center, radius: radius * scale);
      canvas.drawOval(
        area,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withAlpha(0)],
          ).createShader(area),
      );
    }

    glow(
      Offset(size.width * .25, size.height * .25),
      .95,
      const Color(0x8876d8bc),
    );
    glow(
      Offset(size.width * .88, size.height * .76),
      .85,
      const Color(0x887787d0),
    );
    final fold = Path()
      ..moveTo(-size.width * .1, size.height * .88)
      ..cubicTo(
        size.width * .34,
        size.height * .92,
        size.width * .46,
        size.height * .05,
        size.width * 1.1,
        size.height * .16,
      );
    canvas.drawPath(
      fold,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .18
        ..color = Colors.white.withAlpha(dark ? 46 : 115)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .09),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(.6), const Radius.circular(16)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withAlpha(dark ? 48 : 136),
    );
  }

  @override
  bool shouldRepaint(_FrostedPreview old) => old.brightness != brightness;
}

class _MonitorHistory extends StatefulWidget {
  const _MonitorHistory({required this.directory});
  final Directory directory;
  @override
  State<_MonitorHistory> createState() => _MonitorHistoryState();
}

class _MonitorHistoryState extends State<_MonitorHistory> {
  late final Future<List<(File, List)>> sessions = _index();
  Future<List<(File, List)>> _index() async {
    if (!await widget.directory.exists()) return [];
    final files = await widget.directory
        .list()
        .where((e) => e is File && e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    final result = <(File, List)>[];
    for (final f in files) {
      try {
        final line = await f
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        final row = jsonDecode(line);
        if (row is List && row.length >= 4 && row.first == 'start')
          result.add((f, row));
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on StateError {
        continue;
      }
    }
    return result;
  }

  String? package;
  File? selected;
  Future<_GameSummary>? summary;
  String stamp(List row) {
    final date = DateTime.fromMillisecondsSinceEpoch(row[1] as int);
    return '${MaterialLocalizations.of(context).formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
  }

  void open((File, List) entry) => setState(() {
    package = entry.$2[2] as String;
    selected = entry.$1;
    summary = _GameSummary.read(entry.$1);
  });
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .9,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: FutureBuilder<List<(File, List)>>(
        future: sessions,
        builder: (context, snap) {
          if (snap.hasError)
            return const Center(child: Text('Couldn’t read session history.'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final groups = <String, List<(File, List)>>{};
          for (final entry in snap.data!) {
            (groups[entry.$2[2] as String] ??= []).add(entry);
          }
          final group = groups[package];
          return ListView(
            key: ValueKey(package),
            children: [
              if (group == null) ...[
                Text(
                  'Performance history',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  groups.isEmpty
                      ? 'Play a selected app to record your first session.'
                      : 'Last 50 sessions, grouped by app',
                ),
                const SizedBox(height: 14),
                for (final g in groups.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: _MonitorIcon(package: g.key),
                        title: Text(g.value.first.$2[3] as String),
                        subtitle: Text(
                          '${g.value.length} ${g.value.length == 1 ? "session" : "sessions"} · ${stamp(g.value.first.$2)}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => open(g.value.first),
                      ),
                    ),
                  ),
              ] else ...[
                Row(
                  children: [
                    IconButton(
                      tooltip: 'All apps',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => setState(() => package = null),
                    ),
                    _MonitorIcon(package: package!),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        group.first.$2[3] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<File>(
                  key: ValueKey(selected!.path),
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Recorded session',
                  ),
                  items: [
                    for (final e in group)
                      DropdownMenuItem(value: e.$1, child: Text(stamp(e.$2))),
                  ],
                  onChanged: (f) {
                    if (f != null) open(group.firstWhere((e) => e.$1 == f));
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<_GameSummary>(
                  key: ValueKey(selected!.path),
                  future: summary,
                  builder: (context, s) {
                    if (s.hasError)
                      return const Text('Couldn’t read this session.');
                    if (!s.hasData) return const LinearProgressIndicator();
                    return s.data!.view(context);
                  },
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _MonitorIcon extends StatelessWidget {
  const _MonitorIcon({super.key, required this.package});
  final String package;
  static final _cache = <String, Future<Uint8List?>>{};
  static final _pending = <String, Completer<Uint8List?>>{};
  static Timer? _timer;
  static Future<Uint8List?> _load(String pkg) {
    final existing = _cache[pkg];
    if (existing != null) return existing;
    final c = Completer<Uint8List?>();
    _pending[pkg] = c;
    _cache[pkg] = c.future;
    _timer ??= Timer(Duration.zero, () async {
      _timer = null;
      final pending = Map.of(_pending);
      _pending.clear();
      final keys = pending.keys.toList();
      for (int i = 0; i < keys.length; i += 24) {
        final batch = keys.skip(i).take(24).toList();
        Map<String, Uint8List> icons = {};
        try {
          icons = await PerAppBackend.instance.icons(batch);
        } catch (_) {}
        for (final key in batch) {
          pending[key]!.complete(icons[key]);
          if (icons[key] == null) _cache.remove(key);
        }
      }
      while (_cache.length > 256) {
        _cache.remove(_cache.keys.first);
      }
    });
    return c.future;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: FutureBuilder<Uint8List?>(
      future: Platform.isAndroid ? _load(package) : null,
      builder: (context, s) => s.data == null
          ? Icon(
              Icons.apps_rounded,
              color: Theme.of(context).colorScheme.primary,
            )
          : Image.memory(s.data!, fit: BoxFit.contain),
    ),
  );
}

class _GameSummary {
  final fps = <Offset>[],
      temperatures = <Offset>[],
      cpu = <Offset>[],
      gpu = <Offset>[];
  double duration = 0;
  static Future<_GameSummary> read(File file) async {
    final result = _GameSummary();
    await for (final line
        in file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      dynamic row;
      try {
        row = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (row is! List || row.length < 2 || row[1] is! num) continue;
      final seconds = (row[1] as num).toDouble() / 1000;
      if (row[0] == 'end' || row[0] == 'sample')
        result.duration = math.max(result.duration, seconds);
      if (row[0] != 'sample' || row.length < 4) continue;
      result.fps.add(
        Offset(seconds, (row[2] as num?)?.toDouble() ?? double.nan),
      );
      for (final metric in [(4, result.cpu), (5, result.gpu)]) {
        final value = row.length > metric.$1 ? row[metric.$1] : null;
        metric.$2.add(
          Offset(
            seconds,
            value is num && value >= 0 && value <= 100
                ? value.toDouble()
                : double.nan,
          ),
        );
      }
      result.temperatures.add(
        Offset(
          seconds,
          row[3] == null ? double.nan : (row[3] as num).toDouble() / 10,
        ),
      );
    }
    return result;
  }

  double _average(List<Offset> points) {
    final valid = points.where((p) => p.dy.isFinite);
    return valid.isEmpty
        ? double.nan
        : valid.fold<double>(0, (s, p) => s + p.dy) / valid.length;
  }

  Widget view(BuildContext context) {
    final f = fps.map((v) => v.dy).where((v) => v.isFinite).toList();
    final t = temperatures.map((v) => v.dy).where((v) => v.isFinite).toList();
    final avg = f.isEmpty ? double.nan : f.reduce((a, b) => a + b) / f.length;
    final deviation = f.isEmpty
        ? double.nan
        : math.sqrt(
            f.fold<double>(0, (s, v) => s + (v - avg) * (v - avg)) / f.length,
          );
    String number(double v, String unit) =>
        v.isFinite ? '${v.toStringAsFixed(1)}$unit' : '—';
    final metrics = {
      'Average FPS': number(avg, ''),
      'Max FPS': number(f.isEmpty ? double.nan : f.reduce(math.max), ''),
      'Min FPS': number(f.isEmpty ? double.nan : f.reduce(math.min), ''),
      'FPS stability': number(
        avg > 0 && f.length >= 2
            ? (100 * (1 - deviation / avg)).clamp(0, 100)
            : double.nan,
        '%',
      ),
      for (final metric in [('Avg device CPU', cpu), ('Avg device GPU', gpu)])
        metric.$1: number(_average(metric.$2), '%'),
      'Peak battery': number(
        t.isEmpty ? double.nan : t.reduce(math.max),
        ' °C',
      ),
      'Rise from start': number(
        t.isEmpty ? double.nan : t.reduce(math.max) - t.first,
        ' °C',
      ),
    };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session · ${duration.toInt() ~/ 60}m ${duration.toInt() % 60}s',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              for (final m in metrics.entries)
                SizedBox(
                  width: 116,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.key, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        m.value,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SessionChart(summary: this),
          Text('FPS stability measures how much the sampled FPS varied.'),
        ],
      ),
    );
  }
}

class _SessionChart extends StatefulWidget {
  const _SessionChart({required this.summary});
  final _GameSummary summary;
  @override
  State<_SessionChart> createState() => _SessionChartState();
}

class _SessionChartState extends State<_SessionChart> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.summary,
        colors = Theme.of(context).colorScheme,
        theme = Theme.of(context).textTheme;
    final options = [
      ('FPS', 'FPS', s.fps, colors.primary),
      ('CPU', 'Device CPU %', s.cpu, colors.secondary),
      ('GPU', 'Device GPU %', s.gpu, colors.tertiary),
      ('Battery', 'Battery °C', s.temperatures, colors.primary),
    ];
    final metric = options[selected];
    final values = metric.$3.where((p) => p.dy.isFinite).map((p) => p.dy);
    final bounds = values.isEmpty
        ? ''
        : '${values.reduce(math.min).toStringAsFixed(1)} – ${values.reduce(math.max).toStringAsFixed(1)}';
    String time(double seconds) =>
        '${seconds.toInt() ~/ 60}:${(seconds.toInt() % 60).toString().padLeft(2, "0")}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Session timeline', style: theme.titleMedium),
        Wrap(
          spacing: 6,
          children: [
            for (int i = 0; i < options.length; i++)
              ChoiceChip(
                label: Text(options[i].$1),
                selected: i == selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => selected = i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(metric.$2, style: theme.labelLarge)),
            Text(bounds, style: theme.labelMedium),
          ],
        ),
        if (values.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text('No readings available'),
          )
        else ...[
          RepaintBoundary(
            child: SizedBox(
              width: double.infinity,
              height: 108,
              child: CustomPaint(
                painter: _SessionTrace(metric.$3, s.duration, metric.$4),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00', style: theme.labelSmall),
              Text(time(s.duration), style: theme.labelSmall),
            ],
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SessionTrace extends CustomPainter {
  _SessionTrace(this.data, this.duration, this.color);
  final List<Offset> data;
  final double duration;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final valid = data.where((p) => p.dy.isFinite);
    if (valid.isEmpty) return;
    final low = valid.map((p) => p.dy).reduce(math.min),
        high = valid.map((p) => p.dy).reduce(math.max);
    final grid = Paint()
      ..color = color.withValues(alpha: .18)
      ..strokeWidth = 1;
    for (final y in [4.0, size.height / 2, size.height - 4]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    var connected = false;
    double last = 0;
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final point in data) {
      if (!point.dy.isFinite) {
        connected = false;
        continue;
      }
      final x = point.dx / math.max(duration, 1) * size.width;
      final y = high == low
          ? size.height / 2
          : 4 + (high - point.dy) / (high - low) * (size.height - 8);
      if (!connected || point.dx - last > 3) {
        path.moveTo(x, y);
        canvas.drawCircle(Offset(x, y), 1, Paint()..color = color);
      } else {
        path.lineTo(x, y);
      }
      connected = true;
      last = point.dx;
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_SessionTrace old) =>
      old.data != data || old.color != color || old.duration != duration;
}
