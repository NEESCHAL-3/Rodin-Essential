import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class AuroraObject {
  AuroraObject(this.x, this.y, this.speed, {required this.meteor});
  double x;
  double y;
  final double speed;
  final bool meteor;
}

/// NEESCHAL's strictly recreational scheduler: stars get priority, rocks don't.
/// Normalized world coordinates make gameplay independent of DPI and FPS.
class AuroraGame extends ChangeNotifier {
  AuroraGame({int? seed}) : _random = math.Random(seed);
  final math.Random _random;
  final List<AuroraObject> objects = <AuroraObject>[];
  double playerX = 0.5;
  double targetX = 0.5;
  double elapsed = 0;
  double invulnerable = 0;
  double _spawn = 0;
  int score = 0;
  int combo = 0;
  int bestCombo = 0;
  int lives = 3;
  bool running = false;
  bool finished = false;
  static const double roundSeconds = 30;
  int get secondsLeft => math.max(0, (roundSeconds - elapsed).ceil());

  void start() {
    objects.clear();
    playerX = targetX = 0.5;
    elapsed = invulnerable = _spawn = 0;
    score = combo = bestCombo = 0;
    lives = 3;
    finished = false;
    running = true;
    notifyListeners();
  }

  void steer(double x) => targetX = x.clamp(0.07, 0.93);
  void pause() {
    running = false;
    notifyListeners();
  }

  void resume() {
    if (!finished) {
      running = true;
      notifyListeners();
    }
  }

  void advance(double dt) {
    if (!running || finished || !dt.isFinite || dt <= 0) return;
    dt = dt.clamp(0, 0.05);
    elapsed += dt;
    invulnerable = math.max(0, invulnerable - dt);
    playerX += (targetX - playerX) * (1 - math.exp(-18 * dt));
    _spawn -= dt;
    if (_spawn <= 0) {
      final double difficulty = (elapsed / roundSeconds).clamp(0, 1);
      objects.add(
        AuroraObject(
          0.08 + _random.nextDouble() * 0.84,
          -0.07,
          0.25 + difficulty * 0.22 + _random.nextDouble() * 0.06,
          meteor: _random.nextDouble() < 0.28 + difficulty * 0.12,
        ),
      );
      _spawn = 0.42 - difficulty * 0.15;
    }
    for (int i = objects.length - 1; i >= 0; i--) {
      final AuroraObject object = objects[i];
      object.y += object.speed * dt;
      if ((object.x - playerX).abs() < 0.075 &&
          (object.y - 0.82).abs() < 0.045) {
        if (object.meteor) {
          if (invulnerable <= 0) {
            lives--;
            combo = 0;
            invulnerable = 1.1;
          }
        } else {
          combo++;
          bestCombo = math.max(bestCombo, combo);
          score += 10 * math.min(combo, 8);
        }
        objects.removeAt(i);
      } else if (object.y > 1.08) {
        if (!object.meteor) combo = 0;
        objects.removeAt(i);
      }
    }
    if (lives <= 0 || elapsed >= roundSeconds) {
      finished = true;
      running = false;
    }
    notifyListeners();
  }
}
