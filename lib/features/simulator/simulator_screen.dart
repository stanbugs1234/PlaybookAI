import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/coach_ai.dart';
import '../../explain/explainer.dart';
import '../../models/defense.dart';
import '../../models/play.dart';
import '../../models/vec.dart';
import '../../sim/coverage_matrix.dart';
import '../../sim/defense_factory.dart';
import '../../sim/sim_engine.dart';
import '../../sim/sim_types.dart';
import 'sim_painter.dart';

class SimulatorScreen extends StatefulWidget {
  final Play play;
  final DefenseCall initialCall;
  const SimulatorScreen({
    super.key,
    required this.play,
    this.initialCall = const DefenseCall(Front.nickel, Coverage.cover3),
  });

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen>
    with SingleTickerProviderStateMixin {
  late DefenseCall call = widget.initialCall;
  late List<Defender> defenders = DefenseFactory.build(widget.play, call);
  bool customAlignment = false;
  SimResult? result;
  Explanation? explanation;
  int seed = 1;

  double t = 0;
  double speed = 1;
  bool playing = false;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  bool showZones = true;
  bool showTrails = true;
  bool showEyes = true;
  int? pinnedStep;
  String? draggingDefender;

  String? aiText;
  bool aiLoading = false;
  String? aiError;

  Play get play => widget.play;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final r = result;
    if (r == null) return;
    setState(() {
      t += dt * speed;
      if (t >= r.duration) {
        t = r.duration;
        _pause();
      }
    });
  }

  void _play() {
    if (result == null) _simulate();
    if (t >= result!.duration) t = 0;
    pinnedStep = null;
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    setState(() => playing = true);
  }

  void _pause() {
    if (_ticker.isActive) _ticker.stop();
    playing = false;
  }

  void _simulate() {
    final r = SimEngine.run(play, call, seed: seed, defenders: defenders);
    result = r;
    explanation = Explainer.explain(r);
    aiText = null;
    aiError = null;
    t = 0;
  }

  void _newRep() {
    setState(() {
      seed++;
      _pause();
      _simulate();
    });
    _play();
  }

  void _setCall(DefenseCall next) {
    setState(() {
      _pause();
      call = next;
      defenders = DefenseFactory.build(play, call);
      customAlignment = false;
      result = null;
      explanation = null;
      t = 0;
    });
  }

  void _resetToPreSnap() {
    setState(() {
      _pause();
      result = null;
      explanation = null;
      t = 0;
    });
  }

  int? get _activeStep {
    if (pinnedStep != null) return pinnedStep;
    final e = explanation;
    if (e == null) return null;
    int? idx;
    for (var i = 0; i < e.steps.length; i++) {
      if (e.steps[i].t <= t + 1e-6) idx = i;
    }
    return idx;
  }

  void _seekStep(int i) {
    final s = explanation!.steps[i];
    setState(() {
      _pause();
      t = s.t;
      pinnedStep = i;
    });
  }

  Future<void> _askAi() async {
    final r = result, e = explanation;
    if (r == null || e == null) return;
    setState(() {
      aiLoading = true;
      aiError = null;
    });
    try {
      final text = await CoachAi.explain(r, e);
      if (mounted) setState(() => aiText = text);
    } catch (err) {
      if (mounted) setState(() => aiError = '$err');
    } finally {
      if (mounted) setState(() => aiLoading = false);
    }
  }

  Future<void> _showMatrix() async {
    _pause();
    final chosen = await showDialog<Coverage>(
      context: context,
      builder: (_) => _MatrixDialog(play: play, front: call.front, blitz: call.blitz),
    );
    if (chosen != null) _setCall(call.copyWith(coverage: chosen));
  }

  // ---- Defender dragging (pre-snap only) ---------------------------------
  String? _hitDefender(Vec v) {
    String? best;
    var bd = 1.8;
    for (final d in defenders) {
      final dist = d.pos.distanceTo(v);
      if (dist < bd) {
        bd = dist;
        best = d.id;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${play.name} vs ${call.coverage.label}'),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 600)
            TextButton.icon(
              onPressed: _showMatrix,
              icon: const Icon(Icons.grid_view),
              label: const Text('Test vs all coverages'),
            )
          else
            IconButton(
              tooltip: 'Test vs all coverages',
              onPressed: _showMatrix,
              icon: const Icon(Icons.grid_view),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 950;
        final field = _buildField();
        final panel = _buildPanel();
        if (wide) {
          return Row(children: [
            Expanded(child: field),
            SizedBox(width: 400, child: panel),
          ]);
        }
        return Column(children: [
          Expanded(flex: 3, child: field),
          Expanded(flex: 2, child: panel),
        ]);
      }),
    );
  }

  Widget _buildField() {
    final step = _activeStep == null ? null : explanation!.steps[_activeStep!];
    return Container(
      color: const Color(0xFF1B3A1E),
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(builder: (context, box) {
              final tf = SimPainter.transform(box.biggest);
              return GestureDetector(
                onPanStart: result != null
                    ? null
                    : (d) {
                        final id = _hitDefender(tf.toField(d.localPosition));
                        if (id != null) setState(() => draggingDefender = id);
                      },
                onPanUpdate: result != null
                    ? null
                    : (d) {
                        final id = draggingDefender;
                        if (id == null) return;
                        final v = tf.toField(d.localPosition);
                        setState(() {
                          customAlignment = true;
                          defenders = [
                            for (final x in defenders)
                              x.id == id
                                  ? x.copyWith(
                                      pos: Vec(v.x.clamp(0.5, Field.width - 0.5),
                                          v.y.clamp(0.5, 25.0)))
                                  : x,
                          ];
                        });
                      },
                onPanEnd: (_) => setState(() => draggingDefender = null),
                child: CustomPaint(
                  size: box.biggest,
                  painter: SimPainter(
                    play: play,
                    defenders: defenders,
                    result: result,
                    t: t,
                    showZones: showZones && (result == null || t < 0.3),
                    showTrails: showTrails,
                    showEyes: showEyes,
                    focusId: step?.focusId,
                    focusDefenderId: step?.defenderId,
                    focusGood: step?.good,
                    dragging: draggingDefender,
                  ),
                ),
              );
            }),
          ),
        ),
        _controls(),
      ]),
    );
  }

  Widget _controls() {
    final r = result;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          IconButton.filled(
            tooltip: playing ? 'Pause' : 'Run play',
            onPressed: playing ? () => setState(_pause) : _play,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'New rep (different seed)',
            onPressed: _newRep,
            icon: const Icon(Icons.casino_outlined),
          ),
          IconButton(
            tooltip: 'Back to pre-snap',
            onPressed: r == null ? null : _resetToPreSnap,
            icon: const Icon(Icons.restart_alt),
          ),
          Expanded(
            child: r == null
                ? Text(
                    customAlignment
                        ? 'Custom alignment. Press play to run.'
                        : 'Pre-snap: drag defenders to adjust, then press play.',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center)
                : Slider(
                    value: t.clamp(0, r.duration),
                    max: r.duration,
                    onChanged: (v) => setState(() {
                      _pause();
                      pinnedStep = null;
                      t = v;
                    }),
                  ),
          ),
          if (r != null)
            SizedBox(
                width: 44,
                child: Text('${t.toStringAsFixed(1)}s', style: theme.textTheme.labelMedium)),
          PopupMenuButton<double>(
            tooltip: 'Speed',
            initialValue: speed,
            onSelected: (v) => setState(() => speed = v),
            itemBuilder: (_) => [
              for (final s in [0.25, 0.5, 1.0, 2.0])
                PopupMenuItem(value: s, child: Text('${s}x')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${speed}x', style: theme.textTheme.labelLarge),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 700) ...[
            _toggle(Icons.blur_on, 'Zones', showZones, (v) => showZones = v),
            _toggle(Icons.timeline, 'Trails', showTrails, (v) => showTrails = v),
            _toggle(Icons.visibility, 'QB eyes', showEyes, (v) => showEyes = v),
          ] else
            PopupMenuButton<int>(
              tooltip: 'Overlays',
              icon: const Icon(Icons.layers),
              onSelected: (i) => setState(() {
                if (i == 0) showZones = !showZones;
                if (i == 1) showTrails = !showTrails;
                if (i == 2) showEyes = !showEyes;
              }),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(value: 0, checked: showZones, child: const Text('Zones')),
                CheckedPopupMenuItem(value: 1, checked: showTrails, child: const Text('Trails')),
                CheckedPopupMenuItem(value: 2, checked: showEyes, child: const Text('QB eyes')),
              ],
            ),
        ]),
      ),
    );
  }

  Widget _toggle(IconData icon, String tip, bool value, void Function(bool) set) =>
      IconButton(
        tooltip: tip,
        isSelected: value,
        onPressed: () => setState(() => set(!value)),
        icon: Icon(icon),
      );

  Widget _buildPanel() {
    final theme = Theme.of(context);
    final e = explanation;
    final r = result;
    final active = _activeStep;
    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _defensePicker(),
          const Divider(height: 28),
          if (r == null || e == null) ...[
            Text('Pre-snap read', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(call.coverage.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _play,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run the play'),
            ),
          ] else ...[
            _OutcomeBanner(outcome: r.outcome, seed: seed),
            const SizedBox(height: 12),
            Text('Pre-snap read', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(e.shell, style: theme.textTheme.bodyMedium),
            for (final s in e.preSnap)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $s', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 16),
            Text('Progression', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (var i = 0; i < e.steps.length; i++)
              if (e.steps[i].kind != StepKind.preSnap)
                _StepTile(
                  step: e.steps[i],
                  active: i == active,
                  onTap: () => _seekStep(i),
                ),
            const SizedBox(height: 16),
            Text('Why', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(e.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text('Coaching tips', style: theme.textTheme.titleSmall),
            for (final tip in e.tips)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $tip', style: theme.textTheme.bodySmall),
              ),
            const Divider(height: 28),
            _coachAi(),
          ],
        ],
      ),
    );
  }

  Widget _defensePicker() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Defense', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<Front>(
            initialValue: call.front,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Front', border: OutlineInputBorder()),
            items: [for (final f in Front.values) DropdownMenuItem(value: f, child: Text(f.label))],
            onChanged: (v) => v == null ? null : _setCall(call.copyWith(front: v)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<Blitz>(
            initialValue: call.blitz,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pressure', border: OutlineInputBorder()),
            items: [for (final b in Blitz.values) DropdownMenuItem(value: b, child: Text(b.label))],
            onChanged: (v) => v == null ? null : _setCall(call.copyWith(blitz: v)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in Coverage.values)
          ChoiceChip(
            label: Text(c.label),
            selected: call.coverage == c,
            onSelected: (_) => _setCall(call.copyWith(coverage: c)),
          ),
      ]),
    ]);
  }

  Widget _coachAi() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Coach AI breakdown', style: theme.textTheme.titleSmall)),
        FilledButton.tonalIcon(
          onPressed: aiLoading || !CoachAi.available ? null : _askAi,
          icon: aiLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.auto_awesome),
          label: const Text('Ask'),
        ),
      ]),
      if (!CoachAi.available)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Connect Firebase and deploy the explainPlay function to get AI breakdowns from Claude.',
              style: theme.textTheme.bodySmall),
        ),
      if (aiError != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(aiError!, style: TextStyle(color: theme.colorScheme.error)),
        ),
      if (aiText != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText(aiText!, style: theme.textTheme.bodyMedium),
        ),
    ]);
  }
}

class _OutcomeBanner extends StatelessWidget {
  final SimOutcome outcome;
  final int seed;
  const _OutcomeBanner({required this.outcome, required this.seed});

  @override
  Widget build(BuildContext context) {
    final good = outcome.isSuccess;
    final color = good ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(good ? Icons.check_circle : Icons.cancel, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(outcome.label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
        ),
        if (outcome.timeToThrow != null)
          Text('${outcome.timeToThrow!.toStringAsFixed(2)}s to throw',
              style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 8),
        Text('rep #$seed', style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

class _StepTile extends StatelessWidget {
  final ExplanationStep step;
  final bool active;
  final VoidCallback onTap;
  const _StepTile({required this.step, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (step.good) {
      true => const Color(0xFF2E7D32),
      false => const Color(0xFFC62828),
      null => theme.colorScheme.primary,
    };
    final icon = switch (step.kind) {
      StepKind.read => Icons.visibility,
      StepKind.covered => Icons.block,
      StepKind.decision => Icons.sports_football,
      StepKind.pressure => Icons.warning_amber,
      StepKind.result => step.good == true ? Icons.flag : Icons.close,
      StepKind.run => Icons.directions_run,
      StepKind.preSnap => Icons.info_outline,
    };
    return Card(
      elevation: 0,
      color: active ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(step.title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(step.detail, style: theme.textTheme.bodySmall),
              ]),
            ),
            Text('${step.t.toStringAsFixed(1)}s', style: theme.textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}

class _MatrixDialog extends StatefulWidget {
  final Play play;
  final Front front;
  final Blitz blitz;
  const _MatrixDialog({required this.play, required this.front, required this.blitz});

  @override
  State<_MatrixDialog> createState() => _MatrixDialogState();
}

class _MatrixDialogState extends State<_MatrixDialog> {
  List<MatrixRow>? rows;

  @override
  void initState() {
    super.initState();
    // Let the dialog paint its spinner before the (synchronous) batch runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        final r = CoverageMatrix.run(widget.play,
            front: widget.front, blitz: widget.blitz, runs: 25);
        if (mounted) setState(() => rows = r);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRun = widget.play.playType == PlayType.run;
    return AlertDialog(
      title: Text('${widget.play.name}: 25 reps vs each coverage'),
      content: SizedBox(
        width: 720,
        child: rows == null
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: [
                    const DataColumn(label: Text('Coverage')),
                    const DataColumn(label: Text('Avg yds'), numeric: true),
                    const DataColumn(label: Text('Success'), numeric: true),
                    if (!isRun) const DataColumn(label: Text('Comp %'), numeric: true),
                    if (!isRun) const DataColumn(label: Text('Read 1'), numeric: true),
                    if (!isRun) const DataColumn(label: Text('INT'), numeric: true),
                    if (!isRun) const DataColumn(label: Text('Sack'), numeric: true),
                    const DataColumn(label: Text('Top target')),
                  ],
                  rows: [
                    for (final r in rows!)
                      DataRow(
                        onSelectChanged: (_) => Navigator.pop(context, r.call.coverage),
                        color: WidgetStatePropertyAll(_grade(r).withValues(alpha: 0.12)),
                        cells: [
                          DataCell(Text(r.call.coverage.label, style: theme.textTheme.labelLarge)),
                          DataCell(Text(r.avgYards.toStringAsFixed(1))),
                          DataCell(Text('${r.successPct.round()}%')),
                          if (!isRun) DataCell(Text('${r.completionPct.round()}%')),
                          if (!isRun) DataCell(Text('${r.firstReadOpenPct.round()}%')),
                          if (!isRun) DataCell(Text('${r.turnoverPct.round()}%')),
                          if (!isRun) DataCell(Text('${r.sackPct.round()}%')),
                          DataCell(Text(r.topTarget == null
                              ? '—'
                              : widget.play.playerOrNull(r.topTarget!)?.label ?? r.topTarget!)),
                        ],
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        Text('Tap a row to run against it', style: theme.textTheme.bodySmall),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Color _grade(MatrixRow r) => r.successPct >= 55
      ? Colors.green
      : r.successPct >= 35
          ? Colors.amber
          : Colors.red;
}
