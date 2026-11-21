import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'area_engine.dart';
import 'area_rules.dart';

class AreaView extends StatefulWidget {
  final PlayContext ctx;
  const AreaView({super.key, required this.ctx});

  @override
  State<AreaView> createState() => _AreaViewState();
}

class _AreaViewState extends State<AreaView> {
  late AreaLevel level;
  late AreaGame game;
  ARect? _hint;
  (int, int)? _from, _to;
  int _seconds = 0, _hints = 0, _undos = 0;
  Timer? _timer;
  bool _ended = false;
  double _cell = 40;

  PlayContext get ctx => widget.ctx;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<AreaLevel>).puzzle;
    final snap = ctx.resume['snap'];
    game = snap is String ? AreaGame.restore(level, snap) : AreaGame(level);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': game.serialize(), 'secs': _seconds, 'hints': _hints});

  (int, int) _cellAt(Offset p) => (
        (p.dx / _cell).floor().clamp(0, level.w - 1),
        (p.dy / _cell).floor().clamp(0, level.h - 1),
      );

  void _after(ARect? placed) {
    if (placed != null) ctx.sfx(game.correct(placed) ? Sfx.place : Sfx.tap);
    setState(() => _hint = null);
    _persist();
    if (game.won) {
      ctx.sfx(Sfx.win);
      _end();
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.finish(RoundResult(
      won: game.won,
      score: (level.w * level.h * 10 - (game.moves - level.solution.length) * 5).clamp(10, 1 << 20),
      stars: AreaRules.stars(game, _hints),
      seconds: _seconds,
      moves: game.moves,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'areas_drawn': game.correctCount, 'boards_split': game.won ? 1 : 0},
    ));
  }

  Future<void> _useHint() async {
    if (_ended || !await ctx.requestHint()) return;
    final s = game.hint();
    if (s == null) return;
    _hints++;
    game.applyHint(s);
    setState(() => _hint = s);
    _persist();
    if (game.won) {
      ctx.sfx(Sfx.win);
      _end();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _cell = math.max(22.0, math.min((cons.maxWidth - 24) / level.w, cons.maxHeight * 0.72 / level.h));
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(
                  Strings.tx(ctx.lang, 'Doldurulan: {0} / {1}', 'Filled: {0} / {1}', [game.coveredCells, level.w * level.h]),
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onPanStart: (d) => setState(() => _from = _to = _cellAt(d.localPosition)),
              onPanUpdate: (d) => setState(() => _to = _cellAt(d.localPosition)),
              onPanEnd: (_) {
                final a = _from, b = _to;
                setState(() => _from = _to = null);
                if (_ended || a == null || b == null) return;
                if (a == b) {
                  if (game.removeAt(a.$1, a.$2)) _after(null);
                  return;
                }
                _after(game.place(a.$1, a.$2, b.$1, b.$2));
              },
              onTapUp: (d) {
                if (_ended) return;
                final (x, y) = _cellAt(d.localPosition);
                // Tek kare: üstünde blok varsa kaldır, yoksa 1'lik blok koy.
                if (game.removeAt(x, y)) {
                  _after(null);
                } else if (level.clues[y * level.w + x] == 1) {
                  _after(game.place(x, y, x, y));
                }
              },
              child: Semantics(
                label: 'board',
                child: SizedBox(
                  width: _cell * level.w,
                  height: _cell * level.h,
                  child: CustomPaint(painter: _Painter(this)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(onPressed: _ended ? null : _useHint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
            IconButton.filledTonal(
                onPressed: game.canUndo && !_ended
                    ? () {
                        setState(() {
                          game.undo();
                          _undos++;
                        });
                        _persist();
                      }
                    : null,
                icon: const Icon(Icons.undo),
                tooltip: ctx.t('undo')),
          ]),
        ),
      ]);
    });
  }
}

class _Painter extends CustomPainter {
  final _AreaViewState v;
  _Painter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final c = v._cell;
    final g = v.game;
    final lv = v.level;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.2)),
        Paint()..color = Colors.black.withValues(alpha: 0.12));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var x = 1; x < lv.w; x++) {
      canvas.drawLine(Offset(x * c, 0), Offset(x * c, size.height), grid);
    }
    for (var y = 1; y < lv.h; y++) {
      canvas.drawLine(Offset(0, y * c), Offset(size.width, y * c), grid);
    }
    for (var i = 0; i < g.rects.length; i++) {
      final r = g.rects[i];
      final rect = Rect.fromLTWH(r.x * c, r.y * c, r.w * c, r.h * c).deflate(c * 0.06);
      final ok = g.correct(r);
      final col = ok
          ? v.ctx.pieceColors[(r.x * 7 + r.y * 13 + r.area) % v.ctx.pieceColors.length]
          : const Color(0xFF9AA1AC);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(c * 0.18));
      canvas.drawRRect(rr, Paint()..color = col.withValues(alpha: ok ? 0.92 : 0.55));
      if (!ok) {
        canvas.drawRRect(
            rr,
            Paint()
              ..color = const Color(0xFFE2574C)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      }
      if (v._hint == r) {
        canvas.drawRRect(
            rr.inflate(2),
            Paint()
              ..color = Colors.amber
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4);
      }
    }
    final a = v._from, b = v._to;
    if (a != null && b != null) {
      final x0 = math.min(a.$1, b.$1), y0 = math.min(a.$2, b.$2);
      final w = (a.$1 - b.$1).abs() + 1, h = (a.$2 - b.$2).abs() + 1;
      final rect = Rect.fromLTWH(x0 * c, y0 * c, w * c, h * c).deflate(c * 0.04);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(c * 0.18)),
          Paint()..color = Colors.white.withValues(alpha: 0.28));
      final tp = TextPainter(
          text: TextSpan(
              text: '${w * h}',
              style: TextStyle(fontSize: c * 0.42, fontWeight: FontWeight.w800, color: Colors.white)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, rect.topRight - Offset(tp.width + 4, -2));
    }
    lv.clues.forEach((cell, val) {
      final center = Offset((cell % lv.w + 0.5) * c, (cell ~/ lv.w + 0.5) * c);
      canvas.drawCircle(center, c * 0.3, Paint()..color = Colors.white.withValues(alpha: 0.9));
      final tp = TextPainter(
          text: TextSpan(
              text: '$val',
              style: TextStyle(fontSize: c * 0.4, fontWeight: FontWeight.w800, color: const Color(0xFF1E2430))),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
