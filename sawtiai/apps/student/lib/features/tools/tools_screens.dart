import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../logic/achievements.dart';
import '../common/shared.dart';
import '../shell/shell.dart';

Future<void> logStudy(Repository repo, int minutes, String source) async {
  if (minutes <= 0) return;
  await repo.save('study_logs', {'log_date': isoDate(repo.now()), 'minutes': minutes.clamp(1, 1440), 'source': source});
}

String _clock(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Pomodoro
// ---------------------------------------------------------------------------
class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen> {
  int _focus = 25, _break = 5;
  bool _isBreak = false, _running = false;
  late int _left = _focus * 60;
  Timer? _t;

  void _toggle() {
    if (_running) {
      _t?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted) return;
    setState(() => _left--);
    if (_left > 0) return;
    _t?.cancel();
    final l = context.l10n;
    final notif = ref.read(notificationsProvider);
    if (!_isBreak) {
      await logStudy(ref.read(repositoryProvider), _focus, 'pomodoro');
      await notif.showNow(l.pomodoro, l.pomodoroDone);
    } else {
      await notif.showNow(l.pomodoro, l.breakDone);
    }
    if (!mounted) return;
    setState(() {
      _isBreak = !_isBreak;
      _left = (_isBreak ? _break : _focus) * 60;
      _running = false;
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final total = (_isBreak ? _break : _focus) * 60;
    return EnjazPage(
      title: l.pomodoro,
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1 - _left / total,
                  strokeWidth: 12,
                  color: _isBreak ? EnjazColors.success : EnjazColors.danger,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_clock(_left), key: const Key('pomodoro_clock'), style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900)),
                Text(_isBreak ? l.breakTime : l.focusTime, style: TextStyle(color: context.mutedText)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: GlowButton(
              key: const Key('pomodoro_toggle'),
              label: _running ? l.pause : (_left == total ? l.start : l.resume),
              gradient: _running ? EnjazColors.planGradient : EnjazColors.studyGradient,
              icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onPressed: _toggle,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: l.reset,
            onPressed: () {
              _t?.cancel();
              setState(() {
                _running = false;
                _left = (_isBreak ? _break : _focus) * 60;
              });
            },
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ]),
        const SizedBox(height: 24),
        if (!_running) ...[
          Text('${l.focusTime}: $_focus'),
          Slider(value: _focus.toDouble(), min: 5, max: 90, divisions: 17, onChanged: (v) => setState(() {
            _focus = v.round();
            if (!_isBreak) _left = _focus * 60;
          })),
          Text('${l.breakTime}: $_break'),
          Slider(value: _break.toDouble(), min: 1, max: 30, divisions: 29, onChanged: (v) => setState(() {
            _break = v.round();
            if (_isBreak) _left = _break * 60;
          })),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Stopwatch
// ---------------------------------------------------------------------------
class StopwatchScreen extends ConsumerStatefulWidget {
  const StopwatchScreen({super.key});

  @override
  ConsumerState<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _StopwatchScreenState extends ConsumerState<StopwatchScreen> {
  final _sw = Stopwatch();
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = _sw.elapsed.inSeconds;
    return EnjazPage(
      title: l.stopwatch,
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 40),
        Center(
          child: Text('${(s ~/ 3600).toString().padLeft(2, '0')}:${_clock(s % 3600)}',
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 40),
        Row(children: [
          Expanded(
            child: GlowButton(
              label: _sw.isRunning ? l.pause : (s == 0 ? l.start : l.resume),
              gradient: _sw.isRunning ? EnjazColors.planGradient : EnjazColors.studyGradient,
              onPressed: () => setState(() {
                if (_sw.isRunning) {
                  _sw.stop();
                  _t?.cancel();
                } else {
                  _sw.start();
                  _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
                }
              }),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: l.reset,
            onPressed: () => setState(() {
              _sw..stop()..reset();
              _t?.cancel();
            }),
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ]),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: s < 60
              ? null
              : () async {
                  final m = s ~/ 60;
                  await logStudy(ref.read(repositoryProvider), m, 'timer');
                  setState(() {
                    _sw..stop()..reset();
                    _t?.cancel();
                  });
                  if (context.mounted) showEnjazSnack(context, l.studyTimeSaved(m));
                },
          icon: const Icon(Icons.save_rounded),
          label: Text(l.saveStudyTime),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Grade (average) calculator
// ---------------------------------------------------------------------------
class GradeCalculatorScreen extends StatefulWidget {
  const GradeCalculatorScreen({super.key});

  @override
  State<GradeCalculatorScreen> createState() => _GradeCalculatorScreenState();
}

class _GradeCalculatorScreenState extends State<GradeCalculatorScreen> {
  final _rows = <(TextEditingController, TextEditingController)>[];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 6; i++) {
      _add();
    }
  }

  void _add() => _rows.add((TextEditingController(), TextEditingController(text: '100')));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    double sum = 0, max = 0;
    for (final (s, m) in _rows) {
      final a = double.tryParse(s.text), b = double.tryParse(m.text);
      if (a != null && b != null && b > 0) {
        sum += a;
        max += b;
      }
    }
    final avg = max == 0 ? null : sum * 100 / max;
    return EnjazPage(
      title: l.gradeCalculator,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GlassCard(
          blur: true,
          child: Column(children: [
            Text(l.average, style: TextStyle(color: context.mutedText)),
            Text(avg == null ? '—' : avg.toStringAsFixed(2), key: const Key('average_value'),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: EnjazColors.success)),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('${i + 1}', style: TextStyle(color: context.mutedText)),
              const SizedBox(width: 10),
              Expanded(child: TextField(key: Key('grade_$i'), controller: _rows[i].$1, keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.score), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _rows[i].$2, keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l.maxScore), onChanged: (_) => setState(() {}))),
            ]),
          ),
        TextButton.icon(onPressed: () => setState(_add), icon: const Icon(Icons.add_rounded), label: Text(l.addRow)),
      ]),
    );
  }
}

class PercentageCalculatorScreen extends StatefulWidget {
  const PercentageCalculatorScreen({super.key});

  @override
  State<PercentageCalculatorScreen> createState() => _PercentageCalculatorScreenState();
}

class _PercentageCalculatorScreenState extends State<PercentageCalculatorScreen> {
  final _v = TextEditingController(), _t = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final v = double.tryParse(_v.text), t = double.tryParse(_t.text);
    final pct = (v != null && t != null && t != 0) ? v * 100 / t : null;
    return EnjazPage(
      title: l.percentageCalculator,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(key: const Key('pct_value'), controller: _v, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.value), onChanged: (_) => setState(() {})),
        const SizedBox(height: 12),
        TextField(key: const Key('pct_total'), controller: _t, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.total), onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        GlassCard(
          blur: true,
          child: Column(children: [
            Text(l.percentage, style: TextStyle(color: context.mutedText)),
            Text(pct == null ? '—' : '${pct.toStringAsFixed(2)}%', key: const Key('pct_result'),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: EnjazColors.cyan)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final stats = ref.watch(statsProvider);
    final open = [...stats.overdueTasks, ...stats.upcomingTasks];
    final done = repo.tasks.where((t) => t.isDone).toList()..sort((a, b) => (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)));
    return EnjazPage(
      title: l.tasks,
      fab: FloatingActionButton(
        heroTag: null,
        backgroundColor: EnjazColors.violet,
        foregroundColor: Colors.white,
        tooltip: l.addTask,
        onPressed: () => showTaskSheet(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        if (open.isEmpty) EmptyState(icon: Icons.task_alt_rounded, message: l.noTasks),
        for (final t in open) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskTile(task: t)),
        if (done.isNotEmpty)
          TextButton(onPressed: () => setState(() => _showDone = !_showDone), child: Text('${l.completed} (${done.length})')),
        if (_showDone) for (final t in done.take(50)) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskTile(task: t)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Notes
// ---------------------------------------------------------------------------
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Note? note]) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final title = TextEditingController(text: note?.title);
    final body = TextEditingController(text: note?.body);
    var pinned = note?.pinned ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(key: const Key('note_title'), controller: title, decoration: InputDecoration(labelText: l.noteTitle)),
            const SizedBox(height: 10),
            TextField(key: const Key('note_body'), controller: body, minLines: 5, maxLines: 12, decoration: InputDecoration(hintText: l.noteBody)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, value: pinned, title: const Icon(Icons.push_pin_rounded), onChanged: (v) => setS(() => pinned = v ?? false)),
            Row(children: [
              if (note != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: EnjazColors.danger),
                  onPressed: () async {
                    await repo.remove('student_notes', note.id);
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
              Expanded(
                child: GlowButton(
                  key: const Key('save_note'),
                  label: l.save,
                  gradient: EnjazColors.planGradient,
                  onPressed: () async {
                    if (title.text.trim().isEmpty && body.text.trim().isEmpty) return;
                    await repo.save('student_notes', {...?note?.m, 'title': title.text.trim(), 'body': body.text, 'is_pinned': pinned});
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final notes = ref.watch(repositoryProvider).notes;
    return EnjazPage(
      title: l.myNotes,
      fab: FloatingActionButton(
        heroTag: null,
        key: const Key('add_note'),
        backgroundColor: EnjazColors.violet,
        foregroundColor: Colors.white,
        tooltip: l.addNote,
        onPressed: () => _edit(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: notes.isEmpty
          ? EmptyState(icon: Icons.sticky_note_2_outlined, message: l.noNotes)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    onTap: () => _edit(context, ref, n),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(n.title?.isNotEmpty ?? false ? n.title! : l.myNotes, style: const TextStyle(fontWeight: FontWeight.w800))),
                        if (n.pinned) const Icon(Icons.push_pin_rounded, size: 16, color: EnjazColors.warning),
                      ]),
                      const SizedBox(height: 4),
                      Text(n.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.mutedText, height: 1.5)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Expenses
// ---------------------------------------------------------------------------
class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final now = repo.now();
    final month = repo.expenses.where((e) => e.spentOn.year == now.year && e.spentOn.month == now.month);
    final total = month.fold<double>(0, (a, e) => a + e.amount);
    return EnjazPage(
      title: l.expenses,
      fab: FloatingActionButton(
        heroTag: null,
        backgroundColor: EnjazColors.violet,
        foregroundColor: Colors.white,
        tooltip: l.addExpense,
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        GlassCard(
          blur: true,
          child: Row(children: [
            Expanded(child: Text(l.monthTotal, style: TextStyle(color: context.mutedText))),
            Text('${total.toStringAsFixed(0)} ${l.currencyIqd}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ]),
        ),
        const SizedBox(height: 12),
        for (final e in repo.expenses.take(100))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(formatDay(l, e.spentOn), style: TextStyle(fontSize: 12, color: context.mutedText)),
                  ]),
                ),
                Text('${e.amount.toStringAsFixed(0)} ${l.currencyIqd}'),
                IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), tooltip: l.delete, onPressed: () => repo.remove('student_expenses', e.id)),
              ]),
            ),
          ),
      ]),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final title = TextEditingController();
    final amount = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.addExpense, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: InputDecoration(labelText: l.taskTitle)),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.amount)),
          const SizedBox(height: 16),
          GlowButton(
            label: l.save,
            gradient: EnjazColors.planGradient,
            onPressed: () async {
              final a = double.tryParse(amount.text);
              if (title.text.trim().isEmpty || a == null || a < 0) return;
              await repo.save('student_expenses', {'title': title.text.trim(), 'amount_iqd': a.round(), 'category': 'other', 'spent_on': isoDate(repo.now())});
              if (c.mounted) Navigator.pop(c);
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final now = dayOnly(repo.now());
    final active = repo.goals.where((g) => !g.endsOn.isBefore(now)).toList();
    Widget section(String title, String period) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(title: title, action: l.addGoal, onAction: () => _add(context, ref, period)),
          for (final g in active.where((g) => g.period == period))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    IconButton(
                      tooltip: l.progressValue,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      onPressed: () => repo.save('student_goals', {...g.m, 'current_value': g.current + 1}),
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), tooltip: l.delete, onPressed: () => repo.remove('student_goals', g.id)),
                  ]),
                  EnjazProgressBar(value: g.ratio, height: 18),
                  const SizedBox(height: 4),
                  Text('${g.current.toStringAsFixed(0)} / ${g.target.toStringAsFixed(0)} • ${formatDay(l, g.endsOn, withWeekday: false)}',
                      style: TextStyle(fontSize: 12, color: context.mutedText)),
                ]),
              ),
            ),
        ]);
    return EnjazPage(
      title: l.goals,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        section(l.weeklyGoals, 'weekly'),
        section(l.monthlyGoals, 'monthly'),
      ]),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String period) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final title = TextEditingController();
    final target = TextEditingController(text: '5');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.addGoal, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: InputDecoration(labelText: l.goalTitle)),
          const SizedBox(height: 10),
          TextField(controller: target, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.targetValue)),
          const SizedBox(height: 16),
          GlowButton(
            label: l.save,
            gradient: EnjazColors.planGradient,
            onPressed: () async {
              final t = double.tryParse(target.text);
              if (title.text.trim().isEmpty || t == null || t <= 0) return;
              final start = dayOnly(repo.now());
              final end = period == 'weekly'
                  ? start.add(Duration(days: 7 - start.weekday))
                  : DateTime(start.year, start.month + 1, 0);
              await repo.save('student_goals', {
                'period': period, 'title': title.text.trim(), 'target_value': t, 'current_value': 0, 'unit': 'count',
                'starts_on': isoDate(start), 'ends_on': isoDate(end),
              });
              if (c.mounted) Navigator.pop(c);
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Achievements & statistics
// ---------------------------------------------------------------------------
class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final owned = ref.watch(repositoryProvider).achievementCodes;
    return EnjazPage(
      title: l.myAchievements,
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        children: [
          for (final r in achievementRules)
            GlassCard(
              radius: EnjazRadii.tile,
              padding: const EdgeInsets.all(10),
              gradient: owned.contains(r.code) ? EnjazColors.planGradient : null,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(owned.contains(r.code) ? Icons.emoji_events_rounded : Icons.lock_outline_rounded,
                    size: 32, color: owned.contains(r.code) ? Colors.amberAccent : context.mutedText),
                const SizedBox(height: 6),
                Text(achievementName(l, r.code), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (!owned.contains(r.code)) Text(l.achievementLocked, style: TextStyle(fontSize: 10, color: context.mutedText)),
              ]),
            ),
        ],
      ),
    );
  }
}

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final stats = ref.watch(statsProvider);
    final attempts = repo.attempts;
    final avg = attempts.isEmpty ? null : attempts.fold<double>(0, (a, x) => a + (x.scorePercent ?? 0)) / attempts.length;
    final days = weekdayNames(l);
    final labels = [for (var i = 6; i >= 0; i--) days[repo.now().subtract(Duration(days: i)).weekday - 1].substring(0, 3)];
    final bySubject = <String, int>{};
    for (final g in repo.studyLogs.where((g) => g.subjectId != null)) {
      bySubject[g.subjectId!] = (bySubject[g.subjectId!] ?? 0) + g.minutes;
    }
    Widget tile(IconData i, Color c, String v, String label) => Expanded(child: StatTile(icon: i, iconColor: c, value: v, label: label));
    return EnjazPage(
      title: l.statistics,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          tile(Icons.schedule_rounded, EnjazColors.cyan, formatMinutes(l, stats.totalMinutes), l.totalStudyHours),
          const SizedBox(width: 10),
          tile(Icons.task_alt_rounded, EnjazColors.success, '${stats.completedTasks}', l.tasksCompleted),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile(Icons.quiz_rounded, EnjazColors.violet, '${attempts.length}', l.testsTaken),
          const SizedBox(width: 10),
          tile(Icons.grade_rounded, EnjazColors.warning, avg == null ? '—' : '${avg.round()}%', l.avgScore),
          const SizedBox(width: 10),
          tile(Icons.local_fire_department_rounded, EnjazColors.streak, '${stats.streak}', l.streakDays),
        ]),
        SectionHeader(title: l.weeklyPerformance),
        GlassCard(child: WeeklyBars(minutes: stats.last7DaysMinutes, labels: labels)),
        if (bySubject.isNotEmpty) ...[
          SectionHeader(title: l.subjectsCount),
          for (final e in (bySubject.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 110, child: Text(repo.subject(e.key)?.nameAr ?? '', overflow: TextOverflow.ellipsis)),
                Expanded(child: EnjazProgressBar(value: e.value / bySubject.values.reduce((a, b) => a > b ? a : b), height: 12, showLabel: false)),
                const SizedBox(width: 8),
                Text(formatMinutes(l, e.value), style: TextStyle(fontSize: 12, color: context.mutedText)),
              ]),
            ),
        ],
      ]),
    );
  }
}
