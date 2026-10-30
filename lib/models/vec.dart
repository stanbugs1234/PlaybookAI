import 'dart:math' as math;

/// A 2D point/vector in field yards.
///
/// x runs sideline to sideline (0 – [Field.width]); y is depth relative to the
/// line of scrimmage, positive downfield (the offense attacks toward +y).
class Vec {
  final double x;
  final double y;
  const Vec(this.x, this.y);

  static const zero = Vec(0, 0);

  Vec operator +(Vec o) => Vec(x + o.x, y + o.y);
  Vec operator -(Vec o) => Vec(x - o.x, y - o.y);
  Vec operator *(double s) => Vec(x * s, y * s);
  Vec operator /(double s) => Vec(x / s, y / s);

  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Vec o) => (this - o).length;

  Vec normalized() {
    final l = length;
    return l < 1e-9 ? Vec.zero : this / l;
  }

  double dot(Vec o) => x * o.x + y * o.y;

  /// Moves toward [target] by at most [maxStep].
  Vec stepToward(Vec target, double maxStep) {
    final d = target - this;
    final l = d.length;
    if (l <= maxStep || l < 1e-9) return target;
    return this + d * (maxStep / l);
  }

  Vec clampToField() => Vec(x.clamp(0.5, Field.width - 0.5), y);

  Vec mirrorX() => Vec(Field.width - x, y);

  static Vec lerp(Vec a, Vec b, double t) => a + (b - a) * t;

  Map<String, dynamic> toJson() => {'x': _r(x), 'y': _r(y)};
  factory Vec.fromJson(Map<String, dynamic> j) =>
      Vec((j['x'] as num).toDouble(), (j['y'] as num).toDouble());

  static double _r(double v) => (v * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) =>
      other is Vec && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'Vec(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Distance from point [p] to segment [a]-[b], and the param t along it.
({double dist, double t}) distanceToSegment(Vec p, Vec a, Vec b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 < 1e-9) return (dist: p.distanceTo(a), t: 0);
  final t = ((p - a).dot(ab) / len2).clamp(0.0, 1.0);
  return (dist: p.distanceTo(a + ab * t), t: t);
}

abstract final class Field {
  static const double width = 160 / 3; // 53.33 yards
  static const double center = width / 2;
  static const double leftHash = center - 3.08; // NFL hashes are 18'6" apart
  static const double rightHash = center + 3.08;

  /// Yards from the line of scrimmage to the goal line (ball on own 25).
  static const double yardsToGoal = 75;
}
