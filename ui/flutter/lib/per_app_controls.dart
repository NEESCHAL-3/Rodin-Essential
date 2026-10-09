part of 'main.dart';

Future<bool> _confirmAppProfileReset(
  BuildContext context, {
  required bool all,
}) async {
  final appearance = RodinAppearanceScope.of(context);
  return await showRodinDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          final ColorScheme colors = Theme.of(context).colorScheme;
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 360,
                maxHeight: (MediaQuery.sizeOf(context).height - 80).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: RodinAppearanceScope(
                config: appearance,
                child: SurfaceCard(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.restart_alt_rounded,
                          color: colors.primary,
                          size: 26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          all ? 'Reset all app profiles?' : 'Reset this app?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          all
                              ? 'Remove per-app selections and return to your global setup. Your global settings stay unchanged.'
                              : 'Remove this app’s selections and follow your global setup again.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 22),
                        OverflowBar(
                          spacing: 10,
                          overflowSpacing: 8,
                          alignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                RodinBackend.instance.haptic(1);
                                Navigator.pop(context, false);
                              },
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () {
                                RodinBackend.instance.haptic(1);
                                Navigator.pop(context, true);
                              },
                              child: Text(all ? 'Reset profiles' : 'Reset app'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ) ??
      false;
}

class PerAppControlsScreen extends StatefulWidget {
  const PerAppControlsScreen({required this.onBack, this.exchange, super.key});
  final VoidCallback onBack;
  final Future<dynamic> Function(String)? exchange;
  @override
  State<PerAppControlsScreen> createState() => _PerAppControlsScreenState();
}

class _PerAppControlsScreenState extends State<PerAppControlsScreen> {
  // Cache presentation only; live ownership and saved profiles stay daemon-owned.
  static List<Map<String, dynamic>> _cachedApps = <Map<String, dynamic>>[];
  static final Map<String, Uint8List> _cachedIcons = <String, Uint8List>{};
  final PerAppBackend _backend = PerAppBackend.instance;
  final TextEditingController _search = TextEditingController();
  Map<String, dynamic>? _state;
  Map<String, dynamic> _caps = <String, dynamic>{};
  List<Map<String, dynamic>> _apps = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selected;
  String? _error;
  bool _busy = false;
  bool _polling = false;
  int _limit = 40;
  bool _showSystem = false;
  bool _forward = true;
  bool _iconsLoading = false;
  final Map<String, Uint8List> _icons = <String, Uint8List>{};
  final Set<String> _iconAttempts = <String>{};
  Timer? _iconTimer;
  Timer? _timer;
  Future<dynamic> _command(String command) =>
      widget.exchange?.call(command) ?? _backend.command(command);

  @override
  void initState() {
    super.initState();
    if (widget.exchange == null) {
      _apps = List<Map<String, dynamic>>.from(_cachedApps);
      _icons.addAll(_cachedIcons);
      _iconAttempts.addAll(_icons.keys);
    }
    RodinNestedBackController.attach(
      this,
      _consumeBack,
      canPreview: () => _selected != null,
    );
    _search.addListener(() {
      if (mounted) setState(() => _limit = 40);
      _scheduleIcons();
    });
    unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshStatus(),
    );
  }

  @override
  void dispose() {
    RodinNestedBackController.detach(this);
    _timer?.cancel();
    _iconTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _consumeBack() {
    if (_selected == null) return false;
    setState(() {
      _forward = false;
      _selected = null;
      _error = null;
    });
    return true;
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dynamic apps = await _command('GET app.list');
      if (!mounted) return;
      setState(() {
        _apps =
            (apps as List)
                .map((dynamic app) => Map<String, dynamic>.from(app as Map))
                .toList()
              ..sort(
                (Map<String, dynamic> a, Map<String, dynamic> b) =>
                    '${a['label'] ?? a['package']}'.toLowerCase().compareTo(
                      '${b['label'] ?? b['package']}'.toLowerCase(),
                    ),
              );
      });
      if (widget.exchange == null)
        _cachedApps = List<Map<String, dynamic>>.from(_apps);
      _scheduleIcons();
      final dynamic state = await _command('GET app.controls');
      final dynamic caps = await _command('GET app.capabilities');
      if (!mounted) return;
      setState(() {
        _state = Map<String, dynamic>.from(state as Map);
        _caps = Map<String, dynamic>.from(caps as Map);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _filteredApps {
    final String query = _search.text.trim().toLowerCase();
    return _apps
        .where(
          (Map<String, dynamic> app) =>
              (_showSystem || app['system'] != true) &&
              '${app['label'] ?? ''} ${app['package']}'.toLowerCase().contains(
                query,
              ),
        )
        .toList();
  }

  void _scheduleIcons() {
    if (widget.exchange != null) return; // Mock transport has no Android JNI.
    _iconTimer?.cancel();
    _iconTimer = Timer(const Duration(milliseconds: 100), _loadIcons);
  }

  Future<void> _loadIcons() async {
    if (!mounted || _iconsLoading) return;
    final List<String> packages = _filteredApps
        .take(_limit)
        .map((Map<String, dynamic> app) => app['package'] as String)
        .where((String package) => !_iconAttempts.contains(package))
        .take(40)
        .toList();
    if (packages.isEmpty) return;
    _iconsLoading = true;
    _iconAttempts.addAll(packages);
    try {
      final Map<String, Uint8List> icons = await _backend.icons(packages);
      _cachedIcons.addAll(icons);
      while (_cachedIcons.length > 512) {
        _cachedIcons.remove(_cachedIcons.keys.first);
      }
      if (mounted) setState(() => _icons.addAll(icons));
    } catch (_) {
      // Removed/inaccessible packages retain their fallback, not a broken list.
    } finally {
      _iconsLoading = false;
      if (mounted) _scheduleIcons();
    }
  }

  Future<void> _refreshStatus() async {
    if (_busy || _polling || _state == null) return;
    _polling = true;
    try {
      final dynamic state = await _command('GET app.controls');
      if (mounted)
        setState(() => _state = Map<String, dynamic>.from(state as Map));
    } catch (_) {
      /* Keep the last acknowledged state; don't manufacture a switch. */
    } finally {
      _polling = false;
    }
  }

  Future<bool> _write(String command, {bool background = false}) async {
    if (_busy) return false;
    if (mounted)
      setState(() {
        _busy = !background;
        _error = null;
      });
    if (!background) RodinBackend.instance.haptic(1);
    try {
      final dynamic reply = await _command(command);
      if (mounted)
        setState(() => _state = Map<String, dynamic>.from(reply as Map));
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _profile(Map<String, dynamic> app) {
    final List<dynamic> profiles =
        (_state?['config'] as Map?)?['profiles'] as List? ?? <dynamic>[];
    for (final dynamic item in profiles) {
      if (item['user'] == app['user'] && item['package'] == app['package']) {
        return Map<String, dynamic>.from(item['profile'] as Map);
      }
    }
    return <String, dynamic>{'enabled': true};
  }

  Future<bool> _confirmReset() async {
    return _confirmAppProfileReset(context, all: true);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification event) {
        if (_selected == null &&
            event.metrics.extentAfter < 500 &&
            _filteredApps.length > _limit &&
            event is ScrollUpdateNotification) {
          setState(() => _limit += 40);
          _scheduleIcons();
        }
        return false;
      },
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : RodinInteractionSettings.motionDuration(320),
        reverseDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : RodinInteractionSettings.motionDuration(220),
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
            rodinDetailLayout(
              currentChild,
              previousChildren,
              forward: _forward,
            ),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return RodinDetailTransition(
            animation: animation,
            previewThrough: true,
            forward: _forward,
            active:
                child.key ==
                ValueKey<String>(
                  _selected == null
                      ? 'apps'
                      : '${_selected!['user']}:${_selected!['package']}',
                ),
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey<String>(
            _selected == null
                ? 'apps'
                : '${_selected!['user']}:${_selected!['package']}',
          ),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final Map<String, dynamic>? selected = _selected;
    if (selected != null) {
      return RodinPredictivePlane(
        nested: true,
        destination: _buildAppList(context),
        child: _PerAppEditor(
          key: ValueKey<String>('${selected['user']}:${selected['package']}'),
          app: selected,
          icon: _icons[selected['package']],
          initial: _profile(selected),
          overridesEnabled: (_state?['config'] as Map?)?['enabled'] == true,
          serviceEnabled: _state?['serviceEnabled'] != false,
          active:
              (_state?['owner'] as Map?)?['package'] == selected['package'] &&
              (_state?['owner'] as Map?)?['user'] == selected['user'] &&
              _state?['error'] == null,
          onEnableOverrides: () => _write('SET app.enabled 1'),
          capabilities: _caps,
          busy: _busy,
          error: _error ?? _state?['error']?.toString(),
          onBack: _consumeBack,
          onSave: (Map<String, dynamic> profile) => _write(
            'SET app.profile ${jsonEncode(<String, dynamic>{'user': selected['user'], 'package': selected['package'], 'profile': profile})}',
            background: true,
          ),
          onReset: () => _write(
            'ACTION app.reset ${selected['user']} ${selected['package']}',
          ),
        ),
      );
    }
    return RodinPredictivePlane(nested: true, child: _buildAppList(context));
  }

  Widget _buildAppList(BuildContext context) {
    final bool enabled = (_state?['config'] as Map?)?['enabled'] == true;
    final List<Map<String, dynamic>> filtered = _filteredApps;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? backendError = _state?['error']?.toString();
    final String? owner = (_state?['owner'] as Map?)?['package']?.toString();
    return RodinScrollPage(
      key: const PageStorageKey<String>('per-app-installed-list'),
      children: <Widget>[
        DetailHeader(
          title: 'Per-App Controls',
          onBack: widget.onBack,
          trailing: IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Set individual touch, refresh rate, CPU and GPU controls for each app.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        HeroCard(
          icon: Icons.tune_rounded,
          accent: colors.primary,
          title: enabled ? 'Individual control' : 'Your global setup',
          subtitle: enabled
              ? 'Saved app profiles take over only while their app is in focus.'
              : 'Per-App Controls starts off. Set profiles first, then enable when ready.',
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Per-app overrides',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'Off means no app overrides. Your global setup stays saved.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
                value: enabled,
                onChanged: _state == null || _busy
                    ? null
                    : (bool value) =>
                          _write('SET app.enabled ${value ? 1 : 0}'),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    owner == null ? Icons.public_rounded : Icons.apps_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _state?['serviceEnabled'] == false
                          ? 'Rodin Essential is disabled. No app profile is applied.'
                          : owner != null
                          ? 'Active app: $owner'
                          : 'Your global controls are active.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null || backendError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error ?? backendError!,
              style: TextStyle(color: colors.error),
            ),
          ),
        const SizedBox(height: 16),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search installed apps',
              prefixIcon: Icon(Icons.search_rounded),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Show system apps',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          value: _showSystem,
          onChanged: (bool value) {
            RodinBackend.instance.haptic(1);
            setState(() {
              _showSystem = value;
              _limit = 40;
            });
            _scheduleIcons();
          },
        ),
        Text(
          '${filtered.length} apps · ${_showSystem ? 'Third-party and system' : 'Third-party only'}',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (filtered.isNotEmpty)
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: filtered.take(_limit).map((Map<String, dynamic> app) {
                final Map<String, dynamic> profile = _profile(app);
                final bool configured = profile.keys.any(
                  (String key) => key != 'enabled',
                );
                return Column(
                  children: <Widget>[
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      leading: _icons[app['package']] != null
                          ? Image.memory(
                              _icons[app['package']]!,
                              width: 38,
                              height: 38,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            )
                          : Icon(
                              app['system'] == true
                                  ? Icons.android_rounded
                                  : Icons.apps_rounded,
                              color: configured
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                      title: Text(
                        '${app['label'] ?? app['package']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        configured
                            ? profile['enabled'] == true
                                  ? enabled
                                        ? 'Profile ready'
                                        : 'Saved · overrides off'
                                  : 'Profile disabled'
                            : app['system'] == true
                            ? app['launchable'] == false
                                  ? 'System component · no launcher entry'
                                  : 'System app · Follow global'
                            : 'Follow global',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                      ),
                      onTap: _busy
                          ? null
                          : () {
                              RodinBackend.instance.haptic(1);
                              setState(() {
                                _forward = true;
                                _selected = app;
                                _error = null;
                              });
                            },
                    ),
                    if (app != filtered.take(_limit).last)
                      Padding(
                        padding: const EdgeInsets.only(left: 62),
                        child: Divider(
                          height: 1,
                          thickness: 0.8,
                          color: RodinSurfaceLines.divider(colors),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        if (_apps.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No installed-app list is available. Tap refresh to retry.',
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || _state == null
              ? null
              : () async {
                  if (await _confirmReset())
                    await _write('ACTION app.reset_all');
                },
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Reset all app profiles'),
        ),
      ],
    );
  }
}

class _PerAppEditor extends StatefulWidget {
  const _PerAppEditor({
    super.key,
    required this.app,
    this.icon,
    required this.initial,
    required this.capabilities,
    required this.busy,
    required this.error,
    required this.onBack,
    required this.onSave,
    required this.onReset,
    required this.overridesEnabled,
    required this.serviceEnabled,
    required this.active,
    required this.onEnableOverrides,
  });
  final Map<String, dynamic> app, initial, capabilities;
  final Uint8List? icon;
  final bool busy;
  final String? error;
  final VoidCallback onBack;
  final Future<bool> Function(Map<String, dynamic>) onSave;
  final Future<bool> Function() onReset;
  final bool overridesEnabled, serviceEnabled, active;
  final Future<bool> Function() onEnableOverrides;
  @override
  State<_PerAppEditor> createState() => _PerAppEditorState();
}

class _PerAppEditorState extends State<_PerAppEditor> {
  late Map<String, dynamic> _draft;
  bool _dirty = false;
  bool _saving = false;
  bool _previewingSlider = false;
  bool _draggingSlider = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _draft = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.initial)) as Map,
    );
  }

  void _set(String key, dynamic value) {
    RodinBackend.instance.haptic(1);
    setState(() {
      if (value == null) {
        _draft.remove(key);
      } else {
        _draft[key] = value;
      }
      _dirty = true;
      _revision++;
    });
    if (!_previewingSlider) unawaited(_saveDraft());
  }

  Future<void> _saveDraft() async {
    if (_saving || !_dirty || _draggingSlider) return;
    _saving = true;
    if (mounted) setState(() {});
    try {
      while (_dirty && !_draggingSlider) {
        final int revision = _revision;
        final Map<String, dynamic> snapshot = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(_draft)) as Map,
        );
        final bool saved = await widget.onSave(snapshot);
        if (!saved) break; // Show the failure; never loop against the daemon.
        if (revision == _revision) _dirty = false;
        // New taps replace the pending draft, not a queue of stale selections.
      }
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  List<int> _numbers(String key) =>
      (widget.capabilities[key] as List? ?? <dynamic>[])
          .map((dynamic v) => (v as num).toInt())
          .toList();
  Widget _choice(
    String title,
    dynamic selected,
    Map<String, String> choices,
    ValueChanged<String?> change, {
    bool followGlobal = true,
  }) {
    final String value = selected?.toString() ?? 'global';
    final Map<String, String> all = <String, String>{
      if (followGlobal) 'global': 'Follow global',
      ...choices,
    };
    if (!all.containsKey(value))
      all[value] = '$value · Unavailable on this kernel';
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = colors.primary;
    final List<String> steps = choices.keys.toList();
    final bool frequency =
        !followGlobal && steps.every((String key) => int.tryParse(key) != null);
    Widget tile(String key, String label, {bool wide = false}) {
      final bool active = value == key;
      return Semantics(
        button: true,
        selected: active,
        child: PressScale(
          onTap: widget.busy
              ? null
              : () => change(key == 'global' ? null : key),
          child: AnimatedContainer(
            duration: RodinInteractionSettings.motionDuration(160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.14
                          : 0.075,
                    )
                  : colors.onSurface.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: <Widget>[
                if (wide) ...<Widget>[
                  Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: active ? accent : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? colors.primary : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 16,
                  child: AnimatedOpacity(
                    opacity: active ? 1 : 0,
                    duration: RodinInteractionSettings.motionDuration(120),
                    child: Icon(Icons.check_rounded, size: 16, color: accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          if (frequency && steps.isNotEmpty) ...<Widget>[
            Text(
              all[value]!,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                thumbColor: accent,
                valueIndicatorColor: accent,
                inactiveTrackColor: accent.withValues(alpha: 0.12),
                trackHeight: 5,
                overlayColor: accent.withValues(alpha: 0.08),
              ),
              child: Slider(
                min: 0,
                max: (steps.length > 1 ? steps.length - 1 : 1).toDouble(),
                divisions: steps.length > 1 ? steps.length - 1 : 1,
                value: steps
                    .indexOf(value)
                    .clamp(0, steps.length - 1)
                    .toDouble(),
                label: all[value],
                onChangeStart: (_) => _draggingSlider = true,
                onChanged: widget.busy || steps.length < 2
                    ? null
                    : (double v) {
                        final String next = steps[v.round()];
                        _previewingSlider = true;
                        try {
                          if (next != value) change(next);
                        } finally {
                          _previewingSlider = false;
                        }
                      },
                onChangeEnd: widget.busy
                    ? null
                    : (_) {
                        _draggingSlider = false;
                        unawaited(_saveDraft());
                      },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  choices[steps.first]!,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  choices[steps.last]!,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ] else ...<Widget>[
            if (followGlobal) tile('global', 'Follow global', wide: true),
            if (followGlobal && choices.isNotEmpty) const SizedBox(height: 8),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints bounds) {
                final bool twoColumns =
                    bounds.maxWidth >= 260 &&
                    MediaQuery.textScalerOf(context).scale(12) < 18;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final MapEntry<String, String> entry
                        in all.entries.where(
                          (MapEntry<String, String> e) => e.key != 'global',
                        ))
                      SizedBox(
                        width: twoColumns
                            ? (bounds.maxWidth - 8) / 2
                            : bounds.maxWidth,
                        child: tile(entry.key, entry.value),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _cpu(int policy) => Map<String, dynamic>.from(
    (_draft['cpu'] as Map?)?['$policy'] as Map? ?? <String, dynamic>{},
  );
  void _cpuSet(int policy, String key, dynamic value) {
    final Map<String, dynamic> cpu = Map<String, dynamic>.from(
      _draft['cpu'] as Map? ?? <String, dynamic>{},
    );
    final Map<String, dynamic> cluster = _cpu(policy);
    if (value == null) {
      cluster.remove(key);
    } else {
      cluster[key] = value;
    }
    if (cluster.isEmpty) {
      cpu.remove('$policy');
    } else {
      cpu['$policy'] = cluster;
    }
    _set('cpu', cpu.isEmpty ? null : cpu);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return RodinScrollPage(
      key: PageStorageKey<String>(
        'per-app-editor-${widget.app['user']}:${widget.app['package']}',
      ),
      children: <Widget>[
        DetailHeader(title: 'App profile', onBack: widget.onBack),
        const SizedBox(height: 12),
        HeroCard(
          icon: Icons.apps_rounded,
          accent: colors.primary,
          leading: widget.icon == null
              ? null
              : Image.memory(
                  widget.icon!,
                  width: 48,
                  height: 48,
                  gaplessPlayback: true,
                ),
          title: '${widget.app['label'] ?? widget.app['package']}',
          subtitle: widget.active
              ? 'Profile active · daemon-controlled'
              : !widget.serviceEnabled
              ? 'Rodin Essential is disabled'
              : !widget.overridesEnabled
              ? 'Saved only · per-app overrides are off'
              : _draft['enabled'] != true
              ? 'This profile is disabled'
              : 'Ready · applies when this app is in focus',
        ),
        const SizedBox(height: 12),
        if (!widget.overridesEnabled) ...<Widget>[
          SurfaceCard(
            accent: colors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Overrides are off',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can save this profile now. Turn on Per-App Controls to apply it when you open this app.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: widget.busy || !widget.serviceEnabled
                      ? null
                      : () async {
                          RodinBackend.instance.haptic(1);
                          await widget.onEnableOverrides();
                        },
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text('Enable Per-App Controls'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.app['launchable'] == false) ...<Widget>[
          const Text(
            'This package has no launcher entry. Its profile can only apply if an activity from this package becomes the focused app.',
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.error != null) ...<Widget>[
          SurfaceCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline_rounded, color: colors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Not applied: ${widget.error}',
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SurfaceCard(
          accent: const Color(0xFFB087FF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _PerAppSectionTitle(
                title: 'Profile preferences',
                icon: Icons.tune_rounded,
                accent: Color(0xFFB087FF),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enable this profile',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                value: _draft['enabled'] == true,
                onChanged: widget.busy ? null : (bool v) => _set('enabled', v),
              ),
              const Text(
                'Selected controls take priority over your ROM and global setup while this app is in focus. Leaving the app restores your previous settings. Follow global leaves a control unchanged.',
                style: TextStyle(fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _PerAppSectionTitle(
                title: 'Touch & display',
                icon: Icons.touch_app_rounded,
                accent: Color(0xFF4CC79E),
              ),
              const SizedBox(height: 14),
              _choice(
                'Touch response',
                _draft['touch'],
                <String, String>{
                  for (final int v in _numbers('touch'))
                    '$v': v == 0 ? 'OEM adaptive' : _rodinTouchLabel(v),
                },
                (String? v) => _set('touch', v == null ? null : int.parse(v)),
              ),
              _choice(
                'Refresh rate',
                _draft['refresh'],
                <String, String>{
                  for (final int v in _numbers('refresh'))
                    '$v': v == 0 ? 'OEM adaptive' : '$v Hz',
                },
                (String? v) => _set('refresh', v == null ? null : int.parse(v)),
              ),
              Text(
                'Uses supported display modes. Refresh rate is not the same as app FPS.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _PerAppSectionTitle(
                title: 'Mali GPU',
                icon: Icons.sports_esports_rounded,
                accent: Color(0xFFFF5252),
              ),
              const SizedBox(height: 14),
              _choice(
                'GPU profile',
                _draft['gpu'],
                <String, String>{
                  for (final int v in _numbers('gpu'))
                    '$v': _rodinPerformanceLabel(v),
                },
                (String? v) => _set('gpu', v == null ? null : int.parse(v)),
              ),
              const Text(
                'Changes GPU controls only.',
                style: TextStyle(fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final int policy in <int>[0, 4, 7]) _cluster(policy, colors),
        if (widget.capabilities['cores'] == true)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _PerAppSectionTitle(
                  title: 'CPU cores',
                  icon: Icons.memory_rounded,
                  accent: Color(0xFF59BDFC),
                ),
                const SizedBox(height: 14),
                _choice(
                  'Core control',
                  _draft['cores'] == null ? null : 'manual',
                  const <String, String>{'manual': 'Choose online cores'},
                  (String? v) => _set('cores', v == null ? null : 255),
                ),
                if (_draft['cores'] != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (int core = 0; core < 8; core++)
                        FilterChip(
                          label: Text('CPU $core'),
                          selected: (_draft['cores'] as int) & (1 << core) != 0,
                          onSelected: core == 0 || widget.busy
                              ? null
                              : (bool selected) => _set(
                                  'cores',
                                  selected
                                      ? (_draft['cores'] as int) | (1 << core)
                                      : (_draft['cores'] as int) & ~(1 << core),
                                ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                const Text(
                  'CPU 0 stays online. Follow global preserves your existing automatic/manual core preference.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          _saving
              ? 'Saving your selection…'
              : _dirty
              ? 'Selection not saved'
              : !widget.overridesEnabled
              ? 'Selections saved · overrides are off.'
              : 'Selections save automatically.',
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
        if (_dirty && !_saving && widget.error != null)
          TextButton(
            onPressed: () => unawaited(_saveDraft()),
            child: const Text('Retry saving'),
          ),
        OutlinedButton.icon(
          onPressed: widget.busy || _saving
              ? null
              : () async {
                  if (!await _confirmAppProfileReset(context, all: false))
                    return;
                  if (!mounted) return;
                  final bool reset = await widget.onReset();
                  if (reset && mounted)
                    setState(() {
                      _draft = <String, dynamic>{'enabled': true};
                      _dirty = false;
                    });
                },
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Reset this app to global'),
        ),
      ],
    );
  }

  Widget _cluster(int policy, ColorScheme colors) {
    final Map<dynamic, dynamic> caps =
        (widget.capabilities['cpu'] as Map?)?['$policy'] as Map? ??
        <dynamic, dynamic>{};
    final List<int> frequencies = (caps['frequencies'] as List? ?? <dynamic>[])
        .map((dynamic v) => (v as num).toInt())
        .toList();
    if (frequencies.isEmpty) return const SizedBox.shrink();
    final List<dynamic>? range = _cpu(policy)['range'] as List?;
    final String name = policy == 0
        ? 'Efficiency cluster'
        : policy == 4
        ? 'Performance cluster'
        : 'Prime core';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _PerAppSectionTitle(
              title: name,
              icon: Icons.memory_rounded,
              accent: const Color(0xFF67C2FF),
            ),
            const SizedBox(height: 14),
            _choice(
              'Frequency control',
              range == null ? null : 'range',
              const <String, String>{'range': 'Set minimum and maximum'},
              (String? v) => _cpuSet(
                policy,
                'range',
                v == null ? null : <int>[frequencies.first, frequencies.last],
              ),
            ),
            if (range != null) ...<Widget>[
              _choice(
                'Minimum frequency',
                range[0],
                <String, String>{
                  for (final int v in frequencies)
                    if (v <= (range[1] as num)) '$v': '$v MHz',
                },
                (String? v) {
                  if (v != null)
                    _cpuSet(policy, 'range', <int>[
                      int.parse(v),
                      (range[1] as num).toInt(),
                    ]);
                },
                followGlobal: false,
              ),
              _choice(
                'Maximum frequency',
                range[1],
                <String, String>{
                  for (final int v in frequencies)
                    if (v >= (range[0] as num)) '$v': '$v MHz',
                },
                (String? v) {
                  if (v != null)
                    _cpuSet(policy, 'range', <int>[
                      (range[0] as num).toInt(),
                      int.parse(v),
                    ]);
                },
                followGlobal: false,
              ),
              Text(
                'Use the same minimum and maximum for an exact frequency target.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
            ],
            _choice(
              'Governor',
              _cpu(policy)['governor'],
              <String, String>{
                for (final dynamic v
                    in caps['governors'] as List? ?? <dynamic>[])
                  '$v': '$v',
              },
              (String? v) => _cpuSet(policy, 'governor', v),
            ),
            const Text(
              'Governor selection is independent of the frequency range.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _PerAppSectionTitle extends StatelessWidget {
  const _PerAppSectionTitle({
    required this.title,
    required this.icon,
    required this.accent,
  });
  final String title;
  final IconData icon;
  final Color accent;
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.065),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: accent, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
    ],
  );
}
