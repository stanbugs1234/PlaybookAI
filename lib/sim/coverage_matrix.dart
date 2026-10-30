import '../models/defense.dart';
import '../models/play.dart';
import 'sim_engine.dart';
import 'sim_types.dart';

class MatrixRow {
  final DefenseCall call;
  final int runs;
  final double avgYards;
  final double completionPct;
  final double successPct;
  final double turnoverPct;
  final double sackPct;
  final double firstReadOpenPct;
  final String? topTarget;

  const MatrixRow({
    required this.call,
    required this.runs,
    required this.avgYards,
    required this.completionPct,
    required this.successPct,
    required this.turnoverPct,
    required this.sackPct,
    required this.firstReadOpenPct,
    required this.topTarget,
  });
}

/// Runs a play many times against every coverage to grade it.
abstract final class CoverageMatrix {
  static List<MatrixRow> run(Play play,
      {Front front = Front.nickel, int runs = 25, Blitz blitz = Blitz.none}) {
    return [
      for (final cov in Coverage.values)
        _row(play, DefenseCall(front, cov, blitz), runs),
    ];
  }

  static MatrixRow _row(Play play, DefenseCall call, int runs) {
    var yards = 0.0;
    var comp = 0, success = 0, turnovers = 0, sacks = 0, firstOpen = 0, attempts = 0;
    final targets = <String, int>{};
    for (var seed = 1; seed <= runs; seed++) {
      final r = SimEngine.run(play, call, seed: seed);
      final o = r.outcome;
      yards += o.yards;
      if (o.isSuccess) success++;
      if (o.type == OutcomeType.interception) turnovers++;
      if (o.type == OutcomeType.sack) sacks++;
      final thrown = r.events.any((e) => e.type == EventType.throwBall);
      if (thrown) attempts++;
      if (o.type == OutcomeType.complete ||
          (o.type == OutcomeType.touchdown && thrown)) {
        comp++;
      }
      final firstThrow =
          r.events.where((e) => e.type == EventType.throwBall).firstOrNull;
      if (firstThrow != null && firstThrow.readIndex == 0) firstOpen++;
      if (o.targetId != null) targets[o.targetId!] = (targets[o.targetId!] ?? 0) + 1;
    }
    String? top;
    var topN = 0;
    targets.forEach((k, v) {
      if (v > topN) {
        topN = v;
        top = k;
      }
    });
    return MatrixRow(
      call: call,
      runs: runs,
      avgYards: yards / runs,
      completionPct: attempts == 0 ? 0 : 100 * comp / attempts,
      successPct: 100 * success / runs,
      turnoverPct: 100 * turnovers / runs,
      sackPct: 100 * sacks / runs,
      firstReadOpenPct: 100 * firstOpen / runs,
      topTarget: top,
    );
  }
}
