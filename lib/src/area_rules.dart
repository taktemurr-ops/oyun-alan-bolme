import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/stats.dart';

import 'area_engine.dart';

const alanBolmeId = 'oyun-alan-bolme';

class AreaRules extends GameRules<AreaLevel> {
  /// Üretim + çözücü türü: 100.000 bölüm.
  @override
  int get levelCount => 100000;

  @override
  String get gameId => alanBolmeId;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('areas_drawn', 'Çizilen alan', 'Areas drawn', scale: 60),
        GameStat('boards_split', 'Bölünen tahta', 'Boards split', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('areas', 'areas_drawn', [20, 60, 150]),
        MissionTemplate('boards', 'boards_split', [3, 6, 12]),
      ];

  @override
  AreaLevel generate(LevelSpec spec) => generateAreaLevel(spec);

  @override
  Validation validate(AreaLevel level, LevelSpec spec) {
    final cells = level.solution.fold(0, (s, r) => s + r.area);
    if (cells != level.w * level.h) return const Validation.fail('not covered');
    final g = AreaGame(level)..rects = [...level.solution];
    if (!g.won) return const Validation.fail('solution invalid');
    return Validation.ok(level.solution.length);
  }

  /// Yıldız: ipucusuz ve az düzeltmeyle.
  static int stars(AreaGame g, int hints) {
    if (!g.won) return 0;
    final extra = g.moves - g.level.solution.length;
    if (hints == 0 && extra <= 2) return 3;
    return extra <= g.level.solution.length ? 2 : 1;
  }
}
