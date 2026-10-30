import 'package:flutter_test/flutter_test.dart';
import 'package:playbook_ai/features/designer/designer_controller.dart';
import 'package:playbook_ai/models/play.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:playbook_ai/models/vec.dart';

void main() {
  test('assigning routes, reads, undo and redo', () {
    final c = DesignerController(StarterPlays.blank('Gun Doubles', id: 't'));
    c.setRoute('x', 'Slant');
    expect((c.play.assignments['x'] as RouteAssignment).name, 'Slant');
    c.toggleRead('x');
    expect(c.play.progression, ['x']);
    c.undo();
    expect(c.play.progression, isEmpty);
    c.redo();
    expect(c.play.progression, ['x']);
  });

  test('blocking removes a player from the read order', () {
    final c = DesignerController(StarterPlays.blank('Gun Doubles', id: 't'));
    c.toggleRead('h');
    c.setBlock('h');
    expect(c.play.progression, isEmpty);
  });

  test('moving a player carries his route with him', () {
    final c = DesignerController(StarterPlays.blank('Gun Doubles', id: 't'));
    c.setRoute('z', 'Go');
    final before = (c.play.assignments['z'] as RouteAssignment).waypoints.first;
    final start = c.play.player('z').pos;
    c.beginDrag();
    c.movePlayer('z', start + const Vec(-3, 0));
    c.endDrag();
    final after = (c.play.assignments['z'] as RouteAssignment).waypoints.first;
    expect(after.x, closeTo(before.x - 3, 0.01));
  });

  test('custom route drawing and formation change keep named routes', () {
    final c = DesignerController(StarterPlays.blank('Gun Doubles', id: 't'));
    c.addWaypoint('y', const Vec(30, 5));
    c.addWaypoint('y', const Vec(20, 12));
    expect((c.play.assignments['y'] as RouteAssignment).waypoints.length, 2);
    c.setRoute('x', 'Post');
    c.setFormation('Gun Trips Right');
    expect((c.play.assignments['x'] as RouteAssignment).name, 'Post');
  });

  test('switching to a run gives the back a run path', () {
    final c = DesignerController(StarterPlays.blank('I-Form Pro', id: 't'));
    c.setType(PlayType.run);
    expect(c.play.runnerId, isNotNull);
    c.setType(PlayType.pass);
    expect(c.play.runnerId, isNull);
  });
}
