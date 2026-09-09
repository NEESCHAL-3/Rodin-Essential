part of 'main.dart';

class SystemColorsScreen extends StatefulWidget {
  const SystemColorsScreen({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  State<SystemColorsScreen> createState() => _SystemColorsScreenState();
}

class _SystemColorsScreenState extends State<SystemColorsScreen>
    with WidgetsBindingObserver {
  final RodinBackend _backend = RodinBackend.instance;
  StreamSubscription<RodinBackendSnapshot>? _subscription;
  late RodinSystemColorsState _palette;
  late RodinConnectionState _connection;
  RodinSystemColorsSelection? _selection;

  @override
  void initState() {
    super.initState();
    _palette = _backend.systemColors;
    _connection = _backend.latest.connection;
    _selection = _backend.systemColorsSelection;
    WidgetsBinding.instance.addObserver(this);
    _subscription = _backend.snapshots.listen((RodinBackendSnapshot snapshot) {
      if (!mounted) return;
      final RodinSystemColorsState next = _backend.systemColors;
      final RodinSystemColorsSelection? selection =
          _backend.systemColorsSelection;
      final bool connected =
          _connection != RodinConnectionState.online && snapshot.ready;
      if (next.revision != _palette.revision ||
          next.operationState != _palette.operationState ||
          snapshot.connection != _connection ||
          selection != _selection) {
        setState(() {
          _palette = next;
          _connection = snapshot.connection;
          _selection = selection;
        });
      }
      if (connected && !next.busy) _backend.refreshSystemColors();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_backend.systemColors.busy)
        _backend.refreshSystemColors();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_backend.systemColors.busy) {
      _backend.refreshSystemColors();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RodinScrollPage(
      children: <Widget>[
        DetailHeader(title: 'System Colors', onBack: widget.onBack),
        const SizedBox(height: 12),
        SystemColorsPanel(
          palette: _palette,
          connection: _connection,
          selection: _selection,
          onRefresh: _backend.refreshSystemColors,
          isNativeBusy: () => _backend.systemColors.busy,
          onApply: (bool wallpaper, int seed, int style) => wallpaper
              ? _backend.useWallpaperSystemColors()
              : _backend.setSystemColors(seed, style),
        ),
      ],
    );
  }
}

const List<String> _paletteStyleNames = <String>[
  'Tonal',
  'Vibrant',
  'Expressive',
  'Soft',
  'Rainbow',
  'Fruit Salad',
  'Monochrome',
];
const List<(String, int)> _paletteSeeds = <(String, int)>[
  ('Teal', 0x008577),
  ('Ocean', 0x386bd5),
  ('Iris', 0x7655ca),
  ('Rose', 0xad477b),
  ('Clay', 0xb95733),
  ('Gold', 0x997a16),
  ('Forest', 0x4e7541),
  ('Slate', 0x526774),
];

String _paletteHex(int rgb) =>
    '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
Color _paletteColor(int rgb) => Color(0xff000000 | rgb);

/// Choices apply on tap; consecutive slider gestures form one adjustment.
/// Native readback stays separate from the selected preview. Rapid choices
/// coalesce to the latest selection while one transaction is in progress.
class SystemColorsPanel extends StatefulWidget {
  const SystemColorsPanel({
    required this.palette,
    required this.connection,
    required this.onApply,
    required this.onRefresh,
    this.onSelectionFeedback = RodinHaptics.segment,
    this.isNativeBusy,
    this.selection,
    this.previewBuilder,
    super.key,
  });

  final RodinSystemColorsState palette;
  final RodinConnectionState connection;
  bool get backendOnline => connection == RodinConnectionState.online;
  final bool Function(bool wallpaper, int seed, int style) onApply;
  final bool Function() onRefresh;
  final VoidCallback onSelectionFeedback;
  final bool Function()? isNativeBusy;
  final RodinSystemColorsSelection? selection;
  final Widget Function(int seed, int style, bool dark, bool scrubbing)?
  previewBuilder;

  @override
  State<SystemColorsPanel> createState() => _SystemColorsPanelState();
}

class _SystemColorsPanelState extends State<SystemColorsPanel> {
  bool _wallpaper = true;
  int _seed = 0x008577;
  int _style = 0;
  int _fineTuneBase = 0x008577;
  HSLColor _hsl = HSLColor.fromColor(const Color(0xff008577));
  bool _edited = false;
  bool? _previewDark;
  int? _pendingRevision;
  bool _applyQueued = false;
  bool _dispatchScheduled = false;
  bool _sliding = false;
  bool _needsQuiet = false;
  Timer? _quietTimer;
  final Set<int> _activePointers = <int>{};
  static const Duration _sliderQuietTime = Duration(milliseconds: 280);
  String? _notice;
  int _hapticStep = -1;
  final Stopwatch _hapticClock = Stopwatch()..start();
  int _lastHapticMs = -100;

  @override
  void initState() {
    super.initState();
    _syncDraft();
  }

  @override
  void dispose() {
    _quietTimer?.cancel();
    // A completed edit must not disappear if Back is tapped during the short
    // slider settling window. Only flush a write that is already safe to send;
    // never retry a failure or write an unfinished gesture from dispose.
    if (_applyQueued &&
        !_sliding &&
        !_busy &&
        widget.backendOnline &&
        widget.palette.ready &&
        widget.palette.supported &&
        !_matchesCurrent &&
        !(widget.isNativeBusy?.call() ?? false)) {
      widget.onApply(_wallpaper, _seed, _style);
    }
    super.dispose();
  }

  void _syncDraft() {
    final RodinSystemColorsSelection? selection =
        RodinSystemColorsSelection.fromNative(widget.palette) ??
        widget.selection;
    if (selection == null) return;
    // Preserve the unrounded HSL draft and reset point when Android confirms
    // our own edit. Converting through RGB on every frame loses hue at gray,
    // black and white, and causes the other sliders to jump.
    if (selection.seed != _seed || selection.wallpaper != _wallpaper) {
      _hsl = HSLColor.fromColor(_paletteColor(selection.seed));
      _fineTuneBase = selection.seed;
    }
    _wallpaper = selection.wallpaper;
    _seed = selection.seed;
    _style = selection.style;
    _edited = false;
  }

  @override
  void didUpdateWidget(SystemColorsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final RodinSystemColorsState palette = widget.palette;
    if (!widget.backendOnline) _applyQueued = false;
    if (!_edited &&
        !palette.hasReadback &&
        widget.selection != oldWidget.selection) {
      _syncDraft();
    }
    if (palette.busy ||
        (palette.revision == oldWidget.palette.revision &&
            palette.operationState == oldWidget.palette.operationState)) {
      return;
    }
    if (_pendingRevision != null && palette.revision != _pendingRevision) {
      _pendingRevision = null;
      if (palette.ready) {
        if (!_applyQueued && !_sliding) _syncDraft();
        _notice = switch (palette.outcome) {
          1 =>
            palette.mode == 0
                ? 'Wallpaper colors restored. Android’s palette changed.'
                : 'System colors updated. Verified against Android’s palette.',
          2 =>
            'Wallpaper following restored. Android resolved the same colors.',
          _ => 'This palette is already selected in Android.',
        };
      } else {
        _applyQueued = false;
        _notice = null;
      }
    } else if (!_edited) {
      _syncDraft();
    }
    if (_applyQueued && !_busy) _dispatchWhenReady();
  }

  bool get _busy => widget.palette.busy || _pendingRevision != null;
  bool get _selectionKnown =>
      _edited ||
      widget.selection != null ||
      RodinSystemColorsSelection.fromNative(widget.palette) != null;
  bool get _matchesCurrent {
    final RodinSystemColorsState palette = widget.palette;
    if (!palette.hasReadback) return false;
    return _wallpaper
        ? palette.mode == 0 && palette.style == 0
        : palette.mode == 1 && palette.seed == _seed && palette.style == _style;
  }

  void _edit(VoidCallback update) {
    setState(() {
      update();
      _edited = true;
      _notice = null;
    });
  }

  void _select(VoidCallback update) {
    _quietTimer?.cancel();
    _quietTimer = null;
    _needsQuiet = false;
    // Feedback belongs to the gesture, never to a delayed daemon reply.
    widget.onSelectionFeedback();
    _edit(update);
    debugPrint(
      'RODIN_SYSTEM_COLORS_SELECT wallpaper=$_wallpaper seed=$_seed '
      'style=$_style revision=${widget.palette.revision}',
    );
    _scheduleApply();
  }

  void _scheduleApply({bool afterDrag = false}) {
    if (!widget.backendOnline ||
        widget.palette.failed ||
        (widget.palette.hasReadback && !widget.palette.supported)) {
      _applyQueued = false;
      return;
    }
    _applyQueued = true;
    if (afterDrag) _needsQuiet = true;
    _dispatchWhenReady();
  }

  void _dispatchWhenReady() {
    if (!mounted || !_applyQueued || _sliding || _activePointers.isNotEmpty) {
      return;
    }
    if (_needsQuiet) {
      // An Android overlay update can cover the screen with a system snapshot.
      // Do not start one in the small gap between two fine-tune gestures.
      _quietTimer ??= Timer(_sliderQuietTime, () {
        _quietTimer = null;
        _needsQuiet = false;
        _dispatchWhenReady();
      });
      return;
    }
    if (_dispatchScheduled) return;
    _dispatchScheduled = true;
    // Submission only queues native work; it never waits for Android. Do not
    // require another rendering frame to deliver a user's selection.
    scheduleMicrotask(() {
      _dispatchScheduled = false;
      if (mounted &&
          _applyQueued &&
          !_sliding &&
          !_needsQuiet &&
          _activePointers.isEmpty) {
        _applySelection();
      }
    });
  }

  void _pointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _quietTimer?.cancel();
    _quietTimer = null;
  }

  void _pointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    _dispatchWhenReady();
  }

  void _beginSlider(double _) {
    _quietTimer?.cancel();
    _quietTimer = null;
    _needsQuiet = true;
    _hapticStep = -1;
    setState(() => _sliding = true);
  }

  void _endSlider(double _) {
    setState(() => _sliding = false);
    _scheduleApply(afterDrag: true);
  }

  void _applySelection() {
    final RodinSystemColorsState palette = widget.palette;
    if (!widget.backendOnline ||
        palette.failed ||
        (palette.hasReadback && !palette.supported)) {
      _applyQueued = false;
      return;
    }
    // Preserve taps during discovery and during native refreshes that the
    // next UI snapshot has not reported yet. Dispatch once the read completes.
    if (!palette.hasReadback ||
        _busy ||
        (widget.isNativeBusy?.call() ?? false)) {
      _applyQueued = true;
      return;
    }
    _applyQueued = false;
    if (_matchesCurrent) {
      setState(() => _edited = false);
      return;
    }
    final int revision = widget.palette.revision;
    if (widget.onApply(_wallpaper, _seed, _style)) {
      debugPrint('RODIN_SYSTEM_COLORS_SUBMIT revision=$revision');
      setState(() {
        _pendingRevision = revision;
        _notice = null;
      });
    } else if (widget.isNativeBusy?.call() ?? false) {
      // The native refresh can start between the preflight check and submit.
      _applyQueued = true;
    } else {
      setState(
        () => _notice =
            'Could not apply this selection. Refresh and select it again.',
      );
    }
  }

  void _changeHsl(HSLColor color, int hapticStep) {
    if (_hapticStep != hapticStep) {
      _hapticStep = hapticStep;
      final int now = _hapticClock.elapsedMilliseconds;
      if (now - _lastHapticMs >= 45) {
        _lastHapticMs = now;
        RodinHaptics.frequentSegment();
      }
    }
    _edit(() {
      _hsl = color;
      _seed = color.toColor().toARGB32() & 0xffffff;
    });
  }

  void _chooseSeed(int rgb) {
    _select(() {
      _seed = rgb;
      _fineTuneBase = rgb;
      _hsl = HSLColor.fromColor(_paletteColor(rgb));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final RodinSystemColorsState palette = widget.palette;
    final bool dark =
        _previewDark ?? Theme.of(context).brightness == Brightness.dark;
    final int previewSeed = _wallpaper && palette.hasReadback
        ? (palette.seed >= 0 ? palette.seed : palette.primary)
        : _seed;
    final int styleCount = palette.sdk > 0 && palette.sdk < 33
        ? 1
        : palette.sdk == 33
        ? 6
        : 7;
    final TextStyle description = TextStyle(
      fontSize: 12.5,
      height: 1.5,
      color: colors.onSurfaceVariant,
    );

    return Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerEnd,
      onPointerCancel: _pointerEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Make Android yours.',
            style: TextStyle(
              fontSize: 26,
              height: 1.12,
              letterSpacing: -0.7,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Android’s native Monet palette across compatible system '
            'surfaces, apps and keyboards. Separate from Rodin’s own theme.',
            style: description,
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Palette preview')),
              IconButton(
                tooltip: 'Preview light colors',
                onPressed: () => setState(() => _previewDark = false),
                isSelected: !dark,
                icon: const Icon(Icons.light_mode_outlined, size: 19),
                selectedIcon: const Icon(Icons.light_mode_rounded, size: 19),
              ),
              IconButton(
                tooltip: 'Preview dark colors',
                onPressed: () => setState(() => _previewDark = true),
                isSelected: dark,
                icon: const Icon(Icons.dark_mode_outlined, size: 19),
                selectedIcon: const Icon(Icons.dark_mode_rounded, size: 19),
              ),
            ],
          ),
          widget.previewBuilder?.call(
                previewSeed,
                _wallpaper ? 0 : _style,
                dark,
                _sliding,
              ) ??
              _SystemPalettePreviewPane(
                seed: previewSeed,
                style: _wallpaper ? 0 : _style,
                dark: dark,
                scrubbing: _sliding,
              ),
          const SizedBox(height: 8),
          Text(
            !_selectionKnown
                ? 'Reading your saved Android palette. No source is selected yet.'
                : _wallpaper && palette.mode != 0
                ? 'Wallpaper colors are generated after applying. This is an example palette.'
                : 'Illustrative preview. Your ROM generates the final colors.',
            style: description.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Color source'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stack =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(13) > 18;
              final List<Widget> choices = <Widget>[
                _PaletteSourceTile(
                  title: 'Wallpaper',
                  subtitle: 'Let Android choose',
                  icon: Icons.wallpaper_rounded,
                  selected: _selectionKnown && _wallpaper,
                  onTap: () => _select(() => _wallpaper = true),
                ),
                _PaletteSourceTile(
                  title: 'Custom color',
                  subtitle: 'Choose your own seed',
                  icon: Icons.color_lens_rounded,
                  selected: _selectionKnown && !_wallpaper,
                  onTap: () => _select(() => _wallpaper = false),
                ),
              ];
              if (stack)
                return Column(
                  children: <Widget>[
                    choices[0],
                    const SizedBox(height: 10),
                    choices[1],
                  ],
                );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: choices[0]),
                  const SizedBox(width: 10),
                  Expanded(child: choices[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (!_wallpaper) ...<Widget>[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RepaintBoundary(
                    child: Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text(
                            'Seed color',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          _paletteHex(_seed),
                          style: description.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a seed or style to apply. Fine-tune freely; Android '
                    'updates after a brief pause between adjustments.',
                    style: description,
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final int columns =
                              constraints.maxWidth < 240 ||
                                  MediaQuery.textScalerOf(context).scale(11) >
                                      15
                              ? 3
                              : 4;
                          final double width =
                              (constraints.maxWidth - 8 * (columns - 1)) /
                              columns;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final (String name, int rgb)
                                  in _paletteSeeds)
                                _PaletteSeedTile(
                                  name: name,
                                  rgb: rgb,
                                  width: width,
                                  selected: _seed == rgb,
                                  onTap: () => _chooseSeed(rgb),
                                ),
                            ],
                          );
                        },
                  ),
                  const SizedBox(height: 16),
                  Divider(color: colors.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Fine-tune color',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey<String>('palette-reset-tuning'),
                        onPressed:
                            _hsl ==
                                HSLColor.fromColor(_paletteColor(_fineTuneBase))
                            ? null
                            : () => _select(() {
                                _seed = _fineTuneBase;
                                _hsl = HSLColor.fromColor(
                                  _paletteColor(_fineTuneBase),
                                );
                              }),
                        icon: const Icon(Icons.restart_alt_rounded, size: 17),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                  Text(
                    'Reset restores your starting seed. Your palette style stays the same.',
                    style: description.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  _seedSlider(
                    'Hue',
                    _hsl.hue,
                    0,
                    360,
                    const <Color>[
                      Color(0xffff0000),
                      Color(0xffffff00),
                      Color(0xff00ff00),
                      Color(0xff00ffff),
                      Color(0xff0000ff),
                      Color(0xffff00ff),
                      Color(0xffff0000),
                    ],
                    (double value) =>
                        _changeHsl(_hsl.withHue(value), value ~/ 20),
                  ),
                  _seedSlider(
                    'Intensity',
                    _hsl.saturation,
                    0,
                    1,
                    <Color>[
                      _hsl.withSaturation(0).toColor(),
                      _hsl.withSaturation(1).toColor(),
                    ],
                    (double value) => _changeHsl(
                      _hsl.withSaturation(value),
                      100 + (value * 18).round(),
                    ),
                  ),
                  _seedSlider(
                    'Lightness',
                    _hsl.lightness,
                    0,
                    1,
                    <Color>[
                      Colors.black,
                      _hsl.withLightness(0.5).toColor(),
                      Colors.white,
                    ],
                    (double value) => _changeHsl(
                      _hsl.withLightness(value),
                      200 + (value * 18).round(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Divider(color: colors.outlineVariant.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text(
                    'Palette style',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (int index = 0; index < styleCount; index++)
                        ChoiceChip(
                          label: Text(_paletteStyleNames[index]),
                          selected: _style == index,
                          onSelected: (_) => _select(() => _style = index),
                          labelStyle: const TextStyle(fontSize: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Android builds tonal colors from this seed; accents '
                    'may differ from the exact color you pick. Gray or near-black '
                    'seeds may use Android’s fallback color. For grayscale, '
                    'choose Monochrome when available.',
                    style: description,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else if (_selectionKnown) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Text(
                'Use colors from your wallpaper and follow future wallpaper '
                'changes. Selecting this removes only custom palette settings.',
                style: description,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (!widget.backendOnline ||
              palette.failed ||
              (palette.ready && !palette.supported)) ...<Widget>[
            _PaletteNotice(
              icon: Icons.info_outline_rounded,
              text: !widget.backendOnline
                  ? widget.connection == RodinConnectionState.connecting
                        ? 'Connecting to the system service. You can preview colors while it connects.'
                        : 'Preview only — the system service is offline. The updated '
                              'Rodin backend is needed to apply colors.'
                  : palette.failed
                  ? palette.errorMessage
                  : 'This ROM does not expose Android’s native Material You '
                        'update path. Preview remains available, but Rodin will '
                        'not claim or fabricate a system-wide result.',
            ),
            const SizedBox(height: 12),
          ],
          if (_busy)
            Row(
              key: const ValueKey<String>('palette-apply-status'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _pendingRevision != null
                        ? 'Updating Android colors…'
                        : 'Reading Android colors…',
                    style: description,
                  ),
                ),
              ],
            ),
          if (_notice != null && !_busy) ...<Widget>[
            const SizedBox(height: 12),
            _PaletteNotice(icon: Icons.info_outline_rounded, text: _notice!),
          ],
          const SizedBox(height: 20),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Android’s current colors',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh Android palette',
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _notice = null);
                              widget.onRefresh();
                            },
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ],
                ),
                if (palette.hasReadback) ...<Widget>[
                  Text(
                    palette.mode == 0
                        ? 'Wallpaper colors'
                        : palette.mode == 1
                        ? 'Custom · ${_paletteHex(palette.seed)}'
                        : 'System preset',
                    style: description,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (
                        int index = 0;
                        index < palette.nativeColors.length;
                        index++
                      )
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: index == 4 ? 0 : 6),
                            child: Column(
                              children: <Widget>[
                                Semantics(
                                  label:
                                      'Native ${_paletteHex(palette.nativeColors[index])}',
                                  child: Container(
                                    key: ValueKey<String>(
                                      'palette-native-$index',
                                    ),
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: _paletteColor(
                                        palette.nativeColors[index],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  index < 3
                                      ? 'Accent ${index + 1}'
                                      : 'Neutral ${index - 2}',
                                  textAlign: TextAlign.center,
                                  style: description.copyWith(fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    palette.ready && widget.backendOnline
                        ? 'Five tonal families, read from Android at tone 500.'
                        : 'Last successful readback. Refresh to check the current palette.',
                    style: description.copyWith(fontSize: 11),
                  ),
                ] else
                  Text(
                    palette.busy
                        ? 'Reading native palette resources…'
                        : 'No native readback yet. Preview colors are not reported as applied.',
                    style: description,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Android saves your choice across restarts. No background reapply '
            'loop is used. OEM surfaces, apps and keyboards with fixed themes '
            'can ignore the palette even when Android applies it correctly.',
            style: description,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _seedSlider(
    String label,
    double value,
    double min,
    double max,
    List<Color> trackColors,
    ValueChanged<double> onChanged,
  ) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color thumbColor = _hsl.toColor();
    final String formatted = label == 'Hue'
        ? '${value.round()}°'
        : '${(value * 100).round()}%';
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                key: ValueKey<String>('palette-slider-value-$label'),
                constraints: const BoxConstraints(minWidth: 49),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  formatted,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                    fontFeatures: const <ui.FontFeature>[
                      ui.FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 12,
              trackShape: _PaletteGradientTrack(colors: trackColors),
              thumbShape: const _PaletteSliderThumb(),
              thumbColor: thumbColor,
              overlayColor: thumbColor.withValues(alpha: 0.1),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              // Discrete Material sliders animate toward each new position.
              // Continuous values follow the finger without that trailing motion.
              semanticFormatterCallback: (double v) => label == 'Hue'
                  ? '${v.round()} degrees'
                  : '${(v * 100).round()} percent',
              key: ValueKey<String>('palette-slider-$label'),
              onChangeStart: _beginSlider,
              onChanged: onChanged,
              onChangeEnd: _endSlider,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PaletteSeedTile extends StatelessWidget {
  const _PaletteSeedTile({
    required this.name,
    required this.rgb,
    required this.width,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final int rgb;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name seed color',
      excludeSemantics: true,
      child: PressScale(
        enableHaptics: false,
        onTap: onTap,
        child: Container(
          key: ValueKey<String>('palette-seed-$name'),
          width: width,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? _paletteColor(rgb).withValues(alpha: 0.09)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.onSurface : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: <Widget>[
              AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _paletteColor(rgb),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 21,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteGradientTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _PaletteGradientTrack({required this.colors});
  final List<Color> colors;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = true,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final Rect rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final RRect track = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    context.canvas.drawRRect(
      track,
      Paint()
        ..shader = LinearGradient(
          colors: textDirection == TextDirection.ltr
              ? colors
              : colors.reversed.toList(growable: false),
        ).createShader(rect),
    );
    context.canvas.drawRRect(
      track,
      Paint()
        ..color = const Color(0x26000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
  }
}

class _PaletteSliderThumb extends SliderComponentShape {
  const _PaletteSliderThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(22, 22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    canvas.drawCircle(center, 11, Paint()..color = const Color(0x35000000));
    canvas.drawCircle(center, 10, Paint()..color = Colors.white);
    canvas.drawCircle(center, 7, Paint()..color = sliderTheme.thumbColor!);
  }
}

class _PaletteSourceTile extends StatelessWidget {
  const _PaletteSourceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = RodinAppearanceScope.of(context).activeAccent;
    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        enableHaptics: false,
        onTap: onTap,
        child: AnimatedContainer(
          duration: RodinInteractionSettings.motionDuration(220),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.1)
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.7)
                  : colors.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    icon,
                    color: selected ? accent : colors.onSurfaceVariant,
                    size: 23,
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? accent : colors.outline,
                    size: 19,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteNotice extends StatelessWidget {
  const _PaletteNotice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemPalettePreviewPane extends StatefulWidget {
  const _SystemPalettePreviewPane({
    required this.seed,
    required this.style,
    required this.dark,
    required this.scrubbing,
  });
  final int seed;
  final int style;
  final bool dark;
  final bool scrubbing;

  @override
  State<_SystemPalettePreviewPane> createState() =>
      _SystemPalettePreviewPaneState();
}

class _SystemPalettePreviewPaneState extends State<_SystemPalettePreviewPane> {
  final RodinPalettePreviewWorker _worker = RodinPalettePreviewWorker();
  final Map<RodinPaletteKey, ColorScheme> _cache =
      <RodinPaletteKey, ColorScheme>{};
  late RodinPaletteKey _wanted;
  RodinPaletteKey? _shown;
  ColorScheme? _scheme;
  bool _running = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(_SystemPalettePreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _request();
  }

  void _request() {
    _wanted = (widget.seed, widget.style, widget.dark);
    if (_shown == _wanted) return;
    final ColorScheme? cached = _cache.remove(_wanted);
    if (cached != null) {
      _cache[_wanted] = cached;
      _scheme = cached;
      _shown = _wanted;
      _failed = false;
      return;
    }
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      // Only one job runs at a time; intermediate drag positions are replaced
      // by the latest key, never accumulated into a delayed preview backlog.
      while (mounted && _shown != _wanted) {
        final RodinPaletteKey key = _wanted;
        final List<int> colors = await _worker.generate(key);
        if (!mounted) return;
        final ColorScheme scheme = rodinPreviewScheme(colors, key.$3);
        if (_cache.length >= 24) _cache.remove(_cache.keys.first);
        _cache[key] = scheme;
        if (key == _wanted) {
          setState(() {
            _shown = key;
            _scheme = scheme;
            _failed = false;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _failed = true);
        debugPrint('RODIN_PALETTE_PREVIEW_FAIL $error');
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _worker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SystemPalettePreview(
            scheme: _scheme ?? Theme.of(context).colorScheme,
            animate: !widget.scrubbing,
          ),
          if (_failed)
            const Text(
              'Preview unavailable. System color controls still work.',
            ),
        ],
      ),
    );
  }
}

class _SystemPalettePreview extends StatelessWidget {
  const _SystemPalettePreview({required this.scheme, this.animate = true});
  final ColorScheme scheme;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: animate
          ? RodinInteractionSettings.motionDuration(180)
          : Duration.zero,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'A little more you.',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.onTertiaryContainer,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.notifications_none_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your everyday, in color',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 35,
                  height: 21,
                  padding: const EdgeInsets.all(3),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: scheme.onPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (final String letter in <String>[
                'Q',
                'W',
                'E',
                'R',
                'T',
                'Y',
              ])
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: letter == 'Y' ? 0 : 5),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 100,
              height: 22,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.space_bar_rounded,
                size: 19,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
