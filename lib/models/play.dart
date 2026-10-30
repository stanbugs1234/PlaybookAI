import 'vec.dart';

enum Role { qb, rb, fb, wr, te, ol }

extension RoleX on Role {
  bool get isEligible => this != Role.ol && this != Role.qb;

  /// Top speed in yards/second.
  double get topSpeed => switch (this) {
        Role.wr => 8.7,
        Role.rb => 8.4,
        Role.te => 7.6,
        Role.fb => 7.1,
        Role.qb => 6.6,
        Role.ol => 5.4,
      };
}

class OffPlayer {
  final String id;
  final Role role;
  final String label;
  final Vec pos;

  const OffPlayer({
    required this.id,
    required this.role,
    required this.label,
    required this.pos,
  });

  OffPlayer copyWith({Vec? pos, Role? role, String? label}) => OffPlayer(
        id: id,
        role: role ?? this.role,
        label: label ?? this.label,
        pos: pos ?? this.pos,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'role': role.name, 'label': label, 'pos': pos.toJson()};

  factory OffPlayer.fromJson(Map<String, dynamic> j) => OffPlayer(
        id: j['id'] as String,
        role: Role.values.byName(j['role'] as String),
        label: j['label'] as String,
        pos: Vec.fromJson(j['pos'] as Map<String, dynamic>),
      );
}

enum PlayType { pass, run, playAction }

enum QbDrop { quick, threeStep, fiveStep, sevenStep }

extension QbDropX on QbDrop {
  String get label => switch (this) {
        QbDrop.quick => 'Quick (gun)',
        QbDrop.threeStep => '3-step',
        QbDrop.fiveStep => '5-step',
        QbDrop.sevenStep => '7-step',
      };

  /// Seconds until the QB is set and can throw on rhythm.
  double get setTime => switch (this) {
        QbDrop.quick => 0.55,
        QbDrop.threeStep => 0.95,
        QbDrop.fiveStep => 1.45,
        QbDrop.sevenStep => 1.95,
      };

  /// Depth (yards behind LOS) the QB sets at.
  double get depth => switch (this) {
        QbDrop.quick => 5.5,
        QbDrop.threeStep => 5,
        QbDrop.fiveStep => 7,
        QbDrop.sevenStep => 9,
      };
}

/// What an offensive player does on the snap.
sealed class Assignment {
  const Assignment();

  Map<String, dynamic> toJson();

  factory Assignment.fromJson(Map<String, dynamic> j) =>
      switch (j['type'] as String) {
        'route' => RouteAssignment(
            name: j['name'] as String?,
            waypoints: _vecs(j['waypoints']),
          ),
        'block' => const BlockAssignment(),
        'run' => RunAssignment(
            name: j['name'] as String?,
            path: _vecs(j['path']),
          ),
        _ => const BlockAssignment(),
      };

  static List<Vec> _vecs(Object? raw) => (raw as List)
      .map((e) => Vec.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// A pass route as absolute field waypoints (excluding the start position).
class RouteAssignment extends Assignment {
  final String? name;
  final List<Vec> waypoints;
  const RouteAssignment({this.name, required this.waypoints});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'route',
        if (name != null) 'name': name,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
      };
}

/// Pass protection (or run blocking on run plays).
class BlockAssignment extends Assignment {
  const BlockAssignment();
  @override
  Map<String, dynamic> toJson() => {'type': 'block'};
}

/// Ball-carrier path for run plays (the fake path on play-action).
class RunAssignment extends Assignment {
  final String? name;
  final List<Vec> path;
  const RunAssignment({this.name, required this.path});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'run',
        if (name != null) 'name': name,
        'path': path.map((w) => w.toJson()).toList(),
      };
}

class Play {
  final String id;
  final String name;
  final String formation;
  final PlayType playType;
  final QbDrop drop;
  final List<OffPlayer> players;
  final Map<String, Assignment> assignments;

  /// QB read order, as player ids.
  final List<String> progression;
  final String notes;
  final DateTime updatedAt;

  const Play({
    required this.id,
    required this.name,
    required this.formation,
    required this.playType,
    required this.drop,
    required this.players,
    required this.assignments,
    required this.progression,
    this.notes = '',
    required this.updatedAt,
  });

  OffPlayer player(String id) => players.firstWhere((p) => p.id == id);
  OffPlayer? playerOrNull(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  OffPlayer get qb => players.firstWhere((p) => p.role == Role.qb);

  /// The ball carrier on a run (or the faked runner on play-action).
  String? get runnerId {
    for (final e in assignments.entries) {
      if (e.value is RunAssignment) return e.key;
    }
    return null;
  }

  /// Players who release into a route.
  Iterable<OffPlayer> get routeRunners =>
      players.where((p) => assignments[p.id] is RouteAssignment);

  Play copyWith({
    String? id,
    String? name,
    String? formation,
    PlayType? playType,
    QbDrop? drop,
    List<OffPlayer>? players,
    Map<String, Assignment>? assignments,
    List<String>? progression,
    String? notes,
    DateTime? updatedAt,
  }) =>
      Play(
        id: id ?? this.id,
        name: name ?? this.name,
        formation: formation ?? this.formation,
        playType: playType ?? this.playType,
        drop: drop ?? this.drop,
        players: players ?? this.players,
        assignments: assignments ?? this.assignments,
        progression: progression ?? this.progression,
        notes: notes ?? this.notes,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Mirrors the whole play across the middle of the field.
  Play flipped() => copyWith(
        players: [for (final p in players) p.copyWith(pos: p.pos.mirrorX())],
        assignments: assignments.map((id, a) => MapEntry(
              id,
              switch (a) {
                RouteAssignment r => RouteAssignment(
                    name: r.name,
                    waypoints: r.waypoints.map((w) => w.mirrorX()).toList()),
                RunAssignment r => RunAssignment(
                    name: r.name, path: r.path.map((w) => w.mirrorX()).toList()),
                BlockAssignment b => b,
              },
            )),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'formation': formation,
        'playType': playType.name,
        'drop': drop.name,
        'players': players.map((p) => p.toJson()).toList(),
        'assignments': assignments.map((k, v) => MapEntry(k, v.toJson())),
        'progression': progression,
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Play.fromJson(Map<String, dynamic> j) => Play(
        id: j['id'] as String,
        name: j['name'] as String,
        formation: j['formation'] as String? ?? 'Custom',
        playType: PlayType.values.byName(j['playType'] as String),
        drop: QbDrop.values.byName(j['drop'] as String? ?? 'fiveStep'),
        players: (j['players'] as List)
            .map((e) => OffPlayer.fromJson(e as Map<String, dynamic>))
            .toList(),
        assignments: (j['assignments'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, Assignment.fromJson(v as Map<String, dynamic>))),
        progression: (j['progression'] as List).cast<String>(),
        notes: j['notes'] as String? ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
