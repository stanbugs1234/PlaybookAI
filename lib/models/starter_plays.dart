import 'formations.dart';
import 'play.dart';
import 'route_tree.dart';
import 'vec.dart';

/// Classic concepts every coach knows, used to seed a new playbook.
abstract final class StarterPlays {
  static Play blank(String formation, {String? id, String name = 'New Play'}) {
    return build(
      id: id ?? 'play_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      formation: formation,
      routes: const {},
      progression: const [],
    );
  }

  /// Builds a play from a formation and route names. Players without a route
  /// or run block (OL always block; unlisted eligibles run a Go, backs block).
  static Play build({
    required String id,
    required String name,
    required String formation,
    required Map<String, String> routes,
    required List<String> progression,
    PlayType type = PlayType.pass,
    QbDrop drop = QbDrop.threeStep,
    String? run,
    bool runRight = true,
    Map<String, List<Vec>> custom = const {},
    String notes = '',
  }) {
    final players = Formations.build(formation);
    final asg = <String, Assignment>{};
    for (final p in players) {
      if (p.role == Role.qb) continue;
      if (p.role == Role.ol) {
        asg[p.id] = const BlockAssignment();
        continue;
      }
      final custom0 = custom[p.id];
      if (custom0 != null) {
        asg[p.id] = RouteAssignment(name: 'Custom', waypoints: custom0);
        continue;
      }
      final r = routes[p.id];
      if (r == 'Block') {
        asg[p.id] = const BlockAssignment();
      } else if (r != null && RunTree.byName(r) != null) {
        asg[p.id] = RunTree.byName(r)!.apply(p.pos, toRight: runRight);
      } else if (r != null && RouteTree.byName(r) != null) {
        asg[p.id] = RouteTree.byName(r)!.apply(p.pos);
      } else if (p.role == Role.rb || p.role == Role.fb) {
        asg[p.id] = const BlockAssignment();
      } else {
        asg[p.id] = RouteTree.byName('Go')!.apply(p.pos);
      }
    }
    if (run != null) {
      final runner = players.firstWhere((p) => p.id == 'f');
      asg['f'] = RunTree.byName(run)!.apply(runner.pos, toRight: runRight);
    }
    return Play(
      id: id,
      name: name,
      formation: formation,
      playType: type,
      drop: drop,
      players: players,
      assignments: asg,
      progression: progression,
      notes: notes,
      updatedAt: DateTime.now(),
    );
  }

  static List<Play> all() => [
        build(
          id: 'starter_four_verts',
          name: 'Four Verts',
          formation: 'Gun Doubles',
          routes: {'x': 'Go', 'h': 'Seam', 'y': 'Seam', 'z': 'Go', 'f': 'Check Release'},
          progression: ['y', 'h', 'z', 'x', 'f'],
          drop: QbDrop.fiveStep,
          notes: 'Stress the deep safeties: seams vs 1-high, outside vs 2-high.',
        ),
        build(
          id: 'starter_smash',
          name: 'Smash',
          formation: 'Gun Doubles',
          routes: {'x': 'Hitch', 'h': 'Corner', 'y': 'Corner', 'z': 'Hitch', 'f': 'Check Release'},
          progression: ['y', 'z', 'h', 'x', 'f'],
          notes: 'High-low the corner: corner route over the hitch. A Cover 2 beater.',
        ),
        build(
          id: 'starter_mesh',
          name: 'Mesh',
          formation: 'Gun Doubles',
          routes: {'x': 'Dig', 'h': 'Drag', 'z': 'Corner', 'f': 'Swing'},
          custom: {
            'y': const [Vec(38, 2), Vec(22, 5.5), Vec(10, 6)],
          },
          progression: ['h', 'y', 'f', 'z'],
          notes: 'Two shallow crossers rub man defenders; sit in the hole vs zone.',
        ),
        build(
          id: 'starter_flood',
          name: 'Flood',
          formation: 'Gun Trips Right',
          routes: {'z': 'Go', 'h': 'Out', 'y': 'Flat', 'x': 'Dig', 'f': 'Check Release'},
          progression: ['h', 'y', 'x', 'f'],
          drop: QbDrop.fiveStep,
          notes: 'Three levels to one side: overload the flat and curl defenders.',
        ),
        build(
          id: 'starter_slant_flat',
          name: 'Slant-Flat',
          formation: 'Gun Trips Right',
          routes: {'z': 'Slant', 'h': 'Flat', 'y': 'Stick', 'x': 'Slant', 'f': 'Block'},
          progression: ['z', 'h', 'y', 'x'],
          drop: QbDrop.quick,
          notes: 'Quick game. Read the flat defender: he widens, throw the slant.',
        ),
        build(
          id: 'starter_y_cross',
          name: 'Y-Cross',
          formation: 'Gun Trey (TE)',
          routes: {'x': 'Go', 'h': 'Post', 'y': 'Deep Cross', 'z': 'Comeback', 'f': 'Swing'},
          progression: ['y', 'x', 'z', 'f'],
          drop: QbDrop.fiveStep,
          notes: 'Clear the backside with the go; hit the cross in the vacated area.',
        ),
        build(
          id: 'starter_pa_post',
          name: 'PA Post-Dig',
          formation: 'I-Form Pro',
          type: PlayType.playAction,
          drop: QbDrop.fiveStep,
          routes: {'z': 'Post', 'x': 'Dig', 'y': 'Drag', 'h': 'Block'},
          run: 'Inside Zone',
          progression: ['z', 'x', 'y'],
          notes: 'Hold the linebackers with the run fake, throw behind them.',
        ),
        build(
          id: 'starter_inside_zone',
          name: 'Inside Zone',
          formation: 'Singleback Ace',
          type: PlayType.run,
          routes: {'y': 'Block'},
          run: 'Inside Zone',
          progression: const [],
          notes: 'Zone scheme, RB aims at the guard and reads the cutback.',
        ),
        build(
          id: 'starter_power',
          name: 'Power',
          formation: 'I-Form Pro',
          type: PlayType.run,
          routes: {'y': 'Block', 'h': 'Block'},
          run: 'Power',
          progression: const [],
          notes: 'Gap scheme with the fullback leading through the hole.',
        ),
      ];
}
