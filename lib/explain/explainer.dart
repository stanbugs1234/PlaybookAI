import '../models/defense.dart';
import '../models/play.dart';
import '../models/vec.dart';
import '../sim/defense_factory.dart';
import '../sim/sim_types.dart';

enum StepKind { preSnap, read, covered, decision, pressure, result, run }

class ExplanationStep {
  final double t;
  final int frame;
  final StepKind kind;
  final String title;
  final String detail;
  final String? focusId;
  final String? defenderId;

  /// true = good for the offense, false = bad, null = neutral.
  final bool? good;

  const ExplanationStep({
    required this.t,
    required this.frame,
    required this.kind,
    required this.title,
    required this.detail,
    this.focusId,
    this.defenderId,
    this.good,
  });
}

class Explanation {
  final String shell;
  final List<String> preSnap;
  final List<ExplanationStep> steps;
  final String summary;
  final List<String> tips;

  const Explanation({
    required this.shell,
    required this.preSnap,
    required this.steps,
    required this.summary,
    required this.tips,
  });
}

/// Turns a [SimResult] into the coaching explanation shown next to the field.
abstract final class Explainer {
  static Explanation explain(SimResult r) {
    final ctx = _Ctx(r);
    return Explanation(
      shell: ctx.shell(),
      preSnap: ctx.preSnap(),
      steps: ctx.steps(),
      summary: ctx.summary(),
      tips: ctx.tips(),
    );
  }

  static String coverageBeaters(Coverage c) => _beaters[c]!;

  static const _beaters = {
    Coverage.cover0:
        'No deep help and more rushers than blockers: throw hot (slants, quick outs, fades) or keep extra blockers in.',
    Coverage.cover1:
        'Man-free beaters: crossers and rubs (Mesh), double moves, or isolate your best receiver on a linebacker.',
    Coverage.cover2:
        'Attack the holes: Smash (corner over hitch), the sideline hole shot between the corner and safety at 18–20 yds, and seams that split the safeties.',
    Coverage.tampa2:
        'The Mike takes away the deep middle. Attack the flats, the curls and the deep corners, or run the ball against the light box.',
    Coverage.cover3:
        'Four verticals put two receivers on the free safety. Flood (three levels to one side) and curl/flat high-lows put the flat defender in conflict.',
    Coverage.cover4:
        'Quarters is strong against verticals. Throw the flats and underneath routes, run Dagger or Post-Wheel, or use play-action to freeze the run-fitting safeties.',
    Coverage.cover6:
        'Read which side is which. Hit the Cover 2 side with Smash or the hole shot, and the quarters side with flats and curls.',
    Coverage.twoMan:
        'Tight man with safety help over the top: win underneath with crossers, rubs and option routes, or let the QB scramble.',
  };
}

class _Ctx {
  final SimResult r;
  final Play play;
  final FormationRead form;
  _Ctx(this.r)
      : play = r.play,
        form = FormationRead.of(r.play);

  Defender? d(String? id) => id == null ? null : r.defender(id);

  String defName(String? id) {
    final x = d(id);
    if (x == null) return 'a defender';
    return '${x.label} (${x.assignment.description})';
  }

  String recName(String? id) {
    if (id == null) return 'the receiver';
    final p = play.playerOrNull(id);
    if (p == null) return id;
    final a = play.assignments[id];
    final route = switch (a) {
      RouteAssignment(:final name) when name != null => ' on the ${name.toLowerCase()}',
      RunAssignment(:final name) when name != null => ' (${name.toLowerCase()})',
      _ => '',
    };
    return '${p.label}$route';
  }

  double get ballX => play.playerOrNull('c')?.pos.x ?? Field.center;

  int get deepSafeties => r.defenders.where((x) => x.pos.y > 10).length;

  int get boxCount => r.defenders
      .where((x) => x.pos.y <= 7.5 && (x.pos.x - ballX).abs() <= 7)
      .length;

  int get blockers => play.players
      .where((p) =>
          p.role == Role.ol ||
          (play.assignments[p.id] is BlockAssignment && p.role != Role.qb))
      .length;

  int get rushers =>
      r.defenders.where((x) => x.assignment is Rush).length;

  String shell() {
    final n = deepSafeties;
    if (n >= 2) {
      return 'Two-high shell (middle of the field open): expect Cover 2, 4 or 6, or 2-Man.';
    }
    if (n == 1) {
      return 'One-high shell (middle of the field closed): expect Cover 1 or Cover 3.';
    }
    return 'Zero-high: no deep safety. Expect Cover 0 pressure, so the ball must come out hot.';
  }

  List<String> preSnap() {
    final out = <String>[];
    out.add('Formation: ${form.description}. Defense: ${r.call.label}.');
    final corners = r.defenders.where((x) => x.label == 'CB').toList();
    if (corners.isNotEmpty) {
      final avg = corners.map((c) => c.pos.y).reduce((a, b) => a + b) / corners.length;
      if (avg < 3) {
        out.add('Corners are pressed (${avg.toStringAsFixed(0)} yd). Expect man, so routes have to win at the line.');
      } else if (avg >= 6) {
        out.add('Corners are ${avg.toStringAsFixed(0)} yds off, which gives up the quick game (hitch, slant, quick out).');
      } else {
        out.add('Corners are squatting at ${avg.toStringAsFixed(0)} yds, a sign of Cover 2. The hole is behind them along the sideline.');
      }
    }
    if (play.playType == PlayType.run) {
      final diff = boxCount - blockers;
      out.add(diff > 0
          ? '$boxCount in the box against $blockers blockers: the defense has an extra hat in the run fit.'
          : '$boxCount in the box against $blockers blockers: a light box, so this is a good look to run.');
    } else {
      final extra = rushers - blockers;
      out.add(extra > 0
          ? 'Defense brings $rushers against $blockers blockers. Someone is unblocked, so the QB must throw hot.'
          : 'Defense rushes $rushers against $blockers blockers. Protection is sound.');
    }
    for (final id in play.progression.take(3)) {
      final p = play.playerOrNull(id);
      if (p == null) continue;
      final nearest = _nearestDefenderTo(p.pos);
      if (nearest == null) continue;
      final dx = nearest.pos.x - p.pos.x;
      final outside = (p.pos.x >= ballX) ? dx > 0.3 : dx < -0.3;
      final inside = (p.pos.x >= ballX) ? dx < -0.3 : dx > 0.3;
      final lev = outside
          ? 'outside leverage'
          : inside
              ? 'inside leverage'
              : 'head-up';
      final depth = (nearest.pos.y - p.pos.y).toStringAsFixed(0);
      out.add('${p.label}: ${nearest.label} at $depth yds, $lev.');
    }
    return out;
  }

  Defender? _nearestDefenderTo(Vec p) {
    Defender? best;
    var bd = double.infinity;
    for (final x in r.defenders) {
      if (x.assignment is Rush) continue;
      final dist = x.pos.distanceTo(p);
      if (dist < bd) {
        bd = dist;
        best = x;
      }
    }
    return best;
  }

  String _reasonText(ReadEval e) {
    final who = defName(e.limitingDefenderId);
    final w = e.window.toStringAsFixed(1);
    return switch (e.reason) {
      ReadReason.notReady =>
        'The route hadn\'t developed when it was time to move on.',
      ReadReason.overTop => '$who is over the top (window $w yds).',
      ReadReason.manTight => '$who is in his hip pocket (window $w yds).',
      ReadReason.undercut =>
        '$who is sitting underneath the route, in the throwing window ($w yds).',
      ReadReason.lane => '$who is in the throwing lane, so the pass could be tipped or picked.',
      ReadReason.zoneCloses => '$who can close before the ball arrives ($w yds).',
      ReadReason.open => 'Open, with a $w yd window.',
    };
  }

  String _whyOpen(ReadEval e) {
    // Find the two defenders closest to the catch point.
    final defs = [...r.defenders.where((x) => x.assignment is! Rush)]
      ..sort((a, b) => _posAt(a.id, e).distanceTo(e.catchPoint)
          .compareTo(_posAt(b.id, e).distanceTo(e.catchPoint)));
    if (defs.length >= 2) {
      final a = defs[0], b = defs[1];
      if (a.assignment is ZoneCover && b.assignment is ZoneCover) {
        return 'He settles in the void between ${a.label} (${a.assignment.description}) and ${b.label} (${b.assignment.description}).';
      }
      if (a.assignment case ManCover(:final targetId) when targetId == e.receiverId) {
        return 'He has beaten ${a.label} in man coverage with his route break.';
      }
    }
    final lim = d(e.limitingDefenderId);
    if (lim?.assignment case ManCover(:final targetLabel)) {
      return '${lim!.label} is locked on $targetLabel, so nobody is responsible for this area.';
    }
    return 'The nearest help, ${defName(e.limitingDefenderId)}, can\'t get there in time.';
  }

  Vec _posAt(String id, ReadEval e) {
    // Position at the throw (best effort: use the frame nearest the throw).
    final throwEvt = r.events.where((x) => x.type == EventType.throwBall).firstOrNull;
    final f = throwEvt == null ? r.frames.first : r.frames[throwEvt.frame];
    return f.pos[id] ?? Vec.zero;
  }

  List<ExplanationStep> steps() {
    final out = <ExplanationStep>[];
    for (final e in r.events) {
      ExplanationStep step(StepKind k, String title, String detail,
              {String? focus, String? def, bool? good}) =>
          ExplanationStep(
              t: e.t,
              frame: e.frame,
              kind: k,
              title: title,
              detail: detail,
              focusId: focus,
              defenderId: def,
              good: good);
      switch (e.type) {
        case EventType.snap:
          out.add(step(StepKind.preSnap, 'Snap', shell()));
        case EventType.unblocked:
          out.add(step(StepKind.pressure, 'Unblocked rusher',
              '${defName(e.defenderId)} isn\'t accounted for in the protection. The QB has to throw hot.',
              def: e.defenderId, good: false));
        case EventType.blitzPickup:
          final p = play.playerOrNull(e.playerId ?? '');
          out.add(step(StepKind.pressure, 'Blitz picked up',
              '${p?.label ?? 'A back'} picks up ${defName(e.defenderId)}.',
              focus: e.playerId, def: e.defenderId, good: true));
        case EventType.fake:
          out.add(step(StepKind.read, 'Play-action fake',
              'The run fake pulls the linebackers forward and opens the window behind them.',
              focus: e.playerId));
        case EventType.handoff:
          out.add(step(StepKind.run, 'Handoff', 'Ball to ${recName(e.playerId)}.',
              focus: e.playerId));
        case EventType.readStart:
          final i = (e.readIndex ?? 0) + 1;
          out.add(step(StepKind.read, 'Read $i: ${recName(e.playerId)}',
              'Eyes to ${play.playerOrNull(e.playerId ?? '')?.label ?? ''}.',
              focus: e.playerId));
        case EventType.readCovered:
          out.add(step(StepKind.covered, 'Covered: ${recName(e.playerId)}',
              '${_reasonText(e.eval!)} Move on to the next read.',
              focus: e.playerId, def: e.eval?.limitingDefenderId, good: false));
        case EventType.pressure:
          out.add(step(StepKind.pressure, 'Pressure',
              '${defName(e.defenderId)} is collapsing the pocket. Get the ball out.',
              def: e.defenderId, good: false));
        case EventType.throwBall:
          final ev = e.eval!;
          final readNo = (e.readIndex ?? -1) >= 0 ? 'Read ${(e.readIndex ?? 0) + 1}' : 'Check-down';
          out.add(step(StepKind.decision, 'Throw: ${recName(e.playerId)}',
              '$readNo is open with a ${ev.window.toStringAsFixed(1)} yd window. ${_whyOpen(ev)}',
              focus: e.playerId, def: ev.limitingDefenderId, good: true));
        case EventType.throwAway:
          out.add(step(StepKind.result, 'Throw it away',
              'Nothing came open in time, so the QB lives for the next down.',
              good: false));
        case EventType.complete:
          out.add(step(StepKind.result, 'Caught', '${recName(e.playerId)} hauls it in.',
              focus: e.playerId, good: true));
        case EventType.incomplete:
          out.add(step(StepKind.result, 'Incomplete',
              '${defName(e.defenderId)} gets there to contest it.',
              focus: e.playerId, def: e.defenderId, good: false));
        case EventType.interception:
          out.add(step(StepKind.result, 'Intercepted',
              '${defName(e.defenderId)} jumps the throw. The window was too tight.',
              focus: e.playerId, def: e.defenderId, good: false));
        case EventType.sack:
          out.add(step(StepKind.result, 'Sack', '${defName(e.defenderId)} gets home.',
              def: e.defenderId, good: false));
        case EventType.brokenTackle:
          out.add(step(StepKind.run, 'Broken tackle',
              '${play.playerOrNull(e.playerId ?? '')?.label} breaks a tackle by ${d(e.defenderId)?.label}.',
              focus: e.playerId, def: e.defenderId, good: true));
        case EventType.tackle:
          out.add(step(StepKind.result, 'Tackled',
              'Brought down by ${defName(e.defenderId)}. ${r.outcome.label}.',
              focus: e.playerId, def: e.defenderId, good: r.outcome.isSuccess));
        case EventType.outOfBounds:
          out.add(step(StepKind.result, 'Out of bounds', r.outcome.label,
              focus: e.playerId, good: r.outcome.isSuccess));
        case EventType.touchdown:
          out.add(step(StepKind.result, 'Touchdown!', 'Nobody can catch him.',
              focus: e.playerId, good: true));
        case EventType.set:
          break;
      }
    }
    return out;
  }

  String summary() {
    final o = r.outcome;
    final cov = r.call.coverage;
    final throwEvt = r.events.where((e) => e.type == EventType.throwBall).firstOrNull;
    final covered = r.events.where((e) => e.type == EventType.readCovered).toList();
    switch (o.type) {
      case OutcomeType.run || OutcomeType.touchdown when play.playType == PlayType.run:
        final tackle = r.events.where((e) => e.type == EventType.tackle).firstOrNull;
        final box = boxCount - blockers;
        final boxNote = box > 0
            ? 'The defense had $box more defender${box > 1 ? 's' : ''} in the box than you had blockers.'
            : 'You had a hat for every defender in the box.';
        return o.isSuccess
            ? 'Successful run (${o.label}). $boxNote'
            : 'The run was stopped (${o.label})${tackle != null ? ' by ${defName(tackle.defenderId)}' : ''}. $boxNote';
      case OutcomeType.sack || OutcomeType.throwAway:
        final first = covered.isNotEmpty ? covered.first : null;
        return 'Coverage won against ${cov.label}. '
            '${first != null ? 'Read 1 (${recName(first.playerId)}) was taken away: ${_reasonText(first.eval!)} ' : ''}'
            'Nothing else uncovered before the rush got there.';
      default:
        if (throwEvt == null) return o.label;
        final readIdx = throwEvt.readIndex ?? -1;
        final where = readIdx == 0
            ? 'on the first read'
            : readIdx > 0
                ? 'on read ${readIdx + 1}'
                : 'on the check-down';
        final base = 'The ball went to ${recName(throwEvt.playerId)} $where (${o.label}).';
        if (o.type == OutcomeType.interception) {
          return '$base It was a forced throw into a closing window. Against ${cov.label} that throw isn\'t there.';
        }
        if (readIdx == 0 && o.isSuccess) {
          return '$base The concept beat ${cov.label} by design. This is a good call against this look.';
        }
        if (o.isSuccess) {
          return '$base ${covered.length} read${covered.length == 1 ? ' was' : 's were'} covered first, but the progression found the open man.';
        }
        return '$base A low-percentage or short result. Look at the tips for better answers to ${cov.label}.';
    }
  }

  List<String> tips() {
    final out = <String>[Explainer.coverageBeaters(r.call.coverage)];
    if (r.call.blitz != Blitz.none || rushers > blockers) {
      out.add('Against pressure, build in a hot route or keep the back in to block. Quick game beats the blitz.');
    }
    if (play.playType == PlayType.run && boxCount > blockers) {
      out.add('Loaded box: check to a pass or put a receiver on the extra defender (RPO or bubble).');
    }
    if (play.playType != PlayType.run && play.progression.isEmpty) {
      out.add('Set a progression order in the designer so the QB reads it the way you coach it.');
    }
    return out;
  }
}
