import 'dart:convert';

import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Alan Bölme: tahtayı dikdörtgen bloklara böl. Her blokta tam bir sayı
/// olmalı ve sayı bloğun kaç kare olduğunu söyler. Bütün tahta kaplanınca
/// bölüm biter.

class ARect {
  final int x, y, w, h;
  const ARect(this.x, this.y, this.w, this.h);
  int get area => w * h;
  bool contains(int cx, int cy) => cx >= x && cy >= y && cx < x + w && cy < y + h;
  bool overlaps(ARect o) => x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
  Iterable<int> cells(int bw) sync* {
    for (var j = y; j < y + h; j++) {
      for (var i = x; i < x + w; i++) {
        yield j * bw + i;
      }
    }
  }

  @override
  bool operator ==(Object o) => o is ARect && o.x == x && o.y == y && o.w == w && o.h == h;
  @override
  int get hashCode => Object.hash(x, y, w, h);
  List<int> toJson() => [x, y, w, h];
  static ARect fromJson(List<dynamic> j) =>
      ARect((j[0] as num).toInt(), (j[1] as num).toInt(), (j[2] as num).toInt(), (j[3] as num).toInt());
}

class AreaLevel {
  final int w, h;
  final Map<int, int> clues; // hücre -> alan
  final List<ARect> solution;
  final int seed, difficulty;
  final bool unique;
  const AreaLevel({
    required this.w,
    required this.h,
    required this.clues,
    required this.solution,
    required this.seed,
    required this.difficulty,
    this.unique = false,
  });
}

/// Bir ipucu sayısını içerebilecek bütün dikdörtgenler (başka sayı içermeyen).
List<ARect> candidatesFor(int w, int h, Map<int, int> clues, int cell) {
  final area = clues[cell]!;
  final cx = cell % w, cy = cell ~/ w;
  final out = <ARect>[];
  for (var rw = 1; rw <= area; rw++) {
    if (area % rw != 0) continue;
    final rh = area ~/ rw;
    if (rw > w || rh > h) continue;
    for (var x = cx - rw + 1; x <= cx; x++) {
      for (var y = cy - rh + 1; y <= cy; y++) {
        if (x < 0 || y < 0 || x + rw > w || y + rh > h) continue;
        final r = ARect(x, y, rw, rh);
        var ok = true;
        for (final c in r.cells(w)) {
          if (c != cell && clues.containsKey(c)) {
            ok = false;
            break;
          }
        }
        if (ok) out.add(r);
      }
    }
  }
  return out;
}

/// Çözüm sayısı (en çok [limit] kadar sayar). Düğüm sınırı aşılırsa -1.
int countSolutions(int w, int h, Map<int, int> clues, {int limit = 2, int nodeCap = 40000}) {
  final cand = {for (final c in clues.keys) c: candidatesFor(w, h, clues, c)};
  final covered = List<bool>.filled(w * h, false);
  final used = <int>{};
  var found = 0, nodes = 0;
  var aborted = false;

  bool fits(ARect r) => r.cells(w).every((c) => !covered[c]);

  void rec() {
    if (found >= limit || aborted) return;
    if (++nodes > nodeCap) {
      aborted = true;
      return;
    }
    final first = covered.indexOf(false);
    if (first < 0) {
      found++;
      return;
    }
    final fx = first % w, fy = first ~/ w;
    for (final clue in clues.keys) {
      if (used.contains(clue)) continue;
      for (final r in cand[clue]!) {
        if (!r.contains(fx, fy) || !fits(r)) continue;
        for (final c in r.cells(w)) {
          covered[c] = true;
        }
        used.add(clue);
        rec();
        used.remove(clue);
        for (final c in r.cells(w)) {
          covered[c] = false;
        }
        if (found >= limit || aborted) return;
      }
    }
  }

  rec();
  return aborted ? -1 : found;
}

AreaLevel generateAreaLevel(LevelSpec spec) {
  final r = SeededRandom(mixSeed([spec.seed, 9041]));
  final d = spec.difficulty.clamp(1, 10);
  final w = (4 + (d + 1) ~/ 2).clamp(5, 9), h = (5 + d ~/ 2).clamp(5, 10);
  final maxA = 4 + d ~/ 2 + (d >= 7 ? 2 : 0);
  AreaLevel? fallback;
  for (var attempt = 0; attempt < 40; attempt++) {
    final owner = List<int>.filled(w * h, -1);
    final rects = <ARect>[];
    for (var cell = 0; cell < w * h; cell++) {
      if (owner[cell] >= 0) continue;
      final cx = cell % w, cy = cell ~/ w;
      // En çok genişlik: sağdaki boş kareler.
      var maxW = 0;
      while (cx + maxW < w && owner[cy * w + cx + maxW] < 0) {
        maxW++;
      }
      final opts = <ARect>[];
      for (var rw = 1; rw <= maxW; rw++) {
        for (var rh = 1; cy + rh <= h; rh++) {
          if (rw * rh > maxA) break;
          var free = true;
          for (var i = 0; i < rw && free; i++) {
            if (owner[(cy + rh - 1) * w + cx + i] >= 0) free = false;
          }
          if (!free) break;
          if (rw * rh >= 2) opts.add(ARect(cx, cy, rw, rh));
        }
      }
      // Büyük blokları biraz kayır.
      ARect pickR;
      if (opts.isEmpty) {
        pickR = ARect(cx, cy, 1, 1);
      } else {
        opts.sort((a, b) => b.area.compareTo(a.area));
        final top = (opts.length * 0.6).ceil().clamp(1, opts.length);
        pickR = opts[r.nextInt(top)];
      }
      for (final c in pickR.cells(w)) {
        owner[c] = rects.length;
      }
      rects.add(pickR);
    }
    final ones = rects.where((x) => x.area == 1).length;
    if (ones > 1 + d ~/ 4) continue;
    final clues = <int, int>{};
    for (final rc in rects) {
      final cells = rc.cells(w).toList();
      clues[cells[r.nextInt(cells.length)]] = rc.area;
    }
    final n = countSolutions(w, h, clues);
    final lvl = AreaLevel(w: w, h: h, clues: clues, solution: rects, seed: spec.seed, difficulty: d, unique: n == 1);
    if (n == 1) return lvl;
    fallback ??= lvl;
  }
  return fallback!;
}

class AreaGame {
  final AreaLevel level;
  List<ARect> rects = [];
  int moves = 0;
  final List<String> _history = [];

  AreaGame(this.level);

  int get w => level.w;
  int get h => level.h;

  /// Dikdörtgende tam bir sayı var ve alan ona eşit mi?
  bool correct(ARect r) {
    var n = 0, val = 0;
    for (final c in r.cells(w)) {
      final v = level.clues[c];
      if (v != null) {
        n++;
        val = v;
      }
    }
    return n == 1 && val == r.area;
  }

  int get coveredCells => rects.fold(0, (s, r) => s + r.area);

  bool get won => coveredCells == w * h && rects.every(correct);

  int get correctCount => rects.where(correct).length;

  /// İki köşe arasındaki dikdörtgeni koy; üstüne geldiği blokları kaldırır.
  ARect place(int x0, int y0, int x1, int y1) {
    final r = ARect(x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1, (x1 - x0).abs() + 1, (y1 - y0).abs() + 1);
    _history.add(serialize());
    rects = [for (final o in rects) if (!o.overlaps(r)) o, r];
    moves++;
    return r;
  }

  /// Kareye dokunulursa oradaki bloğu kaldırır.
  bool removeAt(int x, int y) {
    final i = rects.indexWhere((r) => r.contains(x, y));
    if (i < 0) return false;
    _history.add(serialize());
    rects = [...rects]..removeAt(i);
    moves++;
    return true;
  }

  /// İpucu: çözümde olup tahtada henüz bulunmayan bir blok.
  ARect? hint() {
    for (final s in level.solution) {
      if (!rects.contains(s)) return s;
    }
    return null;
  }

  void applyHint(ARect s) {
    _history.add(serialize());
    rects = [for (final o in rects) if (!o.overlaps(s)) o, s];
  }

  bool get canUndo => _history.isNotEmpty;

  void undo() {
    if (_history.isEmpty) return;
    _load(jsonDecode(_history.removeLast()) as Map<String, dynamic>);
  }

  String serialize() => jsonEncode({
        'r': [for (final r in rects) r.toJson()],
        'm': moves,
      });

  void _load(Map<String, dynamic> j) {
    rects = [for (final e in j['r'] as List) ARect.fromJson(e as List)];
    moves = (j['m'] as num).toInt();
  }

  static AreaGame restore(AreaLevel l, String snap) {
    final g = AreaGame(l);
    g._load(jsonDecode(snap) as Map<String, dynamic>);
    return g;
  }
}
