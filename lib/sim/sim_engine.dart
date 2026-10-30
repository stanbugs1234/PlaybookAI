import 'dart:math' as math;

import '../models/defense.dart';
import '../models/play.dart';
import '../models/vec.dart';
import 'defense_factory.dart';
import 'sim_types.dart';

/// Deterministic, fixed-timestep football play simulator.
///
/// The whole play is simulated up front and returned as a frame timeline, so
/// the UI can animate, scrub and replay without re-running anything.
abstract final class SimEngine {
  static const double dt = 0.05;
  static const double maxTime = 12;

  static SimResult run(Play play, DefenseCall call,
      {int seed = 1, List<Defender>? defenders}) {
    final defs = defenders ?? DefenseFactory.build(play, call);
    return _Sim(play, call, defs, seed).run();
  }
}

/// Routes that stop at the last waypoint rather than continuing on.
const _settleRoutes = {'Hitch', 'Stick', 'Curl', 'Comeback', 'Check Release'};

class _Actor {
  final String id;
  final bool offense;
  double top;

  /// Seconds this player takes to react to what he sees (defense).
  double react = 0.25;
  final OffPlayer? off;
  final Defender? def;
  Vec pos;
  Vec vel = Vec.zero;
  double speed = 0;

  // Route / path following.
  List<Vec> path = const [];
  int wp = 0;
  bool settle = false;
  double jamUntil = 0;
  double traveled = 0;
  double routeLength = 0;

  // Blocking.
  _Actor? blockTarget;
  _Actor? engagedWith;
  double shedAt = double.infinity;
  bool shed = false;

  // Defense.
  bool greenDog = false;
  bool brokeTackleOn = false;
  double rushFrom = 0;

  final List<Vec> history = [];

  _Actor.off(OffPlayer p)
      : id = p.id,
        offense = true,
        top = p.role.topSpeed,
        off = p,
        def = null,
        pos = p.pos;

  _Actor.def(Defender d)
      : id = d.id,
        offense = false,
        top = d.group.topSpeed,
        off = null,
        def = d,
        pos = d.pos;

  bool get isRusher => def?.assignment is Rush || greenDog;
  bool get stalled => engagedWith != null && !shed;

  /// Position [seconds] ago (for reaction delay).
  Vec posAgo(double seconds) {
    final n = (seconds / SimEngine.dt).round();
    if (history.length <= n) return history.isEmpty ? pos : history.first;
    return history[history.length - 1 - n];
  }
}

class _Sim {
  final Play play;
  final DefenseCall call;
  final List<Defender> defenders;
  final int seed;
  final math.Random rng;

  _Sim(this.play, this.call, this.defenders, this.seed)
      : rng = math.Random(seed);

  late final Map<String, _Actor> actors;
  late final List<_Actor> offense;
  late final List<_Actor> defense;
  late final _Actor qb;
  _Actor? runner; // RB on runs / play-action fake
  final frames = <SimFrame>[];
  final events = <SimEvent>[];

  double t = 0;
  int frameIndex = 0;

  // Ball.
  BallState ballState = BallState.held;
  _Actor? carrier;
  Vec ball = Vec.zero;
  double ballHeight = 0;
  Vec? throwFrom;
  _Actor? target;
  double throwT = 0;
  double flightT = 0;
  ReadEval? throwEval;
  bool throwUnderPressure = false;

  // QB brain.
  late final List<_Actor> reads;
  late final double setTime;
  late final Vec setPoint;
  int readIdx = -1;
  bool hot = false;
  String? eyes;
  ReadEval? lastEval;
  bool pressureAnnounced = false;
  bool handedOff = false;
  bool fakeAnnounced = false;
  bool holdsBall = false;

  SimOutcome? outcome;
  double endAt = double.infinity;

  bool get isRun => play.playType == PlayType.run;
  bool get isPA => play.playType == PlayType.playAction;
  double get ballX => play.playerOrNull('c')?.pos.x ?? Field.center;

  void emit(EventType type,
          {String? player, String? defender, int? read, ReadEval? eval}) =>
      events.add(SimEvent(type, t, frameIndex,
          playerId: player, defenderId: defender, readIndex: read, eval: eval));

  double rand(double lo, double hi) => lo + rng.nextDouble() * (hi - lo);

  // ---------------------------------------------------------------------------
  SimResult run() {
    emit(EventType.snap);
    _setup();
    _record();
    while (t < SimEngine.maxTime && t < endAt) {
      t += SimEngine.dt;
      frameIndex++;
      for (final a in actors.values) {
        a.history.add(a.pos);
      }
      _step();
      _record();
    }
    outcome ??= const SimOutcome(OutcomeType.incomplete, 0);
    return SimResult(
      play: play,
      call: call,
      defenders: defenders,
      frames: frames,
      events: events,
      outcome: outcome!,
      seed: seed,
    );
  }

  void _setup() {
    offense = [for (final p in play.players) _Actor.off(p)];
    defense = [for (final d in defenders) _Actor.def(d)];
    actors = {for (final a in [...offense, ...defense]) a.id: a};
    qb = offense.firstWhere((a) => a.off!.role == Role.qb);
    // Every rep is a little different: small per-player speed and
    // reaction-time variance driven by the seed.
    for (final a in [...offense, ...defense]) {
      a.top *= 1 + rand(-0.05, 0.05);
      a.react = a.def?.group == DefGroup.lb ? rand(0.25, 0.45) : rand(0.15, 0.38);
    }
    carrier = qb;
    ball = qb.pos;

    for (final a in offense) {
      switch (play.assignments[a.id]) {
        case RouteAssignment r:
          a.path = r.waypoints;
          a.settle = _settleRoutes.contains(r.name);
          var prev = a.pos;
          for (final w in r.waypoints) {
            a.routeLength += prev.distanceTo(w);
            prev = w;
          }
        case RunAssignment r:
          a.path = r.path;
          runner = a;
        case _:
          break;
      }
    }

    // QB drop.
    final gun = qb.pos.y < -3;
    final dropDepth = gun
        ? 5 + switch (play.drop) {
              QbDrop.quick => 0.5,
              QbDrop.threeStep => 1.2,
              QbDrop.fiveStep => 2.2,
              QbDrop.sevenStep => 3.2,
            }
        : play.drop.depth;
    setPoint = Vec(qb.pos.x, -dropDepth);
    setTime = play.drop.setTime + (isPA ? 0.55 : 0);

    final order = [
      for (final id in play.progression)
        if (actors[id] != null && play.assignments[id] is RouteAssignment)
          actors[id]!,
    ];
    for (final a in offense) {
      if (play.assignments[a.id] is RouteAssignment && !order.contains(a)) {
        order.add(a);
      }
    }
    reads = order;

    // Press jams.
    for (final d in defense) {
      final asg = d.def!.assignment;
      if (asg is ManCover) {
        final r = actors[asg.targetId];
        if (r != null && d.pos.distanceTo(r.pos) < 2.5 && r.off!.role == Role.wr) {
          r.jamUntil = rand(0.25, 0.45);
        }
        if (r != null && play.assignments[r.id] is! RouteAssignment && !isRun) {
          // His man stayed in to block: the defender becomes a green-dog rusher.
          d.greenDog = true;
          d.rushFrom = 0.6;
        }
      }
    }

    if (isRun) {
      _assignRunBlocks();
    } else {
      _assignPassPro();
    }
  }

  List<_Actor> get _blockers => [
        for (final a in offense)
          if (a.off!.role == Role.ol ||
              (play.assignments[a.id] is BlockAssignment && a.off!.role != Role.qb))
            a,
      ];

  void _assignPassPro() {
    final blockers = _blockers;
    final rushers = defense.where((d) => d.isRusher).toList();
    // OL first, then backs/TEs pick up leftovers (usually blitzers).
    final ol = blockers.where((b) => b.off!.role == Role.ol).toList();
    final backs = blockers.where((b) => b.off!.role != Role.ol).toList();
    final unassigned = [...rushers];
    for (final group in [ol, backs]) {
      final pairs = <(double, _Actor, _Actor)>[];
      for (final b in group) {
        for (final r in unassigned) {
          pairs.add(((b.pos.x - r.pos.x).abs() + (r.greenDog ? 3 : 0), b, r));
        }
      }
      pairs.sort((a, b) => a.$1.compareTo(b.$1));
      final used = <_Actor>{};
      for (final (_, b, r) in pairs) {
        if (used.contains(b) || !unassigned.contains(r)) continue;
        b.blockTarget = r;
        used.add(b);
        unassigned.remove(r);
      }
    }
    for (final r in unassigned) {
      hot = true;
      emit(EventType.unblocked, defender: r.id);
    }
  }

  void _assignRunBlocks() {
    final b = ballX;
    final blockers = _blockers;
    final targets = defense
        .where((d) =>
            d.def!.group != DefGroup.db &&
            d.pos.y < 8 &&
            (d.pos.x - b).abs() < 10)
        .toList();
    final pairs = <(double, _Actor, _Actor)>[];
    for (final bl in blockers) {
      for (final d in targets) {
        final lead = bl.off!.role == Role.fb && d.def!.group == DefGroup.lb ? -4 : 0;
        pairs.add((bl.pos.distanceTo(d.pos) + lead, bl, d));
      }
    }
    pairs.sort((x, y) => x.$1.compareTo(y.$1));
    final used = <_Actor>{};
    final taken = <_Actor>{};
    for (final (_, bl, d) in pairs) {
      if (used.contains(bl) || taken.contains(d)) continue;
      bl.blockTarget = d;
      used.add(bl);
      taken.add(d);
    }
  }

  // ---------------------------------------------------------------------------
  void _step() {
    if (ballState == BallState.dead) {
      for (final a in actors.values) {
        _move(a, a.pos + a.vel * 0.3, factor: 0.3);
      }
      return;
    }
    _moveOffense();
    _moveDefense();
    _updateBall();
    if (ballState == BallState.held && carrier == qb && !isRun) _qbBrain();
    if (isRun && !handedOff) _handoff();
    _checkContact();
  }

  void _move(_Actor a, Vec target, {double factor = 1}) {
    final d = target - a.pos;
    final dist = d.length;
    if (dist < 0.05) {
      a.speed = math.max(0, a.speed - 12 * SimEngine.dt);
      a.vel = Vec.zero;
      return;
    }
    final dir = d / dist;
    if (a.vel.length > 0.5) {
      final cos = a.vel.normalized().dot(dir);
      if (cos < 0.7) a.speed *= (0.35 + 0.65 * (cos + 1) / 2).clamp(0.35, 1.0);
    }
    final maxS = a.top * factor * (t < a.jamUntil ? 0.5 : 1);
    a.speed = math.min(maxS, a.speed + 7 * SimEngine.dt);
    if (a.speed > maxS) a.speed = maxS;
    final step = math.min(dist, a.speed * SimEngine.dt);
    final np = a.pos + dir * step;
    a.traveled += step;
    a.vel = (np - a.pos) / SimEngine.dt;
    a.pos = np;
  }

  // ---- Offense ----------------------------------------------------------------
  void _moveOffense() {
    for (final a in offense) {
      if (a == carrier && ballState != BallState.held) {
        _runWithBall(a);
        continue;
      }
      if (a == carrier && a != qb) {
        if (a.wp < a.path.length && a.pos.y < 0.5) {
          _followPath(a);
        } else {
          _runWithBall(a);
        }
        continue;
      }
      if (a == qb) {
        _moveQb();
        continue;
      }
      final asg = play.assignments[a.id];
      if (ballState == BallState.caught && carrier != null) {
        if (carrier!.offense) {
          // After the catch, everyone looks for someone to block.
          _blockForCarrier(a);
        } else {
          _move(a, carrier!.pos, factor: 0.9); // interception: chase
        }
        continue;
      }
      if (a.blockTarget != null || a.off!.role == Role.ol) {
        isRun ? _runBlock(a) : _passBlock(a);
        continue;
      }
      if (asg is RouteAssignment) {
        _followRoute(a);
      } else if (asg is RunAssignment) {
        if (isPA && t > 1.1) {
          _passBlock(a);
        } else {
          _followPath(a);
        }
      } else {
        _passBlock(a);
      }
    }
  }

  void _followRoute(_Actor a) {
    if (a.wp < a.path.length) {
      final target = a.path[a.wp];
      if (a.pos.distanceTo(target) < 0.6) {
        a.wp++;
      }
    }
    if (a.wp < a.path.length) {
      _move(a, a.path[a.wp]);
      return;
    }
    if (a.settle || a.path.isEmpty) {
      _move(a, a.path.isEmpty ? a.pos : a.path.last, factor: 0.4);
      return;
    }
    final prev = a.path.length > 1 ? a.path[a.path.length - 2] : a.off!.pos;
    final dir = (a.path.last - prev).normalized();
    final ext = (a.pos + dir * 6);
    _move(a, Vec(ext.x.clamp(1.0, Field.width - 1), math.min(ext.y, 45)));
  }

  void _followPath(_Actor a) {
    if (a.wp < a.path.length && a.pos.distanceTo(a.path[a.wp]) < 0.7) a.wp++;
    if (a.wp < a.path.length) {
      _move(a, a.path[a.wp], factor: a == carrier ? 1 : 0.9);
    } else {
      _move(a, a.pos + const Vec(0, 3));
    }
  }

  void _moveQb() {
    if (isRun) {
      if (!handedOff) {
        final r = runner;
        _move(qb, r == null ? qb.pos : Vec.lerp(qb.pos, r.pos, 0.5), factor: 0.55);
      } else {
        // Carry out the fake away from the run.
        final away = (runner?.pos.x ?? ballX) > qb.pos.x ? -1 : 1;
        _move(qb, qb.pos + Vec(away * 2.0, -1), factor: 0.5);
      }
      return;
    }
    if (ballState != BallState.held || carrier != qb) {
      _move(qb, qb.pos, factor: 0.3);
      return;
    }
    if (isPA && t < 0.55) {
      final r = runner;
      if (r != null) _move(qb, Vec.lerp(qb.pos, r.pos, 0.4), factor: 0.6);
      if (t >= 0.45 && !fakeAnnounced) {
        fakeAnnounced = true;
        emit(EventType.fake, player: r?.id);
      }
      return;
    }
    if (t < setTime) {
      final remaining = math.max(SimEngine.dt, setTime - t);
      final dist = qb.pos.distanceTo(setPoint);
      final factor = (dist / remaining / qb.top).clamp(0.2, 1.0);
      _move(qb, setPoint, factor: factor);
      return;
    }
    // In the pocket: slide away from the nearest rusher.
    final threat = _nearestRusher();
    if (threat != null && threat.pos.distanceTo(qb.pos) < 4) {
      final away = (qb.pos - threat.pos).normalized();
      _move(qb, qb.pos + Vec(away.x * 1.5, math.min(away.y, 0.6) * 1.5),
          factor: 0.35);
    } else {
      _move(qb, setPoint, factor: 0.2);
    }
  }

  void _passBlock(_Actor a) {
    final r = a.blockTarget;
    final setSpot = Vec(a.off!.pos.x, math.min(a.off!.pos.y, -1.0) - 1.2);
    if (r == null || r.shed && a.engagedWith == r) {
      // Free blocker: help on anyone running free inside 4 yds.
      final loose = defense
          .where((d) =>
              d.isRusher &&
              d.engagedWith == null &&
              d.pos.distanceTo(a.pos) < 4 &&
              _rushActive(d))
          .toList();
      if (loose.isNotEmpty && r == null) {
        a.blockTarget = loose.first;
        if (a.off!.role != Role.ol) emit(EventType.blitzPickup, player: a.id, defender: loose.first.id);
      } else {
        _move(a, setSpot, factor: 0.6);
      }
      return;
    }
    if (a.engagedWith == r) {
      // Stay between the rusher and the QB.
      final toQb = (qb.pos - r.pos).normalized();
      _move(a, r.pos + toQb * 0.9);
      return;
    }
    final intercept = r.pos + (qb.pos - r.pos).normalized() * 1.0;
    _move(a, t < 0.25 ? setSpot : intercept);
    if (a.pos.distanceTo(r.pos) < 1.3 && r.engagedWith == null && _rushActive(r)) {
      a.engagedWith = r;
      r.engagedWith = a;
      final isBack = a.off!.role != Role.ol;
      final dl = r.def!.group == DefGroup.dl;
      r.shedAt = t + (isBack ? rand(1.2, 2.6) : dl ? rand(2.4, 4.4) : rand(2.0, 3.6));
    }
  }

  void _runBlock(_Actor a) {
    final d = a.blockTarget;
    final carrierPos = (carrier ?? runner ?? qb).pos;
    if (d == null) {
      _move(a, a.pos + const Vec(0, 1.5), factor: 0.5);
      return;
    }
    if (a.engagedWith == d && !d.shed) {
      final toBall = (carrierPos - d.pos).normalized();
      _move(a, d.pos + toBall * 0.9);
      return;
    }
    if (d.shed) {
      _move(a, a.pos + const Vec(0, 1), factor: 0.3);
      return;
    }
    final intercept = d.pos + (carrierPos - d.pos).normalized() * 1.0;
    _move(a, intercept);
    if (a.pos.distanceTo(d.pos) < 1.3 && d.engagedWith == null) {
      a.engagedWith = d;
      d.engagedWith = a;
      final weak = a.off!.role != Role.ol;
      d.shedAt = t + (weak ? rand(0.9, 2.0) : rand(1.3, 3.0));
    }
  }

  void _blockForCarrier(_Actor a) {
    final c = carrier!;
    _Actor? nearest;
    var best = double.infinity;
    for (final d in defense) {
      final dist = d.pos.distanceTo(c.pos);
      if (dist < best && d.pos.distanceTo(a.pos) < 8) {
        best = dist;
        nearest = d;
      }
    }
    if (nearest == null) {
      _move(a, c.pos + const Vec(0, 3), factor: 0.8);
    } else {
      _move(a, nearest.pos + (c.pos - nearest.pos).normalized() * 0.8, factor: 0.9);
    }
  }

  void _runWithBall(_Actor a) {
    var dir = Vec(0, a.offense ? 1 : -1);
    for (final d in a.offense ? defense : offense) {
      if (d.stalled) continue;
      final away = a.pos - d.pos;
      final dist = away.length;
      if (dist > 7 || dist < 1e-3) continue;
      final ahead = a.offense ? d.pos.y > a.pos.y - 2 : d.pos.y < a.pos.y + 2;
      if (!ahead) continue;
      dir = dir + Vec(away.x.sign * 2.2 / (dist + 0.5), 0);
    }
    // Keep away from the sideline.
    if (a.pos.x < 3) dir = dir + const Vec(0.8, 0);
    if (a.pos.x > Field.width - 3) dir = dir + const Vec(-0.8, 0);
    _move(a, a.pos + dir.normalized() * 3, factor: 0.84);
  }

  // ---- Defense ----------------------------------------------------------------
  bool _rushActive(_Actor d) => !d.greenDog || t >= d.rushFrom;

  void _moveDefense() {
    final ballAir = ballState == BallState.air;
    final c = carrier;
    final pursuing = ballState == BallState.caught ||
        (c != null && c != qb && c.offense) ||
        (isRun && handedOff);

    for (final d in defense) {
      if (c != null && c == d) {
        _runWithBall(d);
        continue;
      }
      if (d.stalled) {
        if (t >= d.shedAt) {
          d.shed = true;
        } else {
          final goal = pursuing ? c!.pos : qb.pos;
          _move(d, goal, factor: 0.08);
          continue;
        }
      }
      if (ballAir) {
        final react = d.def!.assignment is ManCover ? 0.35 : 0.22;
        if (t - throwT > react) {
          _move(d, _ballLanding());
        } else {
          _cover(d);
        }
        continue;
      }
      if (pursuing && c != null) {
        _pursue(d, c);
        continue;
      }
      if (isRun && !handedOff) {
        _cover(d, runRead: true);
        continue;
      }
      if (d.isRusher) {
        if (_rushActive(d)) {
          _rush(d);
        } else {
          _cover(d);
        }
        continue;
      }
      _cover(d);
    }
  }

  void _pursue(_Actor d, _Actor c) {
    final asg = d.def!.assignment;
    // Man defenders stay with their receivers until the ball crosses the line.
    if (isRun && asg is ManCover && c.pos.y < 0 && ballState == BallState.held) {
      _cover(d);
      return;
    }
    final read = (d.def!.group == DefGroup.db ? 0.8 : 0.45) + d.react;
    if (isRun && t < read && ballState == BallState.held) {
      _cover(d, runRead: true);
      return;
    }
    _move(d, _intercept(d, c), factor: isRun && c.pos.y < 2 ? 0.8 : 1.0);
  }

  /// Pursuit angle: where [d] can meet [c] if [c] keeps his current velocity.
  Vec _intercept(_Actor d, _Actor c) {
    final rel = c.pos - d.pos;
    final v = c.vel;
    final a = v.dot(v) - d.top * d.top;
    final b = 2 * rel.dot(v);
    final cc = rel.dot(rel);
    double? tau;
    if (a.abs() < 1e-6) {
      if (b < 0) tau = -cc / b;
    } else {
      final disc = b * b - 4 * a * cc;
      if (disc >= 0) {
        final sq = math.sqrt(disc);
        final roots = [(-b - sq) / (2 * a), (-b + sq) / (2 * a)]
            .where((r) => r > 0)
            .toList()
          ..sort();
        if (roots.isNotEmpty) tau = roots.first;
      }
    }
    final lead = (tau ?? 1.0).clamp(0.0, 2.5);
    final p = c.pos + v * lead;
    return Vec(p.x.clamp(0.0, Field.width), p.y);
  }

  void _rush(_Actor d) {
    final asg = d.def!.assignment;
    final gap = asg is Rush ? asg.gapX : d.pos.x;
    final factor = d.shed ? 0.85 : 1.0;
    if (d.pos.y > 0.2 && t < 0.6) {
      _move(d, Vec(gap, -0.4), factor: factor);
    } else {
      _move(d, qb.pos, factor: factor);
    }
  }

  void _cover(_Actor d, {bool runRead = false}) {
    final asg = d.def!.assignment;
    switch (asg) {
      case ManCover m:
        final r = actors[m.targetId];
        if (r == null) return;
        final seen = r.posAgo(d.react);
        final inside = r.pos.x >= ballX ? -0.7 : 0.7;
        final overTop = r.pos.y > 12 ? 0.6 : -0.3;
        _move(d, seen + r.vel * 0.3 + Vec(inside, overTop));
      case ZoneCover z:
        _zone(d, z, runRead: runRead);
      case Rush _:
        _rush(d);
    }
  }

  void _zone(_Actor d, ZoneCover z, {bool runRead = false}) {
    var landmark = z.landmark;
    // Play-action: linebackers step up before they drop.
    if (isPA && t < 0.9 && d.def!.group == DefGroup.lb && !z.deep) {
      _move(d, d.def!.pos + const Vec(0, -1.6), factor: 0.6);
      return;
    }
    final fitTime = d.def!.group == DefGroup.lb ? 0.45 : 0.8;
    if (runRead && t > fitTime + d.react && !z.deep) {
      final r = (runner ?? qb).pos;
      _move(d, Vec(r.x, math.max(r.y, 0.8)), factor: 0.75);
      return;
    }
    // Zone defenders drift with the QB's eyes.
    final look = eyes == null ? null : actors[eyes];
    if (look != null && !z.deep) {
      final shift = ((look.pos.x - landmark.x) * 0.15).clamp(-2.5, 2.5);
      landmark = Vec(landmark.x + shift, landmark.y);
    }
    if (t < 0.25) {
      _move(d, d.pos + Vec(0, z.deep ? 0.5 : 0.2), factor: 0.4);
      return;
    }

    // Find the threat in this zone.
    _Actor? threat;
    var best = -double.infinity;
    for (final r in offense) {
      if (play.assignments[r.id] is! RouteAssignment) continue;
      final p = r.posAgo(d.react + (z.deep ? 0.15 : 0));
      final inArea = (p.x - landmark.x).abs() <= z.rx + 2 &&
          (p.y - landmark.y).abs() <= z.ry + 3;
      if (!inArea) continue;
      // Deep defenders carry the deepest threat nearest their landmark.
      final score =
          z.deep ? p.y - 0.25 * (p.x - landmark.x).abs() : -p.distanceTo(landmark);
      if (score > best) {
        best = score;
        threat = r;
      }
    }

    Vec goal;
    if (threat == null) {
      goal = landmark;
    } else if (z.deep) {
      final seen = threat.posAgo(d.react + 0.15);
      final x = landmark.x + (seen.x - landmark.x) * 0.6;
      final y = math.max(seen.y + 2.5, landmark.y - 3);
      goal = Vec(x, y);
    } else {
      final seen = threat.posAgo(d.react);
      final x = seen.x.clamp(landmark.x - z.rx, landmark.x + z.rx);
      final y = (seen.y + 0.5).clamp(landmark.y - z.ry, landmark.y + z.ry);
      // Sit in the throwing lane between the QB and the threat.
      final lane = Vec.lerp(Vec(x, y), qb.pos, 0.12);
      goal = lane;
    }
    _move(d, goal, factor: z.deep ? 0.95 : 0.9);
  }

  _Actor? _nearestRusher() {
    _Actor? best;
    var bd = double.infinity;
    for (final d in defense) {
      if (!d.isRusher && d.engagedWith == null) continue;
      if (d.stalled) continue;
      final dist = d.pos.distanceTo(qb.pos);
      if (dist < bd) {
        bd = dist;
        best = d;
      }
    }
    return best;
  }

  // ---- QB brain ------------------------------------------------------------
  double get _readStart => hot ? 0.45 : setTime - 0.15;
  double get _readLen => hot ? 0.35 : 0.55;

  void _qbBrain() {
    if (t < _readStart) return;

    final threat = _nearestRusher();
    final threatDist = threat?.pos.distanceTo(qb.pos) ?? 99;
    final pressured = threatDist < 2.8;
    if (pressured && !pressureAnnounced) {
      pressureAnnounced = true;
      holdsBall = rng.nextDouble() < 0.45;
      emit(EventType.pressure, defender: threat?.id);
    }

    final i = ((t - _readStart) / _readLen).floor();
    if (i < reads.length) {
      if (i != readIdx) {
        if (readIdx >= 0 && readIdx < reads.length && lastEval != null) {
          emit(EventType.readCovered,
              player: reads[readIdx].id, read: readIdx, eval: lastEval);
        }
        readIdx = i;
        emit(EventType.readStart, player: reads[i].id, read: i);
      }
      final r = reads[i];
      eyes = r.id;
      final e = _evaluate(r);
      lastEval = e;
      final threshold = hot ? 0.8 : 1.3;
      if (e.reason != ReadReason.notReady && e.window >= threshold) {
        _throw(r, e, pressured: pressured);
        return;
      }
      if (pressured) {
        final best = _bestOption();
        if (best != null && best.window >= 0.4) {
          _throw(actors[best.receiverId]!, best, pressured: true);
        } else if (threatDist < 1.8 && t > setTime + 0.4 && !holdsBall) {
          _throwAway();
        }
      }
      return;
    }

    // Progression exhausted: check it down or get rid of it.
    if (readIdx < reads.length && readIdx >= 0 && lastEval != null) {
      emit(EventType.readCovered,
          player: reads[readIdx].id, read: readIdx, eval: lastEval);
      readIdx = reads.length;
    }
    final best = _bestOption();
    eyes = best?.receiverId;
    final late = t > _readStart + reads.length * _readLen + 1.2;
    if (best != null && (best.window >= 1.0 || (late && best.window >= 0.3))) {
      _throw(actors[best.receiverId]!, best, pressured: pressured);
    } else if ((late && !holdsBall) || (pressured && threatDist < 1.8 && !holdsBall)) {
      _throwAway();
    }
  }

  ReadEval? _bestOption() {
    ReadEval? best;
    for (final r in reads) {
      final e = _evaluate(r);
      if (e.reason == ReadReason.notReady) continue;
      if (best == null || e.window > best.window) best = e;
    }
    return best;
  }

  ReadEval _evaluate(_Actor r) {
    final from = qb.pos;
    var catchPt = r.pos;
    var flight = 0.0;
    for (var k = 0; k < 3; k++) {
      final dist = from.distanceTo(catchPt);
      final speed = 20 + math.min(dist, 35) * 0.15;
      flight = 0.15 + dist / speed;
      final p = r.pos + r.vel * (flight * 0.9);
      catchPt = Vec(p.x.clamp(1.0, Field.width - 1), math.min(p.y, 45));
    }
    final airDist = from.distanceTo(catchPt);

    // Has the route developed enough to throw it?
    final ready = r.path.isEmpty ||
        (r.wp >= 1 && r.traveled >= math.min(6.0, 0.35 * r.routeLength));

    var window = double.infinity;
    _Actor? limiter;
    var laneBlocked = false;
    for (final d in defense) {
      if (d.isRusher && _rushActive(d) && d.pos.y < 1) continue;
      final margin = d.pos.distanceTo(catchPt) - 0.6 - _reach(d, catchPt, flight);
      if (margin < window) {
        window = margin;
        limiter = d;
      }
      // Underneath defender sitting in the throwing lane.
      if (airDist < 22) {
        final seg = distanceToSegment(d.pos, from, catchPt);
        if (seg.t > 0.2 && seg.t < 0.85 && seg.dist < 1.1) {
          laneBlocked = true;
          limiter = d;
        }
      }
    }
    if (laneBlocked) window -= 2.0;

    ReadReason reason;
    if (!ready) {
      reason = ReadReason.notReady;
    } else if (window >= 1.3) {
      reason = ReadReason.open;
    } else if (laneBlocked) {
      reason = ReadReason.lane;
    } else if (limiter == null) {
      reason = ReadReason.open;
    } else {
      final la = limiter.def!.assignment;
      if (la is ManCover && la.targetId == r.id) {
        reason = ReadReason.manTight;
      } else if (limiter.pos.y > r.pos.y + 1.5) {
        reason = ReadReason.overTop;
      } else if (limiter.pos.y < r.pos.y) {
        reason = ReadReason.undercut;
      } else {
        reason = ReadReason.zoneCloses;
      }
    }
    return ReadEval(
      receiverId: r.id,
      window: window.isFinite ? window : 20,
      catchPoint: catchPt,
      flightTime: flight,
      limitingDefenderId: limiter?.id,
      reason: reason,
      laneBlocked: laneBlocked,
    );
  }

  /// How far [d] can travel toward [p] before a ball in the air [flight]
  /// seconds arrives, accounting for reaction time and acceleration.
  double _reach(_Actor d, Vec p, double flight) {
    final dir = (p - d.pos).normalized();
    final v0 = math.max(0.0, d.vel.dot(dir));
    final react = v0 > 3 ? 0.1 : 0.3;
    final tt = math.max(0.0, flight - react);
    const acc = 8.0;
    final tTop = math.max(0.0, (d.top - v0) / acc);
    if (tt <= tTop) return v0 * tt + 0.5 * acc * tt * tt;
    return v0 * tTop + 0.5 * acc * tTop * tTop + d.top * (tt - tTop);
  }

  void _throw(_Actor r, ReadEval e, {required bool pressured}) {
    ballState = BallState.air;
    carrier = null;
    target = r;
    throwFrom = qb.pos;
    throwT = t;
    flightT = e.flightTime;
    throwEval = e;
    throwUnderPressure = pressured;
    eyes = r.id;
    emit(EventType.throwBall,
        player: r.id, defender: e.limitingDefenderId, read: reads.indexOf(r), eval: e);
  }

  void _throwAway() {
    emit(EventType.throwAway);
    ballState = BallState.dead;
    carrier = null;
    outcome = SimOutcome(OutcomeType.throwAway, 0, timeToThrow: t);
    endAt = t + 0.8;
  }

  // ---- Ball -----------------------------------------------------------------
  Vec _ballLanding() {
    final r = target!;
    final remaining = math.max(0, throwT + flightT - t);
    return r.pos + r.vel * remaining.toDouble();
  }

  void _updateBall() {
    switch (ballState) {
      case BallState.held || BallState.caught:
        if (carrier != null) ball = carrier!.pos;
        ballHeight = 1;
      case BallState.air:
        final u = ((t - throwT) / flightT).clamp(0.0, 1.0);
        final landing = _ballLanding();
        ball = Vec.lerp(throwFrom!, landing, u);
        final dist = throwFrom!.distanceTo(landing);
        ballHeight = 1.8 + 4 * (dist / 7) * u * (1 - u);
        if (u >= 1) _resolveCatch();
      case BallState.dead:
        ballHeight = 0;
    }
  }

  void _resolveCatch() {
    final r = target!;
    ball = r.pos;
    var sep = double.infinity;
    _Actor? closest;
    for (final d in defense) {
      final dist = d.pos.distanceTo(r.pos);
      if (dist < sep) {
        sep = dist;
        closest = d;
      }
    }
    double comp;
    double intc;
    if (sep >= 2.5) {
      comp = 0.93;
      intc = 0;
    } else if (sep >= 1.5) {
      comp = 0.8;
      intc = 0.005;
    } else if (sep >= 0.8) {
      comp = 0.58;
      intc = 0.025;
    } else {
      comp = 0.35;
      intc = 0.07;
    }
    final airYards = r.pos.y;
    if (airYards > 20) comp *= 0.85;
    if (throwUnderPressure) comp *= 0.85;
    if (throwEval?.laneBlocked ?? false) {
      comp -= 0.15;
      intc += 0.05;
    }
    final roll = rng.nextDouble();
    if (roll < comp) {
      ballState = BallState.caught;
      carrier = r;
      r.speed *= 0.55; // gathering the catch
      emit(EventType.complete, player: r.id, defender: closest?.id);
      if (closest != null && sep < 1.8 && rng.nextDouble() < 0.75) {
        // Defender arrives with the ball: tackled on the spot.
        emit(EventType.tackle, player: r.id, defender: closest.id);
        _endPlay(OutcomeType.complete, r.pos.y);
      }
    } else if (roll < comp + intc && closest != null) {
      ballState = BallState.caught;
      carrier = closest;
      emit(EventType.interception, player: r.id, defender: closest.id);
      outcome = SimOutcome(OutcomeType.interception, 0,
          targetId: r.id, timeToThrow: throwT);
      endAt = t + 1.2;
    } else {
      ballState = BallState.dead;
      emit(EventType.incomplete, player: r.id, defender: closest?.id);
      outcome = SimOutcome(OutcomeType.incomplete, 0,
          targetId: r.id, timeToThrow: throwT);
      endAt = t + 0.8;
    }
  }

  void _handoff() {
    final r = runner;
    if (r == null) {
      handedOff = true;
      return;
    }
    if (qb.pos.distanceTo(r.pos) < 1.4 || t >= 1.2) {
      handedOff = true;
      carrier = r;
      emit(EventType.handoff, player: r.id);
    }
  }

  void _checkContact() {
    final c = carrier;
    if (c == null || ballState == BallState.dead) return;
    if (c == qb && ballState == BallState.held && !isRun) {
      for (final d in defense) {
        if (d.stalled || !d.isRusher) continue;
        if (d.pos.distanceTo(qb.pos) < 0.9) {
          emit(EventType.sack, defender: d.id);
          _endPlay(OutcomeType.sack, qb.pos.y);
          return;
        }
      }
      return;
    }
    if (!c.offense) return; // interception return — just let it play out
    if (c == qb) return;
    if (c.pos.y >= Field.yardsToGoal) {
      emit(EventType.touchdown, player: c.id);
      _endPlay(OutcomeType.touchdown, Field.yardsToGoal);
      return;
    }
    final nearSideline = c.pos.x < 1.8 || c.pos.x > Field.width - 1.8;
    final pushedOut = nearSideline &&
        defense.any((d) => !d.stalled && d.pos.distanceTo(c.pos) < 2.6);
    if (pushedOut || c.pos.x < 0.2 || c.pos.x > Field.width - 0.2) {
      emit(EventType.outOfBounds, player: c.id);
      _endPlay(isRun ? OutcomeType.run : OutcomeType.complete, c.pos.y);
      return;
    }
    for (final d in defense) {
      if (d.stalled) continue;
      if (d.pos.distanceTo(c.pos) > 1.2) continue;
      final breakChance = switch (d.def!.group) {
        DefGroup.dl => 0.18,
        DefGroup.lb => 0.12,
        DefGroup.db => 0.15,
      };
      if (!d.brokeTackleOn && rng.nextDouble() < breakChance) {
        d.brokeTackleOn = true;
        d.shed = false;
        d.engagedWith = c;
        d.shedAt = t + 0.6;
        c.speed *= 0.5;
        emit(EventType.brokenTackle, player: c.id, defender: d.id);
        continue;
      }
      if (d.brokeTackleOn && d.stalled) continue;
      emit(EventType.tackle, player: c.id, defender: d.id);
      _endPlay(isRun ? OutcomeType.run : OutcomeType.complete, c.pos.y);
      return;
    }
  }

  void _endPlay(OutcomeType type, double yards) {
    ballState = BallState.dead;
    final throwTime = events
        .where((e) => e.type == EventType.throwBall)
        .map((e) => e.t)
        .firstOrNull;
    outcome ??= SimOutcome(type, yards,
        targetId: target?.id ?? runner?.id, timeToThrow: throwTime);
    endAt = t + 0.6;
  }

  void _record() {
    frames.add(SimFrame(
      t: t,
      pos: {for (final a in actors.values) a.id: a.pos},
      ball: ball,
      ballHeight: ballHeight,
      ballState: ballState,
      carrierId: carrier?.id,
      eyes: eyes,
    ));
  }
}
