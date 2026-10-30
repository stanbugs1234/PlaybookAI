// ignore_for_file: avoid_print
// Prints how each starter play fares against each coverage.
// Usage: dart run tool/sim_report.dart [runs]
import 'package:playbook_ai/models/defense.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:playbook_ai/sim/sim_engine.dart';
import 'package:playbook_ai/sim/sim_types.dart';

void main(List<String> args) {
  final runs = args.isEmpty ? 30 : int.parse(args.first);
  for (final play in StarterPlays.all()) {
    print('\n=== ${play.name} (${play.formation}) ===');
    for (final cov in Coverage.values) {
      final call = DefenseCall(Front.nickel, cov);
      var yards = 0.0, comp = 0, ints = 0, sacks = 0, aways = 0;
      final targets = <String, int>{};
      var ttt = 0.0, throws = 0;
      for (var seed = 1; seed <= runs; seed++) {
        final r = SimEngine.run(play, call, seed: seed);
        final o = r.outcome;
        yards += o.yards;
        if (o.type == OutcomeType.complete || o.type == OutcomeType.touchdown) comp++;
        if (o.type == OutcomeType.interception) ints++;
        if (o.type == OutcomeType.sack) sacks++;
        if (o.type == OutcomeType.throwAway) aways++;
        if (o.targetId != null) targets[o.targetId!] = (targets[o.targetId!] ?? 0) + 1;
        if (o.timeToThrow != null) { ttt += o.timeToThrow!; throws++; }
      }
      print('${cov.label.padRight(8)} avg ${(yards / runs).toStringAsFixed(1).padLeft(5)} '
          'comp ${(100 * comp / runs).round()}% int $ints sack $sacks away $aways '
          'ttt ${throws == 0 ? '-' : (ttt / throws).toStringAsFixed(2)} targets $targets');
    }
  }
}
