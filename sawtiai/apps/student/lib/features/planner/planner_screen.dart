import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../logic/planner.dart';

class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late double _hours = ((ref.read(repositoryProvider).preferences['daily_study_hours'] as num?) ?? 3).toDouble();
  int _days = 7;
  final Map<String, double> _priority = {};
  List<PlannedTask>? _preview;

  List<PlannedTask> _build() {
    final repo = ref.read(repositoryProvider);
    final prog = repo.topicProgress;
    final planned = <DateTime, int>{};
    for (final t in repo.tasks.where((t) => !t.isDone && t.dueDate != null)) {
      final d = dayOnly(t.dueDate!);
      planned[d] = (planned[d] ?? 0) + (t.estimatedMinutes ?? 0);
    }
    final alreadyPlannedTopics = repo.tasks.where((t) => !t.isDone && t.topicId != null).map((t) => t.topicId).toSet();
    final topics = <PlannerTopic>[];
    for (final s in repo.mySubjects) {
      for (final t in repo.topicsOfSubject(s.id)) {
        if (alreadyPlannedTopics.contains(t.id)) continue;
        topics.add(PlannerTopic(
          topicId: t.id,
          subjectId: s.id,
          title: '${s.nameAr}: ${t.title}',
          difficulty: t.difficulty,
          status: prog[t.id]?.status ?? TopicStatus.notStarted,
          isDifficult: prog[t.id]?.isDifficult ?? false,
          subjectPriority: _priority[s.id] ?? 1,
        ));
      }
    }
    final exams = <String, DateTime>{};
    for (final e in repo.exams.where((e) => e.subjectId != null && e.examAt.isAfter(repo.now()))) {
      exams.putIfAbsent(e.subjectId!, () => e.examAt);
    }
    return StudyPlanner(today: repo.now()).generate(
      topics: topics,
      nextExamBySubject: exams,
      dailyMinutes: (_hours * 60).round(),
      days: _days,
      alreadyPlanned: planned,
    );
  }

  Future<void> _apply(List<PlannedTask> plan) async {
    final repo = ref.read(repositoryProvider);
    for (final p in plan) {
      await repo.save('study_tasks', {
        'title': p.title,
        'subject_id': p.subjectId,
        'topic_id': p.topicId,
        'due_date': isoDate(p.date),
        'estimated_minutes': p.minutes,
        'priority': p.isRevision ? 3 : 2,
        'is_done': false,
        'source': 'planner',
      });
    }
    await repo.setPreference('daily_study_hours', _hours);
    if (mounted) {
      showEnjazSnack(context, context.l10n.planReady(plan.length));
      Navigator.of(context).pop();
    }
  }

  Future<void> _redistribute() async {
    final repo = ref.read(repositoryProvider);
    final stats = ref.read(statsProvider);
    final planned = <DateTime, int>{};
    for (final t in repo.tasks.where((t) => !t.isDone && t.dueDate != null && !stats.overdueTasks.contains(t))) {
      final d = dayOnly(t.dueDate!);
      planned[d] = (planned[d] ?? 0) + (t.estimatedMinutes ?? 0);
    }
    final moves = StudyPlanner(today: repo.now()).redistribute(
        overdue: stats.overdueTasks, plannedMinutesByDay: planned, dailyMinutes: (_hours * 60).round());
    for (final t in stats.overdueTasks) {
      final d = moves[t.id];
      if (d != null) await repo.save('study_tasks', {...t.m, 'due_date': isoDate(d)});
    }
    if (mounted) showEnjazSnack(context, context.l10n.redistributed);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final overdue = ref.watch(statsProvider).overdueTasks;
    return EnjazPage(
      title: l.planner,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        GlassCard(blur: true, child: Text(l.plannerIntro, style: const TextStyle(height: 1.7))),
        if (overdue.isNotEmpty) ...[
          const SizedBox(height: 12),
          GlassCard(
            gradient: LinearGradient(colors: [EnjazColors.warning.withValues(alpha: 0.3), EnjazColors.danger.withValues(alpha: 0.2)]),
            child: Row(children: [
              const Icon(Icons.history_rounded, color: EnjazColors.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(l.behindSchedule(overdue.length))),
              TextButton(key: const Key('redistribute'), onPressed: _redistribute, child: Text(l.redistribute)),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Text('${l.dailyHours}: ${_hours.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(value: _hours, min: 0.5, max: 10, divisions: 19, label: _hours.toStringAsFixed(1),
            onChanged: (v) => setState(() {
              _hours = v;
              _preview = null;
            })),
        Text(l.planDays, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [ButtonSegment(value: 3, label: Text('3')), ButtonSegment(value: 7, label: Text('7')),
            ButtonSegment(value: 14, label: Text('14')), ButtonSegment(value: 30, label: Text('30'))],
          selected: {_days},
          onSelectionChanged: (v) => setState(() {
            _days = v.first;
            _preview = null;
          }),
        ),
        if (repo.mySubjects.isNotEmpty) ...[
          SectionHeader(title: l.priority),
          for (final s in repo.mySubjects)
            Row(children: [
              Expanded(child: Text(s.nameAr)),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: [ButtonSegment(value: 0.6, label: Text(l.priorityLow)), ButtonSegment(value: 1, label: Text(l.priorityNormal)),
                  ButtonSegment(value: 1.6, label: Text(l.priorityHigh))],
                selected: {_priority[s.id] ?? 1},
                onSelectionChanged: (v) => setState(() {
                  _priority[s.id] = v.first;
                  _preview = null;
                }),
              ),
            ]),
        ],
        const SizedBox(height: 20),
        GlowButton(
          key: const Key('generate_plan'),
          label: l.generatePlan,
          gradient: EnjazColors.planGradient,
          icon: Icons.auto_awesome_rounded,
          onPressed: () => setState(() => _preview = _build()),
        ),
        if (_preview != null) ...[
          const SizedBox(height: 16),
          if (_preview!.isEmpty)
            EmptyState(icon: Icons.celebration_rounded, message: l.nothingToPlan)
          else ...[
            for (final entry in _groupByDay(_preview!).entries) ...[
              SectionHeader(title: formatDay(l, entry.key)),
              for (final p in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Icon(p.isRevision ? Icons.replay_rounded : Icons.menu_book_rounded, color: EnjazColors.cyan, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.title)),
                      Text(formatMinutes(l, p.minutes), style: TextStyle(color: context.mutedText, fontSize: 12)),
                    ]),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            GlowButton(key: const Key('apply_plan'), label: l.save, gradient: EnjazColors.studyGradient, onPressed: () => _apply(_preview!)),
          ],
        ],
      ]),
    );
  }

  Map<DateTime, List<PlannedTask>> _groupByDay(List<PlannedTask> plan) {
    final m = <DateTime, List<PlannedTask>>{};
    for (final p in plan) {
      m.putIfAbsent(p.date, () => []).add(p);
    }
    return m;
  }
}
