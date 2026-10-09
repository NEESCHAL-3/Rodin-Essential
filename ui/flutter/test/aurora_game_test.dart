import 'package:flutter_test/flutter_test.dart';
import 'package:rodin_essential_ui/aurora_game_engine.dart';

void main() {
  test('collecting stars builds real score and combos', () {
    final AuroraGame game = AuroraGame(seed: 1)..start();
    game.objects.add(AuroraObject(0.5, 0.82, 0, meteor: false));
    game.advance(0.016);
    expect(game.score, 10);
    game.objects.add(AuroraObject(0.5, 0.82, 0, meteor: false));
    game.advance(0.016);
    expect(game.score, 30);
    expect(game.bestCombo, 2);
    game.dispose();
  });
  test('meteors cost a life, with a short protection window', () {
    final AuroraGame game = AuroraGame(seed: 1)..start();
    game.objects.add(AuroraObject(0.5, 0.82, 0, meteor: true));
    game.advance(0.016);
    expect(game.lives, 2);
    game.objects.add(AuroraObject(0.5, 0.82, 0, meteor: true));
    game.advance(0.016);
    expect(game.lives, 2);
    game.dispose();
  });
  test('pause freezes the round and restart clears the previous score', () {
    final AuroraGame game = AuroraGame(seed: 1)..start();
    game.advance(0.02);
    final double elapsed = game.elapsed;
    game.pause();
    game.advance(10);
    expect(game.elapsed, elapsed);
    game.resume();
    game.advance(0.02);
    expect(game.elapsed, greaterThan(elapsed));
    game.start();
    expect(game.score, 0);
    expect(game.lives, 3);
    game.dispose();
  });
  test('round ends after 30 seconds and steering is bounded', () {
    final AuroraGame game = AuroraGame(seed: 1)..start();
    game.steer(-5);
    expect(game.targetX, 0.07);
    game.steer(5);
    expect(game.targetX, 0.93);
    for (int i = 0; i < 601; i++) {
      game.objects.clear();
      game.advance(0.05);
    }
    expect(game.finished, true);
    expect(game.running, false);
    final double elapsed = game.elapsed;
    game.advance(0.05);
    expect(game.elapsed, elapsed);
    game.dispose();
  });
}
