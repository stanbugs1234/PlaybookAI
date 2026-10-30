import 'package:flutter_test/flutter_test.dart';
import 'package:playbook_ai/explain/explainer.dart';
import 'package:playbook_ai/models/defense.dart';
import 'package:playbook_ai/models/play.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:playbook_ai/sim/sim_engine.dart';

void main() {
  test('explains every starter vs every coverage without throwing', () {
    for (final play in StarterPlays.all()) {
      for (final cov in Coverage.values) {
        final e = Explainer.explain(SimEngine.run(play, DefenseCall(Front.nickel, cov)));
        expect(e.summary, isNotEmpty);
        expect(e.tips, isNotEmpty);
        expect(e.preSnap, isNotEmpty);
      }
    }
  });

  test('identifies the safety shell', () {
    final play = StarterPlays.all().first;
    String shell(Coverage c) =>
        Explainer.explain(SimEngine.run(play, DefenseCall(Front.nickel, c))).shell;
    expect(shell(Coverage.cover2), contains('Two-high'));
    expect(shell(Coverage.cover3), contains('One-high'));
    expect(shell(Coverage.cover0), contains('Zero-high'));
  });

  test('a throw step names the target and is marked good', () {
    final play = StarterPlays.all().firstWhere((p) => p.name == 'Smash');
    final e = Explainer.explain(SimEngine.run(play, const DefenseCall(Front.nickel, Coverage.cover2)));
    final throwStep = e.steps.firstWhere((s) => s.kind == StepKind.decision);
    expect(throwStep.good, isTrue);
    expect(throwStep.focusId, isNotNull);
    expect(throwStep.title, startsWith('Throw:'));
  });

  test('play JSON round-trips', () {
    for (final p in StarterPlays.all()) {
      final back = Play.fromJson(p.toJson());
      expect(back.toJson(), p.toJson());
    }
  });
}
