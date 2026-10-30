import 'play.dart';
import 'vec.dart';

/// A route template expressed as (outside, downfield) offsets from the
/// receiver's alignment. "Outside" points toward the receiver's sideline, so
/// the same template works for receivers on either side of the ball.
class RouteTemplate {
  final String name;
  final List<(double, double)> offsets;
  final String description;
  final bool backfieldOnly;

  const RouteTemplate(this.name, this.offsets, this.description,
      {this.backfieldOnly = false});

  RouteAssignment apply(Vec start, {bool? toRight}) {
    final outSign = (toRight ?? start.x >= Field.center) ? 1.0 : -1.0;
    // Routes are measured from the line of scrimmage, not from a player's
    // stagger, so a slot off the ball still breaks at the right depth.
    final baseY = start.y.clamp(-1.5, 0.0);
    return RouteAssignment(
      name: name,
      waypoints: [
        for (final (o, d) in offsets)
          Vec(start.x + o * outSign, (d <= 0 ? start.y : baseY) + d)
              .clampToField(),
      ],
    );
  }
}

abstract final class RouteTree {
  static const all = <RouteTemplate>[
    RouteTemplate('Flat', [(3, 1), (9, 2.5)], 'Quick release to the flat'),
    RouteTemplate('Slant', [(0, 1.5), (-7, 7)], '1-step then 45° inside'),
    RouteTemplate('Hitch', [(0, 6), (0, 5)], '6 yds, snap back to QB'),
    RouteTemplate('Stick', [(0, 5), (-1, 5.5)], 'Settle at 5 in the void'),
    RouteTemplate('Out', [(0, 10), (9, 10)], '10 yd square-out'),
    RouteTemplate('Quick Out', [(0, 5), (7, 5)], '5 yd speed out'),
    RouteTemplate('Curl', [(0, 12), (-1.5, 10.5)], '12 yds, curl back inside'),
    RouteTemplate('Comeback', [(0, 15), (3, 12.5)], '15 yds, back to sideline'),
    RouteTemplate('Dig', [(0, 12), (-14, 12)], '12 yd square-in'),
    RouteTemplate('Drag', [(-2, 2), (-20, 3.5)], 'Shallow cross underneath'),
    RouteTemplate('Deep Cross', [(-2, 6), (-24, 15)], 'Crossing route at 15'),
    RouteTemplate('Post', [(0, 11), (-8, 24)], '11 yds, break to the post'),
    RouteTemplate('Corner', [(0, 11), (8, 21)], '11 yds, break to the pylon'),
    RouteTemplate('Go', [(0, 8), (0, 30)], 'Vertical, win over the top'),
    RouteTemplate('Seam', [(-1, 8), (-1.5, 28)], 'Vertical up the hash'),
    RouteTemplate('Fade', [(2, 8), (4, 28)], 'Vertical, bend to sideline'),
    RouteTemplate('Wheel', [(5, 1), (9, 4), (9, 25)], 'Out to flat then up'),
    RouteTemplate('Swing', [(3, -0.5), (8, 0.5), (11, 2)], 'Arc to the flat',
        backfieldOnly: true),
    RouteTemplate('Angle', [(3, 1), (0.5, 6)], 'Out, then cut back inside',
        backfieldOnly: true),
    RouteTemplate('Check Release', [(1, 1.5), (0, 4)],
        'Check protection, release to the void',
        backfieldOnly: true),
  ];

  static RouteTemplate? byName(String name) {
    for (final r in all) {
      if (r.name == name) return r;
    }
    return null;
  }
}

/// Ball-carrier path presets for run plays.
class RunTemplate {
  final String name;
  final List<(double, double)> offsets; // (toward play side, downfield)
  final String description;
  const RunTemplate(this.name, this.offsets, this.description);

  RunAssignment apply(Vec start, {required bool toRight}) {
    final s = toRight ? 1.0 : -1.0;
    return RunAssignment(
      name: name,
      path: [
        for (final (o, d) in offsets)
          Vec(start.x + o * s, d < 0 ? start.y - d : d).clampToField(),
      ],
    );
  }
}

abstract final class RunTree {
  // Negative "downfield" values are interpreted as yards relative to the
  // runner's start depth (moving toward the line), positive as absolute depth.
  static const all = <RunTemplate>[
    RunTemplate('Dive', [(1, -2.5), (1, 1), (1, 8)], 'A/B gap downhill'),
    RunTemplate('Inside Zone', [(2, -2), (3, 0.5), (2.5, 8)],
        'Aim at guard, read the cutback'),
    RunTemplate('Outside Zone', [(5, -1.5), (8, 0), (9, 7)],
        'Stretch to the edge, one cut'),
    RunTemplate('Power', [(1, -1.5), (3.6, 0.3), (4, 8)],
        'Downhill off the backside guard pull'),
    RunTemplate('Toss', [(9, -0.5), (13, 1), (14, 8)], 'Pitch to the perimeter'),
  ];

  static RunTemplate? byName(String name) {
    for (final r in all) {
      if (r.name == name) return r;
    }
    return null;
  }
}
