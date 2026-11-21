import 'package:flutter_test/flutter_test.dart';
import 'package:oyun_alan_bolme/oyun_alan_bolme.dart';
import 'package:studio_core/core/level_plan.dart';

void main() {
  final rules = AreaRules();
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);

  test('bölümler geçerli, çoğu tek çözümlü, ipucuyla çözülür', () {
    var unique = 0;
    final lvs = [1, 12, 50, 99, 230, 777, 2500, 9999, 33333, 49999, 77777, 99999];
    for (final lv in lvs) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      final l = gl.puzzle;
      if (l.unique) unique++;
      // Her blokta tam bir sayı.
      expect(l.clues.length, l.solution.length);
      final g = AreaGame(l);
      var guard = 0;
      while (!g.won && guard++ < 200) {
        g.applyHint(g.hint()!);
      }
      expect(g.won, isTrue, reason: 'bölüm $lv');
    }
    expect(unique, greaterThanOrEqualTo(lvs.length - 2));
  });

  test('çizim, silme, geri al, kayıt', () {
    final l = rules.build(planner.spec(40)).puzzle;
    final g = AreaGame(l);
    final s = l.solution.first;
    g.place(s.x, s.y, s.x + s.w - 1, s.y + s.h - 1);
    expect(g.correct(g.rects.single), isTrue);
    g.place(0, 0, l.w - 1, l.h - 1); // her şeyi kaplar, öncekini kaldırır
    expect(g.rects.length, 1);
    expect(g.correct(g.rects.single), isFalse);
    expect(g.removeAt(0, 0), isTrue);
    expect(g.rects, isEmpty);
    g.undo();
    expect(g.rects.length, 1);
    final r = AreaGame.restore(l, g.serialize());
    expect(r.serialize(), g.serialize());
  });
}
