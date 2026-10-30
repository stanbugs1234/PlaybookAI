import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/field/field_painter.dart';
import '../../core/field/play_painter.dart';
import '../../models/defense.dart';
import '../../models/play.dart';
import '../../models/vec.dart';
import '../../sim/sim_engine.dart';
import '../../sim/sim_types.dart';

class SimPainter extends CustomPainter {
  final Play play;
  final List<Defender> defenders;
  final SimResult? result;
  final double t;
  final bool showZones;
  final bool showTrails;
  final bool showEyes;
  final String? focusId;
  final String? focusDefenderId;
  final bool? focusGood;
  final String? dragging;

  SimPainter({
    required this.play,
    required this.defenders,
    required this.result,
    required this.t,
    required this.showZones,
    required this.showTrails,
    required this.showEyes,
    this.focusId,
    this.focusDefenderId,
    this.focusGood,
    this.dragging,
  });

  static FieldTransform transform(Size size) => FieldTransform(size, yTop: 34, yBottom: -12);

  @override
  void paint(Canvas canvas, Size size) {
    final tf = transform(size);
    canvas.save();
    canvas.clipRect(tf.fieldRect);
    paintField(canvas, tf);
    if (showZones) paintZones(canvas, tf, defenders);

    final r = result;
    if (r == null) {
      _paintPreSnap(canvas, tf);
    } else {
      _paintFrame(canvas, tf, r);
    }
    canvas.restore();
  }

  void _paintPreSnap(Canvas canvas, FieldTransform tf) {
    for (final p in play.players) {
      final a = play.assignments[p.id];
      if (a is RouteAssignment) {
        paintPath(canvas, tf, [p.pos, ...a.waypoints], color: Colors.white70, width: 2);
      } else if (a is RunAssignment) {
        paintPath(canvas, tf, [p.pos, ...a.path], color: FieldColors.run, width: 2, dashed: true);
      }
    }
    _paintManLines(canvas, tf, {for (final p in play.players) p.id: p.pos},
        {for (final d in defenders) d.id: d.pos});
    for (final d in defenders) {
      paintPlayer(canvas, tf, d.pos, d.label, offense: false, highlight: d.id == dragging);
    }
    for (final p in play.players) {
      paintPlayer(canvas, tf, p.pos, p.label, offense: true, square: p.role == Role.ol);
    }
  }

  void _paintManLines(Canvas canvas, FieldTransform tf, Map<String, Vec> off, Map<String, Vec> def) {
    final paint = Paint()
      ..color = FieldColors.defense.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (final d in defenders) {
      final a = d.assignment;
      if (a is! ManCover) continue;
      final from = def[d.id];
      final to = off[a.targetId];
      if (from == null || to == null) continue;
      final pa = tf.toScreen(from), pb = tf.toScreen(to);
      final dir = pb - pa;
      final len = dir.distance;
      for (var s = 0.0; s < len; s += 8) {
        canvas.drawLine(pa + dir * (s / len), pa + dir * (math.min(s + 4, len) / len), paint);
      }
    }
  }

  void _paintFrame(Canvas canvas, FieldTransform tf, SimResult r) {
    final frames = r.frames;
    final fi = (t / SimEngine.dt).clamp(0.0, frames.length - 1.0);
    final i0 = fi.floor();
    final i1 = math.min(i0 + 1, frames.length - 1);
    final u = fi - i0;
    final f0 = frames[i0], f1 = frames[i1];
    Vec at(String id) => Vec.lerp(f0.pos[id]!, f1.pos[id]!, u);

    // Planned routes as ghosts.
    for (final p in play.players) {
      final a = play.assignments[p.id];
      if (a is RouteAssignment) {
        paintPath(canvas, tf, [p.pos, ...a.waypoints],
            color: Colors.white24, width: 1.5, arrow: false);
      }
    }

    if (showTrails) {
      for (final p in play.players) {
        if (p.role == Role.ol) continue;
        final pts = <Vec>[for (var k = 0; k <= i0; k += 2) frames[k].pos[p.id]!, at(p.id)];
        paintPath(canvas, tf, pts,
            color: (p.id == f0.carrierId ? FieldColors.run : const Color(0xFF90CAF9))
                .withValues(alpha: 0.85),
            width: 2,
            arrow: false);
      }
      for (final d in r.defenders) {
        if (d.assignment is Rush) continue;
        final pts = <Vec>[for (var k = 0; k <= i0; k += 2) frames[k].pos[d.id]!, at(d.id)];
        paintPath(canvas, tf, pts,
            color: const Color(0xFFEF9A9A).withValues(alpha: 0.55), width: 1.4, arrow: false);
      }
    }

    // QB eyes.
    final eyes = f0.eyes;
    if (showEyes && eyes != null && f0.ballState == BallState.held && f0.carrierId == play.qb.id) {
      final a = tf.toScreen(at(play.qb.id)), b = tf.toScreen(at(eyes));
      final paint = Paint()
        ..color = FieldColors.firstDown.withValues(alpha: 0.8)
        ..strokeWidth = 1.6;
      final dir = b - a;
      final len = dir.distance;
      for (var s = 0.0; s < len; s += 10) {
        canvas.drawLine(a + dir * (s / len), a + dir * (math.min(s + 5, len) / len), paint);
      }
    }

    void ring(String id, Color color) {
      final c = tf.toScreen(at(id));
      canvas.drawCircle(
          c,
          math.max(12, tf.scale * 1.9),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color);
    }

    if (focusId != null && f0.pos.containsKey(focusId)) {
      ring(focusId!, focusGood == false ? const Color(0xFFFF5252) : const Color(0xFF69F0AE));
    }
    if (focusDefenderId != null && f0.pos.containsKey(focusDefenderId)) {
      ring(focusDefenderId!, const Color(0xFFFF8A80));
    }

    for (final d in r.defenders) {
      paintPlayer(canvas, tf, at(d.id), d.label, offense: false);
    }
    for (final p in play.players) {
      paintPlayer(canvas, tf, at(p.id), p.label,
          offense: true, square: p.role == Role.ol, highlight: p.id == eyes && showEyes);
    }

    // Ball (with shadow when in the air).
    final ball = Vec.lerp(f0.ball, f1.ball, u);
    final h = f0.ballHeight + (f1.ballHeight - f0.ballHeight) * u;
    final bc = tf.toScreen(ball);
    if (f0.ballState == BallState.air) {
      canvas.drawOval(Rect.fromCenter(center: bc, width: 10, height: 6),
          Paint()..color = Colors.black38);
    }
    final lifted = bc - Offset(0, h * tf.scale * 0.6);
    canvas.save();
    canvas.translate(lifted.dx, lifted.dy);
    canvas.rotate(-0.5);
    final ballRect = Rect.fromCenter(center: Offset.zero, width: 13, height: 8);
    canvas.drawOval(ballRect, Paint()..color = const Color(0xFF8D4E2A));
    canvas.drawLine(const Offset(-3, 0), const Offset(3, 0),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SimPainter old) => true;
}
