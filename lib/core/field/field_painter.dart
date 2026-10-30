import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/vec.dart';

/// Maps field yards to screen pixels. The offense attacks up the screen.
class FieldTransform {
  final Size size;
  final double yTop;
  final double yBottom;
  late final double scale;
  late final Offset origin;

  FieldTransform(this.size, {this.yTop = 30, this.yBottom = -12}) {
    final h = yTop - yBottom;
    scale = math.min(size.width / Field.width, size.height / h);
    final w = Field.width * scale;
    origin = Offset((size.width - w) / 2, (size.height - h * scale) / 2);
  }

  Offset toScreen(Vec v) =>
      Offset(origin.dx + v.x * scale, origin.dy + (yTop - v.y) * scale);

  Vec toField(Offset o) =>
      Vec((o.dx - origin.dx) / scale, yTop - (o.dy - origin.dy) / scale);

  Rect get fieldRect => Rect.fromLTWH(
      origin.dx, origin.dy, Field.width * scale, (yTop - yBottom) * scale);
}

abstract final class FieldColors {
  static const grass = Color(0xFF2E7D32);
  static const grassAlt = Color(0xFF388E3C);
  static const line = Color(0xCCFFFFFF);
  static const los = Color(0xFF64B5F6);
  static const firstDown = Color(0xFFFFEB3B);
  static const offense = Color(0xFF1565C0);
  static const defense = Color(0xFFC62828);
  static const route = Color(0xFFFFFFFF);
  static const run = Color(0xFFFFA726);
  static const block = Color(0xFFB0BEC5);
}

/// Paints grass, yard lines, hashes, numbers, LOS and line to gain.
void paintField(Canvas canvas, FieldTransform tf, {bool showNumbers = true}) {
  final rect = tf.fieldRect;
  canvas.drawRect(rect, Paint()..color = FieldColors.grass);

  final lo = tf.yBottom.floor();
  final hi = tf.yTop.ceil();
  // Alternating 5-yard stripes.
  for (var y = (lo ~/ 5) * 5; y < hi; y += 5) {
    if ((y ~/ 5).isEven) continue;
    final a = tf.toScreen(Vec(0, y + 5.0));
    final b = tf.toScreen(Vec(Field.width, y.toDouble()));
    canvas.drawRect(Rect.fromPoints(a, b).intersect(rect),
        Paint()..color = FieldColors.grassAlt);
  }

  final linePaint = Paint()
    ..color = FieldColors.line
    ..strokeWidth = 1.2;
  final thin = Paint()
    ..color = FieldColors.line
    ..strokeWidth = 1;
  for (var y = lo; y <= hi; y++) {
    if (y < tf.yBottom || y > tf.yTop) continue;
    final yy = y.toDouble();
    if (y % 5 == 0) {
      canvas.drawLine(tf.toScreen(Vec(0, yy)), tf.toScreen(Vec(Field.width, yy)), linePaint);
    } else {
      // Hash ticks and sideline ticks.
      for (final x in [0.3, Field.leftHash, Field.rightHash, Field.width - 1.3]) {
        canvas.drawLine(tf.toScreen(Vec(x, yy)), tf.toScreen(Vec(x + 1, yy)), thin);
      }
    }
  }

  if (showNumbers && tf.scale > 6) {
    for (var y = (lo ~/ 10) * 10 + 5; y <= hi; y += 10) {
      // Ball on the offense's own 25: LOS (y=0) is the 25, y=5 is the 30.
      final yardLine = 25 + y;
      if (yardLine % 10 != 0 || yardLine <= 0 || yardLine >= 100) continue;
      final label = '${yardLine > 50 ? 100 - yardLine : yardLine}';
      for (final x in [9.0, Field.width - 9.0]) {
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  color: FieldColors.line,
                  fontSize: tf.scale * 2,
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = tf.toScreen(Vec(x, y.toDouble()));
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  canvas.drawLine(tf.toScreen(const Vec(0, 0)), tf.toScreen(const Vec(Field.width, 0)),
      Paint()
        ..color = FieldColors.los
        ..strokeWidth = 2);
  canvas.drawLine(tf.toScreen(const Vec(0, 10)), tf.toScreen(const Vec(Field.width, 10)),
      Paint()
        ..color = FieldColors.firstDown
        ..strokeWidth = 2);
}

void paintPlayer(Canvas canvas, FieldTransform tf, Vec pos, String label,
    {required bool offense,
    bool square = false,
    bool highlight = false,
    bool dim = false,
    Color? color,
    double radiusYards = 1.0}) {
  final c = tf.toScreen(pos);
  final r = math.max(7.0, tf.scale * radiusYards);
  final base = color ?? (offense ? FieldColors.offense : FieldColors.defense);
  final fill = Paint()..color = dim ? base.withValues(alpha: 0.45) : base;
  if (highlight) {
    canvas.drawCircle(c, r + 5, Paint()..color = const Color(0xAAFFEB3B));
  }
  if (square) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCircle(center: c, radius: r), const Radius.circular(3)),
        fill);
  } else {
    canvas.drawCircle(c, r, fill);
  }
  canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white
        ..strokeWidth = 1.4);
  final tp = TextPainter(
    text: TextSpan(
        text: label,
        style: TextStyle(
            color: Colors.white,
            fontSize: r * (label.length > 2 ? 0.75 : 0.95),
            fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
}

/// Draws a polyline with an arrowhead (routes) or a T (blocks).
void paintPath(Canvas canvas, FieldTransform tf, List<Vec> pts,
    {required Color color,
    double width = 2.4,
    bool arrow = true,
    bool dashed = false}) {
  if (pts.length < 2) return;
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final screen = pts.map(tf.toScreen).toList();
  if (dashed) {
    for (var i = 0; i < screen.length - 1; i++) {
      _dash(canvas, screen[i], screen[i + 1], paint);
    }
  } else {
    final path = Path()..moveTo(screen.first.dx, screen.first.dy);
    for (final p in screen.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }
  if (arrow) {
    final a = screen[screen.length - 2];
    final b = screen.last;
    final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
    const len = 10.0;
    final head = Path()
      ..moveTo(b.dx, b.dy)
      ..lineTo(b.dx - len * math.cos(ang - 0.45), b.dy - len * math.sin(ang - 0.45))
      ..lineTo(b.dx - len * math.cos(ang + 0.45), b.dy - len * math.sin(ang + 0.45))
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }
}

void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
  final d = b - a;
  final len = d.distance;
  if (len < 1) return;
  final dir = d / len;
  const on = 6.0, off = 5.0;
  var t = 0.0;
  while (t < len) {
    final e = math.min(t + on, len);
    canvas.drawLine(a + dir * t, a + dir * e, paint);
    t = e + off;
  }
}

void paintBlockStub(Canvas canvas, FieldTransform tf, Vec from, {Color color = FieldColors.block}) {
  final a = tf.toScreen(from);
  final b = tf.toScreen(from + const Vec(0, 1.6));
  final p = Paint()
    ..color = color
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(a, b, p);
  final w = tf.scale * 0.7;
  canvas.drawLine(b - Offset(w, 0), b + Offset(w, 0), p);
}

void paintBadge(Canvas canvas, Offset at, String text, Color color) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
    textDirection: TextDirection.ltr,
  )..layout();
  final r = math.max(tp.width, tp.height) / 2 + 3;
  canvas.drawCircle(at, r, Paint()..color = color);
  tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
}
