part of 'main.dart';

class AuroraDrift extends StatefulWidget {
  const AuroraDrift({required this.onBack, super.key});
  final VoidCallback onBack;
  @override
  State<AuroraDrift> createState() => _AuroraDriftState();
}

class _AuroraDriftState extends State<AuroraDrift>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AuroraGame _game = AuroraGame();
  late final Ticker _ticker;
  Duration? _last;
  int _best = 0;
  bool _started = false;
  bool _paused = false;
  String _hud = '';
  bool _recordSaved = false;
  File get _scoreFile =>
      File('${Directory.systemTemp.parent.path}/files/aurora-drift-best.json');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    unawaited(_loadBest());
  }

  Future<void> _loadBest() async {
    try {
      final dynamic saved = jsonDecode(await _scoreFile.readAsString());
      final int best = (saved['best'] as num).toInt().clamp(0, 1000000);
      if (mounted) setState(() => _best = math.max(_best, best));
    } catch (_) {
      /* Missing or invalid recreational data never affects controls. */
    }
  }

  Future<void> _saveBest() async {
    if (_game.score <= _best) return;
    _best = _game.score;
    try {
      await _scoreFile.parent.create(recursive: true);
      final File pending = File('${_scoreFile.path}.tmp');
      await pending.writeAsString(
        jsonEncode(<String, int>{'best': _best}),
        flush: true,
      );
      await pending.rename(_scoreFile.path);
    } catch (_) {
      /* Gameplay still works if storage is unavailable. */
    }
    if (mounted) setState(() {});
  }

  void _tick(Duration now) {
    final Duration? previous = _last;
    _last = now;
    if (previous == null) return;
    final int lives = _game.lives;
    final int score = _game.score;
    _game.advance((now - previous).inMicroseconds / 1000000);
    if (_game.lives < lives)
      RodinBackend.instance.haptic(2);
    else if (_game.score > score && _game.combo % 3 == 0)
      RodinHaptics.tap();
    final String hud =
        '${_game.score}:${_game.lives}:${_game.secondsLeft}:${_game.combo}:${_game.finished}';
    if (hud != _hud && mounted) setState(() => _hud = hud);
    if (_game.finished) {
      _ticker.stop();
      if (!_recordSaved) {
        _recordSaved = true;
        unawaited(_saveBest());
      }
    }
  }

  void _start() {
    RodinHaptics.confirm();
    _last = null;
    _recordSaved = false;
    _game.start();
    setState(() {
      _started = true;
      _paused = false;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  void _pause() {
    if (!_game.running) return;
    _game.pause();
    _ticker.stop();
    _last = null;
    if (mounted) setState(() => _paused = true);
  }

  void _resume() {
    RodinHaptics.confirm();
    _last = null;
    _game.resume();
    setState(() => _paused = false);
    _ticker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.7).clamp(300, 580),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Back to secret room',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  'Aurora Drift',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (_game.running)
                IconButton(
                  tooltip: 'Pause game',
                  onPressed: _pause,
                  icon: const Icon(Icons.pause_rounded),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: <Widget>[
                Text(
                  '${_game.score} pts',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text('${_game.secondsLeft}s'),
                Text('${_game.lives} lives'),
                Text('Best $_best'),
                if (_game.combo > 1)
                  Text(
                    '×${math.min(_game.combo, 8)} combo',
                    style: TextStyle(color: colors.secondary),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: (DragDownDetails d) => _game.steer(
                        d.localPosition.dx / constraints.maxWidth,
                      ),
                      onPanUpdate: (DragUpdateDetails d) => _game.steer(
                        d.localPosition.dx / constraints.maxWidth,
                      ),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _AuroraWorld(
                            _game,
                            reduced: MediaQuery.disableAnimationsOf(context),
                          ),
                        ),
                      ),
                    ),
                    if (!_started || _paused || _game.finished)
                      ColoredBox(
                        color: const Color(0xDD080F20),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  _game.finished
                                      ? (_game.lives == 0
                                            ? 'That meteor wasn’t in the changelog.'
                                            : 'A stellar little detour.')
                                      : _paused
                                      ? 'Taking a breather.'
                                      : 'Catch stars. Dodge rocks.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _game.finished
                                      ? '${_game.score} points · best combo ${_game.bestCombo}'
                                      : _paused
                                      ? 'Resume when you’re ready.'
                                      : 'Drag left and right to steer R.\nBuild combos. You have three lives and 30 seconds.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFB8C6DF),
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton(
                                  onPressed: _paused ? _resume : _start,
                                  child: Text(
                                    _paused
                                        ? 'Resume'
                                        : _game.finished
                                        ? 'Drift again'
                                        : 'Let’s drift',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Aurora · v$rodinVersionName · just for fun',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AuroraWorld extends CustomPainter {
  _AuroraWorld(this.game, {required this.reduced}) : super(repaint: game);
  final AuroraGame game;
  final bool reduced;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF080F20),
    );
    final double time = reduced ? 0 : game.elapsed;
    for (int band = 0; band < 3; band++) {
      final Path path = Path()..moveTo(-20, size.height * 0.25);
      for (double x = -20; x <= size.width + 20; x += 12) {
        final double y =
            size.height * (0.25 + band * 0.14) +
            math.sin(x / 90 + time * 0.35 + band) * 30;
        path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..color = <Color>[
            const Color(0x194EF2CB),
            const Color(0x197E8CFF),
            const Color(0x199165FF),
          ][band],
      );
    }
    final Paint starPaint = Paint()..color = const Color(0x665D739D);
    for (int i = 0; i < 30; i++) {
      canvas.drawCircle(
        Offset(
          ((i * 71) % 293) / 293 * size.width,
          (((i * 47) % 257) / 257 * size.height + time * 5) % size.height,
        ),
        i.isEven ? 1 : 1.6,
        starPaint,
      );
    }
    for (final AuroraObject object in game.objects) {
      final Offset center = Offset(
        object.x * size.width,
        object.y * size.height,
      );
      if (object.meteor) {
        canvas.drawCircle(center, 10, Paint()..color = const Color(0xFFFC8F83));
        canvas.drawCircle(
          center + const Offset(-3, -2),
          3,
          Paint()..color = const Color(0xFFBC5E62),
        );
        canvas.drawCircle(
          center + const Offset(4, 3),
          2,
          Paint()..color = const Color(0xFFBC5E62),
        );
      } else {
        final Path star = Path();
        for (int i = 0; i < 8; i++) {
          final Offset point =
              center + Offset.fromDirection(i * math.pi / 4, i.isEven ? 10 : 4);
          if (i == 0)
            star.moveTo(point.dx, point.dy);
          else
            star.lineTo(point.dx, point.dy);
        }
        star.close();
        canvas.drawPath(star, Paint()..color = const Color(0xFFF9D98B));
      }
    }
    final Offset player = Offset(game.playerX * size.width, size.height * 0.82);
    if (game.invulnerable > 0)
      canvas.drawCircle(
        player,
        23,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xCC83DDFF),
      );
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: player, width: 34, height: 34),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF16C8D7), Color(0xFF374FE0)],
        ).createShader(body.outerRect),
    );
    final TextPainter label = TextPainter(
      text: const TextSpan(
        text: 'R',
        style: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, player - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(_AuroraWorld old) =>
      old.game != game || old.reduced != reduced;
}
