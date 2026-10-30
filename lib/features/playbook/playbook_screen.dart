import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/field/play_painter.dart';
import '../../data/providers.dart';
import '../../models/formations.dart';
import '../../models/play.dart';
import '../../models/starter_plays.dart';
import '../designer/designer_screen.dart';
import '../simulator/simulator_screen.dart';

class PlaybookScreen extends ConsumerStatefulWidget {
  const PlaybookScreen({super.key});

  @override
  ConsumerState<PlaybookScreen> createState() => _PlaybookScreenState();
}

class _PlaybookScreenState extends ConsumerState<PlaybookScreen> {
  String _query = '';
  PlayType? _filter;

  void _open(Play p) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => DesignerScreen(play: p)));

  Future<void> _newPlay() async {
    final formation = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Start from a formation'),
        children: [
          for (final f in Formations.names)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, f), child: Text(f)),
        ],
      ),
    );
    if (formation == null) return;
    _open(StarterPlays.blank(formation));
  }

  Future<void> _delete(Play p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ref.read(playRepositoryProvider).delete(p.id);
  }

  Future<void> _duplicate(Play p) => ref.read(playRepositoryProvider).save(p.copyWith(
        id: 'play_${DateTime.now().microsecondsSinceEpoch}',
        name: '${p.name} (copy)',
        updatedAt: DateTime.now(),
      ));

  @override
  Widget build(BuildContext context) {
    final plays = ref.watch(playsProvider);
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playbook'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Chip(
              avatar: Icon(session is UserSession ? Icons.cloud_done : Icons.phone_android, size: 18),
              label: Text(switch (session) {
                UserSession(:final email) => email ?? 'Signed in',
                _ => 'On this device',
              }),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'out') {
                if (session is UserSession) await FirebaseAuth.instance.signOut();
                ref.read(guestModeProvider.notifier).set(false);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newPlay,
        icon: const Icon(Icons.add),
        label: const Text('New play'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search plays',
                    border: OutlineInputBorder(),
                    isDense: true),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const SizedBox(width: 12),
            SegmentedButton<PlayType?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(value: PlayType.pass, label: Text('Pass')),
                ButtonSegment(value: PlayType.run, label: Text('Run')),
                ButtonSegment(value: PlayType.playAction, label: Text('PA')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ]),
        ),
        Expanded(
          child: plays.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Couldn\'t load plays: $e')),
            data: (all) {
              final list = all
                  .where((p) =>
                      (_filter == null || p.playType == _filter) &&
                      (_query.isEmpty ||
                          p.name.toLowerCase().contains(_query) ||
                          p.formation.toLowerCase().contains(_query)))
                  .toList();
              if (list.isEmpty) {
                return Center(
                    child: Text('No plays yet. Tap "New play" to draw one up.',
                        style: theme.textTheme.bodyLarge));
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300, childAspectRatio: 0.82, mainAxisSpacing: 12, crossAxisSpacing: 12),
                itemCount: list.length,
                itemBuilder: (_, i) => _PlayCard(
                  play: list[i],
                  onOpen: () => _open(list[i]),
                  onSimulate: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SimulatorScreen(play: list[i]))),
                  onDuplicate: () => _duplicate(list[i]),
                  onDelete: () => _delete(list[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _PlayCard extends StatelessWidget {
  final Play play;
  final VoidCallback onOpen, onSimulate, onDuplicate, onDelete;
  const _PlayCard({
    required this.play,
    required this.onOpen,
    required this.onSimulate,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: CustomPaint(
              painter: PlayDiagramPainter(play: play, compact: true, yTop: 24, yBottom: -9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(play.name,
                      style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${play.formation} · ${switch (play.playType) {
                    PlayType.pass => 'Pass',
                    PlayType.run => 'Run',
                    PlayType.playAction => 'Play-action',
                  }}',
                      style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              IconButton(tooltip: 'Simulate', onPressed: onSimulate, icon: const Icon(Icons.play_circle)),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'dup' ? onDuplicate() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                  PopupMenuItem(value: 'del', child: Text('Delete')),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
