import 'package:flutter_test/flutter_test.dart';
import 'package:playbook_ai/models/defense.dart';
import 'package:playbook_ai/models/play.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:playbook_ai/sim/coverage_matrix.dart';
import 'package:playbook_ai/sim/defense_factory.dart';
import 'package:playbook_ai/sim/sim_engine.dart';
import 'package:playbook_ai/sim/sim_types.dart';

Play starter(String name) => StarterPlays.all().firstWhere((p) => p.name == name);

MatrixRow rowFor(List<MatrixRow> rows, Coverage c) =>
    rows.firstWhere((r) => r.call.coverage == c);

void main() {
  group('DefenseFactory', () {
    test('every call fields 11 defenders', () {
      for (final play in StarterPlays.all()) {
        for (final front in Front.values) {
          for (final cov in Coverage.values) {
            for (final blitz in Blitz.values) {
              final d = DefenseFactory.build(play, DefenseCall(front, cov, blitz));
              expect(d.length, 11, reason: '${play.name} ${front.label} ${cov.label} ${blitz.label}');
              expect(d.map((x) => x.id).toSet().length, 11);
            }
          }
        }
      }
    });

    test('shells match the coverage', () {
      final play = starter('Smash');
      int deep(Coverage c) => DefenseFactory.build(play, DefenseCall(Front.nickel, c))
          .where((d) => d.pos.y > 10)
          .length;
      expect(deep(Coverage.cover2), 2);
      expect(deep(Coverage.cover4), 2);
      expect(deep(Coverage.cover3), 1);
      expect(deep(Coverage.cover1), 1);
      expect(deep(Coverage.cover0), 0);
    });

    test('trips formation reads strength to the trips side', () {
      final f = FormationRead.of(starter('Flood'));
      expect(f.s, 1);
      expect(f.strong.length, 3);
    });
  });

  group('SimEngine', () {
    test('is deterministic for a seed', () {
      final play = starter('Mesh');
      const call = DefenseCall(Front.nickel, Coverage.cover1);
      final a = SimEngine.run(play, call, seed: 7);
      final b = SimEngine.run(play, call, seed: 7);
      expect(a.frames.length, b.frames.length);
      expect(a.outcome.label, b.outcome.label);
      expect(a.frames.last.pos['x'], b.frames.last.pos['x']);
    });

    test('every starter play finishes against every coverage', () {
      for (final play in StarterPlays.all()) {
        for (final cov in Coverage.values) {
          final r = SimEngine.run(play, DefenseCall(Front.nickel, cov));
          expect(r.frames, isNotEmpty);
          expect(r.duration, lessThanOrEqualTo(SimEngine.maxTime + SimEngine.dt));
          expect(r.events.first.type, EventType.snap);
        }
      }
    });

    test('pass plays read the progression in order', () {
      final play = starter('Smash');
      final r = SimEngine.run(play, const DefenseCall(Front.nickel, Coverage.cover2));
      final reads = r.events.where((e) => e.type == EventType.readStart).map((e) => e.playerId).toList();
      expect(reads, isNotEmpty);
      expect(reads, play.progression.take(reads.length).toList());
    });

    test('run plays hand off and never throw', () {
      final r = SimEngine.run(starter('Inside Zone'), const DefenseCall(Front.fourThree, Coverage.cover3));
      expect(r.events.any((e) => e.type == EventType.handoff), isTrue);
      expect(r.events.any((e) => e.type == EventType.throwBall), isFalse);
      expect(r.outcome.type, anyOf(OutcomeType.run, OutcomeType.touchdown));
    });
  });

  group('Concepts beat the coverages they are designed to beat', () {
    test('Smash beats Cover 2', () {
      final rows = CoverageMatrix.run(starter('Smash'), runs: 20);
      expect(rowFor(rows, Coverage.cover2).successPct, greaterThan(70));
      expect(rowFor(rows, Coverage.cover2).avgYards,
          greaterThan(rowFor(rows, Coverage.cover3).avgYards));
    });

    test('Four Verts beats Cover 3 better than Cover 4', () {
      final rows = CoverageMatrix.run(starter('Four Verts'), runs: 20);
      expect(rowFor(rows, Coverage.cover3).avgYards,
          greaterThan(rowFor(rows, Coverage.cover4).avgYards));
    });

    test('a two-high light box runs better than Cover 0', () {
      final rows = CoverageMatrix.run(starter('Inside Zone'), runs: 20);
      expect(rowFor(rows, Coverage.cover2).avgYards,
          greaterThan(rowFor(rows, Coverage.cover0).avgYards));
    });
  });
}
