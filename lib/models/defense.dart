import 'vec.dart';

enum Front { fourThree, threeFour, nickel, dime }

extension FrontX on Front {
  String get label => switch (this) {
        Front.fourThree => '4-3 Base',
        Front.threeFour => '3-4 Base',
        Front.nickel => 'Nickel 4-2-5',
        Front.dime => 'Dime 4-1-6',
      };
}

enum Coverage { cover0, cover1, cover2, tampa2, cover3, cover4, cover6, twoMan }

extension CoverageX on Coverage {
  String get label => switch (this) {
        Coverage.cover0 => 'Cover 0',
        Coverage.cover1 => 'Cover 1',
        Coverage.cover2 => 'Cover 2',
        Coverage.tampa2 => 'Tampa 2',
        Coverage.cover3 => 'Cover 3',
        Coverage.cover4 => 'Cover 4',
        Coverage.cover6 => 'Cover 6',
        Coverage.twoMan => '2-Man',
      };

  String get summary => switch (this) {
        Coverage.cover0 =>
          'Pure man, no deep safety, 6+ rushers. Quick throws beat it.',
        Coverage.cover1 =>
          'Man-free: man underneath, one deep safety, often a robber.',
        Coverage.cover2 =>
          'Two deep halves, corners squat the flats, 3 underneath hooks.',
        Coverage.tampa2 =>
          'Cover 2 with the Mike running the deep middle hole.',
        Coverage.cover3 =>
          'Three deep thirds, four underneath (curl/flat, hook).',
        Coverage.cover4 =>
          'Quarters: four deep, three under. Strong vs verticals and the run.',
        Coverage.cover6 =>
          'Quarter-quarter-half: Cover 4 to the strength, Cover 2 to the weak side.',
        Coverage.twoMan =>
          'Man underneath with two deep safeties over the top.',
      };

  bool get isMan =>
      this == Coverage.cover0 || this == Coverage.cover1 || this == Coverage.twoMan;
}

enum Blitz { none, mike, slot, safety }

extension BlitzX on Blitz {
  String get label => switch (this) {
        Blitz.none => 'No blitz',
        Blitz.mike => 'Mike A-gap',
        Blitz.slot => 'Nickel/Sam edge',
        Blitz.safety => 'Strong safety',
      };
}

enum DefGroup { dl, lb, db }

extension DefGroupX on DefGroup {
  double get topSpeed => switch (this) {
        DefGroup.dl => 6.3,
        DefGroup.lb => 7.8,
        DefGroup.db => 8.5,
      };
}

sealed class DefAssignment {
  const DefAssignment();
  String get description;
}

class ManCover extends DefAssignment {
  final String targetId;
  final String targetLabel;
  const ManCover(this.targetId, this.targetLabel);
  @override
  String get description => 'Man on $targetLabel';
}

class ZoneCover extends DefAssignment {
  final String name;
  final Vec landmark;

  /// Half-width and half-depth of the zone area this defender owns.
  final double rx;
  final double ry;
  final bool deep;
  const ZoneCover(this.name, this.landmark,
      {this.rx = 7, this.ry = 5, this.deep = false});
  @override
  String get description => name;

  bool contains(Vec p) =>
      (p.x - landmark.x).abs() <= rx && (p.y - landmark.y).abs() <= ry;
}

class Rush extends DefAssignment {
  /// Lateral aiming point at the line (a gap).
  final double gapX;
  final bool blitzer;
  const Rush(this.gapX, {this.blitzer = false});
  @override
  String get description => blitzer ? 'Blitz' : 'Pass rush';
}

class Defender {
  final String id;
  final String label;
  final DefGroup group;
  final Vec pos;
  final DefAssignment assignment;

  const Defender({
    required this.id,
    required this.label,
    required this.group,
    required this.pos,
    required this.assignment,
  });

  Defender copyWith({Vec? pos, DefAssignment? assignment}) => Defender(
        id: id,
        label: label,
        group: group,
        pos: pos ?? this.pos,
        assignment: assignment ?? this.assignment,
      );
}

class DefenseCall {
  final Front front;
  final Coverage coverage;
  final Blitz blitz;
  const DefenseCall(this.front, this.coverage, [this.blitz = Blitz.none]);

  String get label =>
      '${front.label} · ${coverage.label}${blitz == Blitz.none ? '' : ' · ${blitz.label}'}';

  DefenseCall copyWith({Front? front, Coverage? coverage, Blitz? blitz}) =>
      DefenseCall(front ?? this.front, coverage ?? this.coverage,
          blitz ?? this.blitz);

  @override
  bool operator ==(Object other) =>
      other is DefenseCall &&
      other.front == front &&
      other.coverage == coverage &&
      other.blitz == blitz;
  @override
  int get hashCode => Object.hash(front, coverage, blitz);
}
