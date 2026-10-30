import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/field/field_painter.dart';
import '../../core/field/play_painter.dart';
import '../../data/providers.dart';
import '../../models/formations.dart';
import '../../models/play.dart';
import '../../models/route_tree.dart';
import '../../models/vec.dart';
import '../simulator/simulator_screen.dart';
import 'designer_controller.dart';

class DesignerScreen extends ConsumerStatefulWidget {
  final Play play;
  const DesignerScreen({super.key, required this.play});

  @override
  ConsumerState<DesignerScreen> createState() => _DesignerScreenState();
}

class _DesignerScreenState extends ConsumerState<DesignerScreen> {
  late final DesignerController c = DesignerController(widget.play);
  late final TextEditingController _name = TextEditingController(text: widget.play.name);
  late final TextEditingController _notes = TextEditingController(text: widget.play.notes);

  @override
  void dispose() {
    c.dispose();
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(playRepositoryProvider).save(c.play);
    c.markSaved();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved "${c.play.name}"')));
    }
  }

  void _test() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SimulatorScreen(play: c.play)));

  Future<bool> _confirmLeave() async {
    if (!c.dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save this play before leaving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (r == 'save') await _save();
    return r == 'save' || r == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return PopScope(
          canPop: !c.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = Navigator.of(context);
            if (await _confirmLeave()) nav.pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(c.play.name),
              actions: [
                IconButton(
                    tooltip: 'Undo',
                    onPressed: c.canUndo ? c.undo : null,
                    icon: const Icon(Icons.undo)),
                IconButton(
                    tooltip: 'Redo',
                    onPressed: c.canRedo ? c.redo : null,
                    icon: const Icon(Icons.redo)),
                IconButton(
                    tooltip: 'Flip formation',
                    onPressed: c.flip,
                    icon: const Icon(Icons.flip)),
                IconButton(
                    tooltip: 'Save',
                    onPressed: _save,
                    icon: Icon(c.dirty ? Icons.save : Icons.save_outlined)),
                const SizedBox(width: 4),
                if (MediaQuery.sizeOf(context).width >= 600)
                  FilledButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Test vs defense'),
                  )
                else
                  IconButton.filled(
                    tooltip: 'Test vs defense',
                    onPressed: _test,
                    icon: const Icon(Icons.play_arrow),
                  ),
                const SizedBox(width: 12),
              ],
            ),
            body: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 900;
              final canvas = _DesignerCanvas(c: c);
              final panel = _Panel(c: c, name: _name, notes: _notes);
              if (wide) {
                return Row(children: [
                  Expanded(child: canvas),
                  SizedBox(width: 380, child: panel),
                ]);
              }
              return Column(children: [
                Expanded(flex: 3, child: canvas),
                Expanded(flex: 2, child: panel),
              ]);
            }),
          ),
        );
      },
    );
  }
}

class _DesignerCanvas extends StatefulWidget {
  final DesignerController c;
  const _DesignerCanvas({required this.c});

  @override
  State<_DesignerCanvas> createState() => _DesignerCanvasState();
}

class _DesignerCanvasState extends State<_DesignerCanvas> {
  String? _dragPlayer;
  int? _dragWaypoint;

  DesignerController get c => widget.c;

  String? _hitPlayer(Vec v) {
    String? best;
    var bd = 1.8;
    for (final p in c.play.players) {
      final d = p.pos.distanceTo(v);
      if (d < bd) {
        bd = d;
        best = p.id;
      }
    }
    return best;
  }

  List<Vec> _selectedPoints() {
    final a = c.selectedId == null ? null : c.play.assignments[c.selectedId!];
    return switch (a) {
      RouteAssignment r => r.waypoints,
      RunAssignment r => r.path,
      _ => const [],
    };
  }

  int? _hitWaypoint(Vec v) {
    final pts = _selectedPoints();
    for (var i = pts.length - 1; i >= 0; i--) {
      if (pts[i].distanceTo(v) < 1.4) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1B3A1E),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, box) {
        final tf = FieldTransform(box.biggest);
        return GestureDetector(
          onTapUp: (d) {
            final v = tf.toField(d.localPosition);
            final hit = _hitPlayer(v);
            if (c.drawMode && c.selectedId != null && (hit == null || hit == c.selectedId)) {
              if (hit == null) c.addWaypoint(c.selectedId!, v);
              return;
            }
            c.select(hit);
          },
          onPanStart: (d) {
            final v = tf.toField(d.localPosition);
            final wp = c.selectedId == null ? null : _hitWaypoint(v);
            if (wp != null) {
              _dragWaypoint = wp;
              c.beginDrag();
              return;
            }
            final hit = _hitPlayer(v);
            if (hit != null) {
              _dragPlayer = hit;
              c.select(hit);
              c.beginDrag();
            }
          },
          onPanUpdate: (d) {
            final v = tf.toField(d.localPosition);
            if (_dragWaypoint != null && c.selectedId != null) {
              c.moveWaypoint(c.selectedId!, _dragWaypoint!, v);
            } else if (_dragPlayer != null) {
              c.movePlayer(_dragPlayer!, v);
            }
          },
          onPanEnd: (_) {
            _dragPlayer = null;
            _dragWaypoint = null;
            c.endDrag();
          },
          child: CustomPaint(
            size: box.biggest,
            painter: PlayDiagramPainter(play: c.play, selectedId: c.selectedId),
            foregroundPainter: _HandlesPainter(_selectedPoints(), c.drawMode),
          ),
        );
      }),
    );
  }
}

class _HandlesPainter extends CustomPainter {
  final List<Vec> points;
  final bool drawMode;
  _HandlesPainter(this.points, this.drawMode);

  @override
  void paint(Canvas canvas, Size size) {
    final tf = FieldTransform(size);
    for (final p in points) {
      final o = tf.toScreen(p);
      canvas.drawCircle(o, 6, Paint()..color = FieldColors.firstDown);
      canvas.drawCircle(
          o,
          6,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.black54);
    }
    if (drawMode) {
      final tp = TextPainter(
        text: const TextSpan(
            text: 'Tap the field to add route points',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = Rect.fromLTWH(10, 10, tp.width + 16, tp.height + 10);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)),
          Paint()..color = Colors.black54);
      tp.paint(canvas, const Offset(18, 15));
    }
  }

  @override
  bool shouldRepaint(covariant _HandlesPainter old) =>
      old.points != points || old.drawMode != drawMode;
}

class _Panel extends StatelessWidget {
  final DesignerController c;
  final TextEditingController name;
  final TextEditingController notes;
  const _Panel({required this.c, required this.name, required this.notes});

  @override
  Widget build(BuildContext context) {
    final play = c.play;
    final theme = Theme.of(context);
    final sel = c.selected;
    final formations = Formations.names;
    final formationValue = formations.contains(play.formation) ? play.formation : null;

    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Play name', border: OutlineInputBorder()),
            onChanged: c.rename,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: formationValue,
            isExpanded: true,
            hint: Text(play.formation),
            decoration: const InputDecoration(labelText: 'Formation', border: OutlineInputBorder()),
            items: [for (final f in formations) DropdownMenuItem(value: f, child: Text(f))],
            onChanged: (v) => v == null ? null : c.setFormation(v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<PlayType>(
            segments: const [
              ButtonSegment(value: PlayType.pass, label: Text('Pass'), icon: Icon(Icons.sports_football)),
              ButtonSegment(value: PlayType.run, label: Text('Run'), icon: Icon(Icons.directions_run)),
              ButtonSegment(value: PlayType.playAction, label: Text('PA')),
            ],
            selected: {play.playType},
            onSelectionChanged: (s) => c.setType(s.first),
          ),
          if (play.playType != PlayType.run) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<QbDrop>(
              initialValue: play.drop,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'QB drop', border: OutlineInputBorder()),
              items: [for (final d in QbDrop.values) DropdownMenuItem(value: d, child: Text(d.label))],
              onChanged: (v) => v == null ? null : c.setDrop(v),
            ),
          ],
          const Divider(height: 32),
          if (sel == null)
            Text('Tap a player to give him an assignment. Drag players to adjust the formation.',
                style: theme.textTheme.bodyMedium)
          else
            _PlayerSection(c: c, p: sel),
          if (play.playType != PlayType.run) ...[
            const Divider(height: 32),
            _ReadOrder(c: c),
          ],
          const Divider(height: 32),
          TextField(
            controller: notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Coaching notes', border: OutlineInputBorder()),
            onChanged: c.setNotes,
          ),
        ],
      ),
    );
  }
}

class _PlayerSection extends StatelessWidget {
  final DesignerController c;
  final OffPlayer p;
  const _PlayerSection({required this.c, required this.p});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = c.play.assignments[p.id];
    final current = switch (a) {
      RouteAssignment r => r.name ?? 'Custom',
      RunAssignment r => r.name ?? 'Custom run',
      BlockAssignment _ => 'Block',
      null => p.role == Role.qb ? 'Quarterback' : '—',
    };
    final isBack = p.role == Role.rb || p.role == Role.fb;
    final routes = RouteTree.all.where((r) => !r.backfieldOnly || isBack);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CircleAvatar(
            backgroundColor: FieldColors.offense,
            child: Text(p.label, style: const TextStyle(color: Colors.white))),
        const SizedBox(width: 12),
        Expanded(
            child: Text('${p.label} · ${p.role.name.toUpperCase()}\n$current',
                style: theme.textTheme.titleSmall)),
        IconButton(onPressed: () => c.select(null), icon: const Icon(Icons.close)),
      ]),
      if (p.role == Role.qb)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('The QB follows the drop and the read order you set below.'),
        ),
      if (p.role == Role.ol)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Linemen pass-protect or run-block automatically. Drag to adjust splits.'),
        ),
      if (p.role.isEligible) ...[
        const SizedBox(height: 12),
        Text('Routes', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in routes)
            Tooltip(
              message: r.description,
              child: ChoiceChip(
                label: Text(r.name),
                selected: current == r.name,
                onSelected: (_) => c.setRoute(p.id, r.name),
              ),
            ),
          ChoiceChip(
            label: const Text('Block'),
            selected: current == 'Block',
            onSelected: (_) => c.setBlock(p.id),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          FilterChip(
            avatar: const Icon(Icons.gesture, size: 18),
            label: const Text('Draw custom'),
            selected: c.drawMode,
            onSelected: c.setDrawMode,
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => c.removeLastWaypoint(p.id),
            icon: const Icon(Icons.backspace_outlined, size: 18),
            label: const Text('Undo point'),
          ),
        ]),
        if (isBack && c.play.playType != PlayType.pass) ...[
          const SizedBox(height: 12),
          Text(c.play.playType == PlayType.run ? 'Run concept' : 'Play-action fake',
              style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in RunTree.all)
              for (final right in [false, true])
                Tooltip(
                  message: r.description,
                  child: ChoiceChip(
                    label: Text('${r.name} ${right ? '→' : '←'}'),
                    selected: current == r.name && a is RunAssignment &&
                        ((a.path.lastOrNull?.x ?? p.pos.x) >= p.pos.x) == right,
                    onSelected: (_) => c.setRun(p.id, r.name, toRight: right),
                  ),
                ),
          ]),
        ],
        if (c.play.playType != PlayType.run && a is RouteAssignment) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => c.toggleRead(p.id),
            icon: Icon(c.play.progression.contains(p.id)
                ? Icons.remove_circle_outline
                : Icons.add_circle_outline),
            label: Text(c.play.progression.contains(p.id)
                ? 'Remove from read order'
                : 'Add to read order (#${c.play.progression.length + 1})'),
          ),
        ],
      ],
    ]);
  }
}

class _ReadOrder extends StatelessWidget {
  final DesignerController c;
  const _ReadOrder({required this.c});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prog = c.play.progression;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('QB progression', style: theme.textTheme.titleSmall)),
        if (prog.isNotEmpty)
          TextButton(onPressed: c.clearReads, child: const Text('Clear')),
      ]),
      if (prog.isEmpty)
        Text('Select a receiver and tap "Add to read order". With no order set, '
            'the QB reads routes left to right.',
            style: theme.textTheme.bodySmall),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: true,
        onReorderItem: c.reorderReads,
        children: [
          for (var i = 0; i < prog.length; i++)
            ListTile(
              key: ValueKey(prog[i]),
              dense: true,
              leading: CircleAvatar(
                  radius: 13,
                  backgroundColor: FieldColors.firstDown,
                  child: Text('${i + 1}',
                      style: const TextStyle(color: Colors.black, fontSize: 12))),
              title: Text(_label(prog[i])),
              onTap: () => c.select(prog[i]),
            ),
        ],
      ),
    ]);
  }

  String _label(String id) {
    final p = c.play.playerOrNull(id);
    final a = c.play.assignments[id];
    final route = a is RouteAssignment ? (a.name ?? 'Custom') : '';
    return '${p?.label ?? id} — $route';
  }
}
