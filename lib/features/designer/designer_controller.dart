import 'package:flutter/foundation.dart';

import '../../models/formations.dart';
import '../../models/play.dart';
import '../../models/route_tree.dart';
import '../../models/vec.dart';

/// Editing state for one play, with undo/redo.
class DesignerController extends ChangeNotifier {
  Play _play;
  String? selectedId;
  bool drawMode = false;
  bool dirty = false;
  final _undo = <Play>[];
  final _redo = <Play>[];

  DesignerController(this._play);

  Play get play => _play;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  OffPlayer? get selected =>
      selectedId == null ? null : _play.playerOrNull(selectedId!);

  void _commit(Play next, {bool push = true}) {
    if (push) {
      _undo.add(_play);
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    _play = next.copyWith(updatedAt: DateTime.now());
    dirty = true;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_play);
    _play = _undo.removeLast();
    dirty = true;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_play);
    _play = _redo.removeLast();
    dirty = true;
    notifyListeners();
  }

  void markSaved() {
    dirty = false;
    notifyListeners();
  }

  void select(String? id) {
    selectedId = id;
    if (id == null) drawMode = false;
    notifyListeners();
  }

  void setDrawMode(bool v) {
    drawMode = v;
    notifyListeners();
  }

  // ---- Play-level ----------------------------------------------------------
  void rename(String name) => _commit(_play.copyWith(name: name), push: false);
  void setNotes(String notes) => _commit(_play.copyWith(notes: notes), push: false);
  void setDrop(QbDrop d) => _commit(_play.copyWith(drop: d));
  void flip() => _commit(_play.flipped());

  void setType(PlayType type) {
    final asg = Map<String, Assignment>.of(_play.assignments);
    final hasRun = asg.values.any((a) => a is RunAssignment);
    if (type == PlayType.pass) {
      asg.updateAll((k, v) => v is RunAssignment ? const BlockAssignment() : v);
    } else if (!hasRun) {
      final back = _play.players
          .where((p) => p.role == Role.rb || p.role == Role.fb)
          .firstOrNull;
      if (back != null) {
        asg[back.id] = RunTree.byName('Inside Zone')!.apply(back.pos, toRight: true);
      }
    }
    _commit(_play.copyWith(playType: type, assignments: asg));
  }

  void setFormation(String name) {
    final next = Formations.build(name);
    final asg = <String, Assignment>{};
    for (final p in next) {
      final old = _play.playerOrNull(p.id);
      final a = _play.assignments[p.id];
      if (p.role == Role.qb) continue;
      if (p.role == Role.ol) {
        asg[p.id] = const BlockAssignment();
        continue;
      }
      asg[p.id] = switch (a) {
        RouteAssignment r when RouteTree.byName(r.name ?? '') != null =>
          RouteTree.byName(r.name!)!.apply(p.pos),
        RouteAssignment r when old != null =>
          _translateRoute(r, p.pos - old.pos),
        RunAssignment r when RunTree.byName(r.name ?? '') != null && old != null =>
          RunTree.byName(r.name!)!.apply(p.pos,
              toRight: (r.path.lastOrNull?.x ?? old.pos.x) >= old.pos.x),
        BlockAssignment b => b,
        _ => p.role == Role.rb || p.role == Role.fb
            ? const BlockAssignment()
            : RouteTree.byName('Go')!.apply(p.pos),
      };
    }
    _commit(_play.copyWith(formation: name, players: next, assignments: asg));
  }

  // ---- Player-level --------------------------------------------------------
  RouteAssignment _translateRoute(RouteAssignment r, Vec delta) => RouteAssignment(
      name: r.name,
      waypoints: [for (final w in r.waypoints) (w + delta).clampToField()]);

  bool _dragging = false;

  void beginDrag() {
    if (_dragging) return;
    _dragging = true;
    _undo.add(_play);
    _redo.clear();
  }

  void endDrag() => _dragging = false;

  void movePlayer(String id, Vec to) {
    final p = _play.player(id);
    final clamped = Vec(to.x.clamp(1.0, Field.width - 1),
        p.role == Role.ol ? p.pos.y : to.y.clamp(-12.0, -0.5));
    final delta = clamped - p.pos;
    final asg = Map<String, Assignment>.of(_play.assignments);
    final a = asg[id];
    if (a is RouteAssignment) asg[id] = _translateRoute(a, delta);
    if (a is RunAssignment) {
      asg[id] = RunAssignment(
          name: a.name, path: [for (final w in a.path) (w + delta).clampToField()]);
    }
    _commit(
        _play.copyWith(
          formation: _play.formation.endsWith('*') ? _play.formation : '${_play.formation}*',
          players: [for (final x in _play.players) x.id == id ? x.copyWith(pos: clamped) : x],
          assignments: asg,
        ),
        push: false);
  }

  void moveWaypoint(String id, int index, Vec to) {
    final a = _play.assignments[id];
    final asg = Map<String, Assignment>.of(_play.assignments);
    final v = to.clampToField();
    if (a is RouteAssignment) {
      final w = [...a.waypoints]..[index] = v;
      asg[id] = RouteAssignment(name: 'Custom', waypoints: w);
    } else if (a is RunAssignment) {
      final w = [...a.path]..[index] = v;
      asg[id] = RunAssignment(name: 'Custom', path: w);
    }
    _commit(_play.copyWith(assignments: asg), push: false);
  }

  void setRoute(String id, String templateName) {
    final p = _play.player(id);
    final t = RouteTree.byName(templateName)!;
    final asg = Map<String, Assignment>.of(_play.assignments)..[id] = t.apply(p.pos);
    _commit(_play.copyWith(assignments: asg));
  }

  void setRun(String id, String name, {required bool toRight}) {
    final p = _play.player(id);
    final asg = Map<String, Assignment>.of(_play.assignments);
    // Only one ball carrier.
    asg.updateAll((k, v) => v is RunAssignment ? const BlockAssignment() : v);
    asg[id] = RunTree.byName(name)!.apply(p.pos, toRight: toRight);
    final prog = _play.progression.where((x) => x != id).toList();
    _commit(_play.copyWith(assignments: asg, progression: prog));
  }

  void setBlock(String id) {
    final asg = Map<String, Assignment>.of(_play.assignments)
      ..[id] = const BlockAssignment();
    final prog = _play.progression.where((x) => x != id).toList();
    _commit(_play.copyWith(assignments: asg, progression: prog));
  }

  void addWaypoint(String id, Vec at) {
    final p = _play.player(id);
    if (p.role == Role.ol || p.role == Role.qb) return;
    final a = _play.assignments[id];
    final pt = Vec((at.x * 2).roundToDouble() / 2, (at.y * 2).roundToDouble() / 2)
        .clampToField();
    final asg = Map<String, Assignment>.of(_play.assignments);
    if (a is RunAssignment && _play.playType != PlayType.pass) {
      asg[id] = RunAssignment(name: 'Custom', path: [...a.path, pt]);
    } else {
      final existing = (a is RouteAssignment && a.name == 'Custom') ? a.waypoints : <Vec>[];
      asg[id] = RouteAssignment(name: 'Custom', waypoints: [...existing, pt]);
    }
    _commit(_play.copyWith(assignments: asg));
  }

  void removeLastWaypoint(String id) {
    final a = _play.assignments[id];
    final asg = Map<String, Assignment>.of(_play.assignments);
    if (a is RouteAssignment && a.waypoints.isNotEmpty) {
      final w = [...a.waypoints]..removeLast();
      asg[id] = w.isEmpty
          ? const BlockAssignment()
          : RouteAssignment(name: 'Custom', waypoints: w);
    } else if (a is RunAssignment && a.path.length > 1) {
      asg[id] = RunAssignment(name: 'Custom', path: [...a.path]..removeLast());
    } else {
      return;
    }
    _commit(_play.copyWith(assignments: asg));
  }

  void toggleRead(String id) {
    final prog = [..._play.progression];
    if (prog.contains(id)) {
      prog.remove(id);
    } else if (_play.assignments[id] is RouteAssignment) {
      prog.add(id);
    }
    _commit(_play.copyWith(progression: prog));
  }

  void reorderReads(int oldIndex, int newIndex) {
    final prog = [..._play.progression];
    final item = prog.removeAt(oldIndex);
    prog.insert(newIndex, item);
    _commit(_play.copyWith(progression: prog));
  }

  void clearReads() => _commit(_play.copyWith(progression: const []));
}
