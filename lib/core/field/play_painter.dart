import 'package:flutter/material.dart';

import '../../models/defense.dart';
import '../../models/play.dart';
import '../../models/vec.dart';
import 'field_painter.dart';

/// Draws a play diagram: offense, assignments, read order and (optionally)
/// an aligned defense with zone shading.
class PlayDiagramPainter extends CustomPainter {
  final Play play;
  final String? selectedId;
  final List<Defender> defenders;
  final bool showZones;
  final bool compact;
  final double yTop;
  final double yBottom;

  PlayDiagramPainter({
    required this.play,
    this.selectedId,
    this.defenders = const [],
    this.showZones = false,
    this.compact = false,
    this.yTop = 30,
    this.yBottom = -12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tf = FieldTransform(size, yTop: yTop, yBottom: yBottom);
    canvas.save();
    canvas.clipRect(tf.fieldRect);
    paintField(canvas, tf, showNumbers: !compact);

    if (showZones) paintZones(canvas, tf, defenders);

    for (final p in play.players) {
      final a = play.assignments[p.id];
      switch (a) {
        case RouteAssignment r:
          paintPath(canvas, tf, [p.pos, ...r.waypoints],
              color: p.id == selectedId ? FieldColors.firstDown : FieldColors.route,
              width: compact ? 1.6 : 2.4);
        case RunAssignment r:
          paintPath(canvas, tf, [p.pos, ...r.path],
              color: FieldColors.run, width: compact ? 1.6 : 2.6, dashed: play.playType == PlayType.playAction);
        case BlockAssignment _:
          if (p.role != Role.ol || !compact) paintBlockStub(canvas, tf, p.pos);
        case null:
          break;
      }
    }

    for (final d in defenders) {
      paintPlayer(canvas, tf, d.pos, d.label, offense: false, radiusYards: compact ? 0.9 : 1.0);
    }

    for (final p in play.players) {
      paintPlayer(canvas, tf, p.pos, compact ? '' : p.label,
          offense: true,
          square: p.role == Role.ol,
          highlight: p.id == selectedId,
          radiusYards: compact ? 0.9 : 1.0);
    }

    if (!compact) {
      for (var i = 0; i < play.progression.length; i++) {
        final p = play.playerOrNull(play.progression[i]);
        final a = p == null ? null : play.assignments[p.id];
        if (a is! RouteAssignment || a.waypoints.isEmpty) continue;
        final end = tf.toScreen(a.waypoints.last);
        paintBadge(canvas, end + const Offset(10, -10), '${i + 1}', FieldColors.firstDown);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlayDiagramPainter old) =>
      old.play != play ||
      old.selectedId != selectedId ||
      old.defenders != defenders ||
      old.showZones != showZones;
}

void paintZones(Canvas canvas, FieldTransform tf, List<Defender> defenders) {
  for (final d in defenders) {
    final z = d.assignment;
    if (z is! ZoneCover) continue;
    final center = tf.toScreen(z.landmark);
    final rect = Rect.fromCenter(
        center: center, width: z.rx * 2 * tf.scale, height: z.ry * 2 * tf.scale);
    final color = z.deep ? const Color(0xFF7E57C2) : const Color(0xFF26C6DA);
    canvas.drawOval(rect, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1);
    canvas.drawLine(tf.toScreen(d.pos), center,
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 1);
  }
  for (final d in defenders) {
    final m = d.assignment;
    if (m is ManCover) {
      // Man responsibilities are drawn by the caller, which knows positions.
      continue;
    }
    if (m is Rush) {
      final from = tf.toScreen(d.pos);
      final to = tf.toScreen(Vec(m.gapX, -0.5));
      canvas.drawLine(from, to,
          Paint()
            ..color = FieldColors.defense.withValues(alpha: 0.7)
            ..strokeWidth = 2);
    }
  }
}
