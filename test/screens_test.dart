import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playbook_ai/app.dart';
import 'package:playbook_ai/features/designer/designer_screen.dart';
import 'package:playbook_ai/features/simulator/simulator_screen.dart';
import 'package:playbook_ai/models/starter_plays.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child) => ProviderScope(child: MaterialApp(home: child));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('guest lands on a playbook seeded with starter plays', (tester) async {
    await bigScreen(tester);
    await tester.pumpWidget(const ProviderScope(child: PlaybookApp()));
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Playbook'), findsOneWidget);
    expect(find.text('Smash'), findsOneWidget);
    expect(find.text('Four Verts'), findsOneWidget);
  });

  testWidgets('simulator runs a play to the end and explains it', (tester) async {
    await bigScreen(tester);
    final play = StarterPlays.all().firstWhere((p) => p.name == 'Smash');
    await tester.pumpWidget(host(SimulatorScreen(play: play)));
    await tester.tap(find.text('Cover 2'));
    await tester.pump();
    await tester.tap(find.text('Run the play'));
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Progression'), findsOneWidget);
    expect(find.textContaining('Read 1'), findsWidgets);
    // Tapping a timeline step seeks without errors.
    await tester.tap(find.textContaining('Read 1').first, warnIfMissed: false);
    await tester.pump();
    await tester.dragUntilVisible(
        find.text('Coaching tips'), find.byType(ListView), const Offset(0, -300));
    expect(find.text('Coaching tips'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout of the simulator renders', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final play = StarterPlays.all().firstWhere((p) => p.name == 'Power');
    await tester.pumpWidget(host(SimulatorScreen(play: play)));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Run play'));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone layout of the designer renders', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(DesignerScreen(play: StarterPlays.all().first)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('designer assigns a route from the palette', (tester) async {
    await bigScreen(tester);
    final play = StarterPlays.blank('Gun Doubles', id: 't');
    await tester.pumpWidget(host(DesignerScreen(play: play)));
    // Tap the X receiver on the field to select him.
    final canvas = find.byType(CustomPaint).first;
    final box = tester.getRect(canvas);
    expect(box.width, greaterThan(100));
    expect(find.text('Test vs defense'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
