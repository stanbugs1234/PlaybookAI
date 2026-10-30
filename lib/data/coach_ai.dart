import 'package:cloud_functions/cloud_functions.dart';

import '../explain/explainer.dart';
import '../models/play.dart';
import '../sim/sim_types.dart';
import 'backend.dart';

/// Asks the `explainPlay` Cloud Function (which calls Claude) for a
/// coach-voice breakdown of a simulated rep.
abstract final class CoachAi {
  static bool get available => Backend.firebaseReady;

  static Map<String, dynamic> summarize(SimResult r, Explanation e) {
    final play = r.play;
    return {
      'play': {
        'name': play.name,
        'formation': play.formation,
        'type': play.playType.name,
        'drop': play.drop.name,
        'routes': {
          for (final p in play.players)
            if (p.role != Role.ol && p.role != Role.qb)
              p.label: switch (play.assignments[p.id]) {
                RouteAssignment(:final name) => name ?? 'Custom route',
                RunAssignment(:final name) => 'Run: ${name ?? 'custom'}',
                _ => 'Block',
              },
        },
        'progression': [
          for (final id in play.progression) play.playerOrNull(id)?.label ?? id,
        ],
        'notes': play.notes,
      },
      'defense': {
        'call': r.call.label,
        'assignments': [
          for (final d in r.defenders) '${d.label}: ${d.assignment.description}',
        ],
      },
      'preSnap': e.preSnap,
      'timeline': [
        for (final s in e.steps) '${s.t.toStringAsFixed(2)}s ${s.title}: ${s.detail}',
      ],
      'outcome': r.outcome.label,
      'summary': e.summary,
    };
  }

  static Future<String> explain(SimResult r, Explanation e) async {
    if (!available) {
      throw StateError(
          'Coach AI needs Firebase. Run `flutterfire configure` and deploy the functions.');
    }
    final callable = FirebaseFunctions.instance.httpsCallable('explainPlay',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));
    final res = await callable.call<Map<String, dynamic>>(summarize(r, e));
    return (res.data['text'] as String?) ?? 'No response.';
  }
}
