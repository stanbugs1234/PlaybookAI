import '../models/defense.dart';
import '../models/play.dart';
import '../models/vec.dart';

/// How the defense "sees" the offensive formation.
class FormationRead {
  /// +1 if the strength is to the right, -1 if left.
  final double s;
  final double ballX;

  /// Receivers to the strong/weak side, numbered outside-in (#1 first).
  final List<OffPlayer> strong;
  final List<OffPlayer> weak;
  final List<OffPlayer> backfield;

  const FormationRead(
      this.s, this.ballX, this.strong, this.weak, this.backfield);

  List<OffPlayer> get eligible => [...strong, ...weak, ...backfield];

  /// e.g. "3x1 (trips right)".
  String get description {
    final side = s > 0 ? 'right' : 'left';
    final shape = '${strong.length}x${weak.length}';
    final name = switch (strong.length) {
      3 => 'trips $side',
      2 when weak.length == 2 => 'doubles',
      2 => 'twins $side',
      4 => 'quads $side',
      _ => 'strength $side',
    };
    return '$shape ($name)';
  }

  static FormationRead of(Play play) {
    final ballX = play.playerOrNull('c')?.pos.x ?? Field.center;
    final elig = play.players.where((p) => p.role.isEligible).toList();
    final backfield = <OffPlayer>[];
    final left = <OffPlayer>[];
    final right = <OffPlayer>[];
    for (final p in elig) {
      if (p.pos.y < -3 && (p.pos.x - ballX).abs() < 5) {
        backfield.add(p);
      } else if (p.pos.x < ballX) {
        left.add(p);
      } else {
        right.add(p);
      }
    }
    double s;
    if (right.length != left.length) {
      s = right.length > left.length ? 1 : -1;
    } else {
      final teRight = right.any((p) => p.role == Role.te);
      final teLeft = left.any((p) => p.role == Role.te);
      s = (teLeft && !teRight) ? -1 : 1;
    }
    int byOutside(OffPlayer a, OffPlayer b) =>
        (b.pos.x - ballX).abs().compareTo((a.pos.x - ballX).abs());
    left.sort(byOutside);
    right.sort(byOutside);
    return FormationRead(
        s, ballX, s > 0 ? right : left, s > 0 ? left : right, backfield);
  }
}

/// Builds and aligns 11 defenders for a [DefenseCall] against a formation.
abstract final class DefenseFactory {
  static List<Defender> build(Play play, DefenseCall call) {
    final f = FormationRead.of(play);
    final s = f.s;
    final b = f.ballX;
    final cov = call.coverage;

    // ---- Front (rushers) -------------------------------------------------
    final strongTe = f.strong.where((p) =>
        p.role == Role.te && (p.pos.x - b).abs() < 7 && p.pos.y > -2);
    final deStrongX = strongTe.isNotEmpty ? strongTe.first.pos.x + s * 0.8 : b + s * 5.4;
    final rushers = <Defender>[];
    void rusher(String id, String label, DefGroup g, double x, double gap) =>
        rushers.add(Defender(
            id: id, label: label, group: g, pos: Vec(x, 1), assignment: Rush(gap)));

    if (call.front == Front.threeFour) {
      rusher('d_de_s', 'DE', DefGroup.dl, b + s * 3.6, b + s * 4.5);
      rusher('d_nt', 'NT', DefGroup.dl, b, b + s * 0.9);
      rusher('d_de_w', 'DE', DefGroup.dl, b - s * 3.6, b - s * 2.7);
      rusher('d_wolb', 'OLB', DefGroup.lb, b - s * 6.2, b - s * 6);
    } else {
      rusher('d_de_s', 'DE', DefGroup.dl, deStrongX, deStrongX + s * 0.5);
      rusher('d_dt_s', 'DT', DefGroup.dl, b + s * 2.6, b + s * 2.7);
      rusher('d_dt_w', 'DT', DefGroup.dl, b - s * 0.9, b - s * 0.9);
      rusher('d_de_w', 'DE', DefGroup.dl, b - s * 5.4, b - s * 5.8);
    }

    // ---- Coverage personnel & base alignment -------------------------------
    final s1 = f.strong.isNotEmpty ? f.strong[0] : null;
    final w1 = f.weak.isNotEmpty ? f.weak[0] : null;
    final s2 = f.strong.length > 1 ? f.strong[1] : null;
    final w2 = f.weak.length > 1 ? f.weak[1] : null;
    final s3 = f.strong.length > 2 ? f.strong[2] : null;

    final pressCorners = cov.isMan;
    double cbDepth(bool strongSide) => switch (cov) {
          Coverage.cover0 || Coverage.cover1 || Coverage.twoMan => 1.5,
          Coverage.cover2 || Coverage.tampa2 => 4.5,
          Coverage.cover6 => strongSide ? 7 : 4.5,
          _ => 7,
        };
    Vec cornerSpot(OffPlayer? wr, bool strongSide) {
      final side = strongSide ? s : -s;
      final x = wr?.pos.x ?? b + side * 18;
      // Man: inside leverage. Squat corners: outside leverage.
      final shade = pressCorners ? -side * 0.8 : side * 0.8;
      return Vec(x + shade, cbDepth(strongSide));
    }

    final twoHigh = switch (cov) {
      Coverage.cover2 ||
      Coverage.tampa2 ||
      Coverage.twoMan ||
      Coverage.cover4 ||
      Coverage.cover6 =>
        true,
      _ => false,
    };

    final cbS = _D('d_cbs', 'CB', DefGroup.db, cornerSpot(s1, true));
    final cbW = _D('d_cbw', 'CB', DefGroup.db, cornerSpot(w1, false));
    final safetyDepth = cov == Coverage.cover4 ? 10.5 : 12.5;
    final fs = _D('d_fs', 'FS', DefGroup.db,
        twoHigh
            ? Vec(b - s * 9, safetyDepth)
            : Vec(b, cov == Coverage.cover0 ? 8 : 13.5));
    final ssSlot = s3 ?? s2;
    final ss = _D(
        'd_ss',
        'SS',
        DefGroup.db,
        twoHigh
            ? Vec(b + s * 9, safetyDepth)
            : Vec(ssSlot != null ? ssSlot.pos.x - s * 1.5 : b + s * 6, 7));

    Vec apex(OffPlayer? slot, double side, double fallback) {
      if (slot == null) return Vec(b + side * fallback, 4.5);
      final tackleX = b + side * 3.6;
      if (slot.role == Role.te && (slot.pos.x - b).abs() < 7) {
        return Vec(slot.pos.x + side * 0.4, 4);
      }
      return Vec((tackleX + slot.pos.x) / 2, 5);
    }

    final unders = <_D>[];
    switch (call.front) {
      case Front.fourThree || Front.threeFour:
        unders.add(_D('d_sam', 'S', DefGroup.lb, apex(s2, s, 5)));
        unders.add(_D('d_mike', 'M', DefGroup.lb, Vec(b + s * 0.5, 5)));
        unders.add(_D('d_will', 'W', DefGroup.lb,
            w2 != null ? apex(w2, -s, 3.5) : Vec(b - s * 3.5, 5)));
      case Front.nickel:
        unders.add(_D('d_nb', 'NB', DefGroup.db,
            s2 != null ? Vec(s2.pos.x - s * 1, 4.5) : Vec(b + s * 7, 5)));
        unders.add(_D('d_mike', 'M', DefGroup.lb, Vec(b + s * 1.5, 5)));
        unders.add(_D('d_will', 'W', DefGroup.lb, Vec(b - s * 2.5, 5)));
      case Front.dime:
        unders.add(_D('d_nb', 'NB', DefGroup.db,
            s2 != null ? Vec(s2.pos.x - s * 1, 4.5) : Vec(b + s * 7, 5)));
        final dimeTarget = w2 ?? s3;
        unders.add(_D(
            'd_dime',
            'DB',
            DefGroup.db,
            dimeTarget != null
                ? Vec(dimeTarget.pos.x - (dimeTarget.pos.x > b ? 1 : -1), 4.5)
                : Vec(b - s * 6, 5)));
        unders.add(_D('d_mike', 'M', DefGroup.lb, Vec(b, 5)));
    }

    // ---- Blitz -------------------------------------------------------------
    final blitzers = <_D>[];
    _D? pull(String id) {
      for (final u in [...unders, ss]) {
        if (u.id == id) return u;
      }
      return null;
    }

    switch (call.blitz) {
      case Blitz.none:
        break;
      case Blitz.mike:
        final m = pull('d_mike')!;
        m.rushGap = b - s * 0.9;
        blitzers.add(m);
      case Blitz.slot:
        final n = pull('d_nb') ?? pull('d_sam')!;
        n.rushGap = b + s * 6;
        blitzers.add(n);
      case Blitz.safety:
        ss.rushGap = b + s * 2.7;
        ss.pos = Vec(b + s * 4, 5.5);
        blitzers.add(ss);
    }
    unders.removeWhere(blitzers.contains);

    // ---- Coverage assignments ---------------------------------------------
    final all = [cbS, cbW, fs, ss, ...unders];

    if (cov.isMan) {
      final manPool = <_D>[
        if (cov != Coverage.twoMan && !blitzers.contains(ss)) ss,
        if (cov == Coverage.cover0) fs,
        ...unders,
      ];
      void manUp(_D d, OffPlayer r, {double depth = 1.5}) {
        final rightSide = r.pos.x >= b;
        final inside = rightSide ? -1.0 : 1.0;
        d.assignment = ManCover(r.id, r.label);
        final backfield = f.backfield.contains(r);
        d.pos = backfield
            ? Vec(r.pos.x + (d.pos.x - r.pos.x) * 0.5, 4.5)
            : Vec(r.pos.x + inside * 0.8, d.group == DefGroup.lb ? 3.5 : depth);
      }

      if (s1 != null) manUp(cbS, s1);
      if (w1 != null) manUp(cbW, w1);
      final rest = [
        ?s2,
        ?w2,
        ...f.strong.skip(2),
        ...f.weak.skip(2),
        ...f.backfield,
      ];
      for (final r in rest) {
        if (manPool.isEmpty) break;
        _D best = manPool.first;
        double bestCost = double.infinity;
        for (final d in manPool) {
          var cost = d.pos.distanceTo(r.pos);
          if (r.role == Role.wr && d.group == DefGroup.lb) cost += 6;
          if ((r.role == Role.rb || r.role == Role.fb) && d.group == DefGroup.db) {
            cost += 3;
          }
          if (cost < bestCost) {
            bestCost = cost;
            best = d;
          }
        }
        manPool.remove(best);
        manUp(best, r, depth: 3);
      }
      // Corners with nobody to cover (e.g. no #1 to a side) play a zone.
      cbS.assignment ??= ZoneCover('Flat (strong)', Vec(b + s * 16, 5));
      cbW.assignment ??= ZoneCover('Flat (weak)', Vec(b - s * 16, 5));

      switch (cov) {
        case Coverage.cover1:
          fs.assignment = const ZoneCover('Deep middle (free)',
              Vec(Field.center, 17),
              rx: 18, ry: 14, deep: true);
        case Coverage.twoMan:
          fs.assignment = _deepHalf(-s);
          ss.assignment ??= _deepHalf(s);
        case _:
          break;
      }
      // Extra men: one robs the hole, the rest come.
      var robber = cov == Coverage.cover1;
      for (final d in manPool) {
        if (robber) {
          d.assignment = ZoneCover('Robber (hole)', Vec(b, 9), rx: 7, ry: 4);
          d.pos = Vec(b, 7);
          robber = false;
        } else {
          d.rushGap = d.pos.x > b ? b + 2.7 : b - 2.7;
          // Walk the extra man down into the box to come on the snap.
          d.pos = Vec(b + (d.pos.x - b).clamp(-5.0, 5.0), 4.5);
          blitzers.add(d);
        }
      }
    } else {
      _assignZones(cov, s, b, cbS, cbW, fs, ss, unders);
    }

    final out = <Defender>[...rushers];
    for (final d in all) {
      if (blitzers.contains(d)) continue;
      out.add(d.build());
    }
    for (final d in blitzers) {
      out.add(Defender(
          id: d.id,
          label: d.label,
          group: d.group,
          pos: d.pos,
          assignment: Rush(d.rushGap ?? b, blitzer: true)));
    }
    return out;
  }

  static ZoneCover _deepHalf(double side) => ZoneCover(
      side * 1 > 0 ? 'Deep half (right)' : 'Deep half (left)',
      Vec(Field.center + side * 13.3, 17),
      rx: 13.3,
      ry: 14,
      deep: true);

  static ZoneCover _deepThird(double side) => ZoneCover(
      side == 0
          ? 'Deep middle third'
          : side > 0
              ? 'Deep third (right)'
              : 'Deep third (left)',
      Vec(Field.center + side * 17.8, 17),
      rx: side == 0 ? 11 : 9,
      ry: 14,
      deep: true);

  static ZoneCover _deepQuarter(double pos) => ZoneCover(
      'Deep quarter',
      Vec(Field.center + pos, 15),
      rx: 6.7,
      ry: 13,
      deep: true);

  static void _assignZones(Coverage cov, double s, double b, _D cbS, _D cbW,
      _D fs, _D ss, List<_D> unders) {
    final ssBlitzing = ss.rushGap != null;
    final under = <_D>[...unders];
    List<ZoneCover> underZones;

    switch (cov) {
      case Coverage.cover3:
        cbS.assignment = _deepThird(s);
        cbW.assignment = _deepThird(-s);
        fs.assignment = _deepThird(0);
        if (!ssBlitzing) under.add(ss);
        underZones = under.length >= 4
            ? [
                ZoneCover('Curl/flat (strong)', Vec(b + s * 13, 6), rx: 6),
                ZoneCover('Hook/curl (strong)', Vec(b + s * 5, 8), rx: 5),
                ZoneCover('Hook/curl (weak)', Vec(b - s * 5, 8), rx: 5),
                ZoneCover('Curl/flat (weak)', Vec(b - s * 13, 6), rx: 6),
              ]
            : [
                ZoneCover('Curl/flat (strong)', Vec(b + s * 12, 6), rx: 7),
                ZoneCover('Middle hook', Vec(b, 8), rx: 6),
                ZoneCover('Curl/flat (weak)', Vec(b - s * 12, 6), rx: 7),
              ];
      case Coverage.cover2 || Coverage.tampa2:
        cbS.assignment =
            ZoneCover('Flat (strong)', Vec(Field.center + s * 19, 4), rx: 7);
        cbW.assignment =
            ZoneCover('Flat (weak)', Vec(Field.center - s * 19, 4), rx: 7);
        ss.assignment ??= _deepHalf(s);
        fs.assignment = _deepHalf(-s);
        if (cov == Coverage.tampa2) {
          final mike = under.where((u) => u.id == 'd_mike').firstOrNull;
          if (mike != null) {
            mike.assignment = ZoneCover('Deep middle (Tampa)',
                Vec(Field.center, 15),
                rx: 5, ry: 7, deep: true);
            under.remove(mike);
          }
          underZones = [
            ZoneCover('Hook/curl (strong)', Vec(b + s * 7, 8), rx: 6),
            ZoneCover('Hook/curl (weak)', Vec(b - s * 7, 8), rx: 6),
          ];
        } else {
          underZones = under.length >= 3
              ? [
                  ZoneCover('Hook/curl (strong)', Vec(b + s * 8, 9), rx: 5),
                  ZoneCover('Middle hook', Vec(b, 9), rx: 4),
                  ZoneCover('Hook/curl (weak)', Vec(b - s * 8, 9), rx: 5),
                ]
              : [
                  ZoneCover('Hook/curl (strong)', Vec(b + s * 6, 9), rx: 6),
                  ZoneCover('Hook/curl (weak)', Vec(b - s * 6, 9), rx: 6),
                ];
        }
      case Coverage.cover4:
        cbS.assignment = _deepQuarter(s * 20);
        cbW.assignment = _deepQuarter(-s * 20);
        ss.assignment ??= _deepQuarter(s * 6.7);
        fs.assignment = _deepQuarter(-s * 6.7);
        underZones = _threeUnder(s, b);
      case Coverage.cover6:
        cbS.assignment = _deepQuarter(s * 20);
        ss.assignment ??= _deepQuarter(s * 6.7);
        fs.assignment = _deepHalf(-s);
        cbW.assignment =
            ZoneCover('Flat (weak)', Vec(Field.center - s * 19, 4), rx: 7);
        underZones = _threeUnder(s, b);
      case _:
        underZones = _threeUnder(s, b);
    }

    // Match underneath defenders to zones in strong-to-weak order.
    under.sort((a, c) => (c.pos.x * s).compareTo(a.pos.x * s));
    if (under.length < underZones.length && underZones.length == 3) {
      underZones = [underZones.first, underZones.last];
    }
    for (var i = 0; i < under.length; i++) {
      under[i].assignment = underZones[i.clamp(0, underZones.length - 1)];
    }
  }

  static List<ZoneCover> _threeUnder(double s, double b) => [
        ZoneCover('Curl/flat (strong)', Vec(b + s * 12, 6), rx: 7),
        ZoneCover('Hook (middle)', Vec(b, 8), rx: 6),
        ZoneCover('Curl/flat (weak)', Vec(b - s * 12, 6), rx: 7),
      ];
}

/// Mutable builder used while laying out the defense.
class _D {
  final String id;
  final String label;
  final DefGroup group;
  Vec pos;
  DefAssignment? assignment;
  double? rushGap;
  _D(this.id, this.label, this.group, this.pos);

  Defender build() => Defender(
        id: id,
        label: label,
        group: group,
        pos: pos,
        assignment: assignment ?? ZoneCover('Hook (middle)', Vec(pos.x, 8)),
      );
}
