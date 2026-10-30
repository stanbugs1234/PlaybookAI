// ignore_for_file: avoid_print
// Prints a frame-by-frame trace of one play for debugging the engine.
// Usage: dart run tool/sim_trace.dart "<play name>" <coverage> [seed]
import 'package:playbook_ai/models/defense.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:playbook_ai/sim/sim_engine.dart';

void main(List<String> args) {
  final play = StarterPlays.all().firstWhere((p) => p.name == args[0]);
  final cov = Coverage.values.byName(args[1]);
  final seed = args.length > 2 ? int.parse(args[2]) : 1;
  final r = SimEngine.run(play, DefenseCall(Front.nickel, cov), seed: seed);
  for (final d in r.defenders) {
    print('${d.id.padRight(8)} ${d.label.padRight(4)} ${d.pos} ${d.assignment.description}');
  }
  for (final e in r.events) {
    print('t=${e.t.toStringAsFixed(2)} ${e.type.name} p=${e.playerId} d=${e.defenderId} '
        '${e.eval == null ? '' : 'win=${e.eval!.window.toStringAsFixed(1)} ${e.eval!.reason.name} by ${e.eval!.limitingDefenderId}'}');
  }
  final ids = args.length > 3 ? args[3].split(',') : <String>[];
  for (var i = 0; i < r.frames.length; i += 4) {
    final f = r.frames[i];
    print('${f.t.toStringAsFixed(2)} ball=${f.ball} c=${f.carrierId} '
        '${ids.map((id) => '$id=${f.pos[id]}').join(' ')}');
  }
  print(r.outcome.label);
}
