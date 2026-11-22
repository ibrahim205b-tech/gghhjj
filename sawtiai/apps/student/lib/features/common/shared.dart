import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

Color hexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

const subjectIcons = <String, IconData>{
  'book': Icons.menu_book_rounded,
  'math': Icons.calculate_rounded,
  'science': Icons.science_rounded,
  'physics': Icons.bolt_rounded,
  'chemistry': Icons.biotech_rounded,
  'biology': Icons.eco_rounded,
  'language': Icons.translate_rounded,
  'arabic': Icons.history_edu_rounded,
  'english': Icons.abc_rounded,
  'islamic': Icons.mosque_rounded,
  'history': Icons.account_balance_rounded,
  'geography': Icons.public_rounded,
  'computer': Icons.computer_rounded,
  'economy': Icons.trending_up_rounded,
  'art': Icons.palette_rounded,
};

IconData subjectIcon(String key) => subjectIcons[key] ?? Icons.menu_book_rounded;

(String, Color) priorityLook(L10n l, int p) => switch (p) {
      3 => (l.priorityHigh, EnjazColors.violet),
      1 => (l.priorityLow, EnjazColors.textSecondary),
      _ => (l.priorityNormal, EnjazColors.cyan),
    };

(String, Color) topicStatusLook(L10n l, TopicStatus s) => switch (s) {
      TopicStatus.completed => (l.completed, EnjazColors.success),
      TopicStatus.inProgress => (l.inProgress, EnjazColors.cyan),
      TopicStatus.needsRevision => (l.needsReview, EnjazColors.warning),
      TopicStatus.notStarted => (l.notStarted, EnjazColors.textSecondary),
    };

/// A task row matching the reference design ("Calculus Review ... High").
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task});
  final StudyTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final (pLabel, pColor) = priorityLook(l, task.priority);
    final subject = repo.subject(task.subjectId);
    final when = [
      if (task.dueDate != null) formatDay(l, task.dueDate!, withWeekday: false),
      if (task.startTime != null) '${task.startTime!.substring(0, 5)}${task.endTime != null ? ' - ${task.endTime!.substring(0, 5)}' : ''}',
      if (task.estimatedMinutes != null && task.startTime == null) formatMinutes(l, task.estimatedMinutes!),
    ].join(' • ');
    return GlassCard(
      key: ValueKey('task_${task.id}'),
      radius: EnjazRadii.tile,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => showTaskSheet(context, ref, task: task),
      child: Row(children: [
        IconButton(
          tooltip: l.markDone,
          onPressed: () => repo.save('study_tasks', {
            ...task.m,
            'is_done': !task.isDone,
            'done_at': !task.isDone ? repo.now().toUtc().toIso8601String() : null,
          }),
          icon: Icon(task.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: task.isDone ? EnjazColors.success : EnjazColors.violet),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: task.isDone ? TextDecoration.lineThrough : null,
                    color: task.isDone ? context.mutedText : null)),
            if (when.isNotEmpty || subject != null)
              Text([if (subject != null) subject.nameAr, if (when.isNotEmpty) when].join(' • '),
                  style: TextStyle(fontSize: 12, color: context.mutedText)),
          ]),
        ),
        const SizedBox(width: 8),
        StatusChip(label: pLabel, color: pColor, filled: task.priority == 3),
      ]),
    );
  }
}

Future<void> showTaskSheet(BuildContext context, WidgetRef ref, {StudyTask? task, DateTime? date}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final title = TextEditingController(text: task?.title);
  final minutes = TextEditingController(text: task?.estimatedMinutes?.toString() ?? '');
  var due = task?.dueDate ?? date ?? dayOnly(repo.now());
  var priority = task?.priority ?? 2;
  String? subjectId = task?.subjectId;
  TimeOfDay? start = task?.startTime == null ? null : TimeOfDay(hour: minutesOf(task!.startTime) ~/ 60, minute: minutesOf(task.startTime) % 60);
  final formKey = GlobalKey<FormState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(task == null ? l.addTask : l.edit, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('task_title'),
                controller: title,
                autofocus: task == null,
                maxLength: 200,
                decoration: InputDecoration(labelText: l.taskTitle),
                validator: (v) => (v == null || v.trim().isEmpty) ? l.requiredField : null,
              ),
              DropdownButtonFormField<String?>(
                initialValue: subjectId,
                decoration: InputDecoration(labelText: l.subject),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.noSubject)),
                  for (final s in repo.mySubjects) DropdownMenuItem(value: s.id, child: Text(s.nameAr)),
                ],
                onChanged: (v) => subjectId = v,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text(formatDay(l, due, withWeekday: false)),
                    onPressed: () async {
                      final d = await showDatePicker(context: c, initialDate: due,
                          firstDate: DateTime(2020), lastDate: DateTime(2100));
                      if (d != null) setS(() => due = d);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(start == null ? l.startTime : start!.format(c)),
                    onPressed: () async {
                      final t = await showTimePicker(context: c, initialTime: start ?? TimeOfDay.now());
                      if (t != null) setS(() => start = t);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.estimatedMinutes),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = int.tryParse(v);
                  return (n == null || n < 0 || n > 1440) ? l.errorGeneric : null;
                },
              ),
              const SizedBox(height: 12),
              Text(l.priority),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 1, label: Text(l.priorityLow)),
                  ButtonSegment(value: 2, label: Text(l.priorityNormal)),
                  ButtonSegment(value: 3, label: Text(l.priorityHigh)),
                ],
                selected: {priority},
                onSelectionChanged: (v) => setS(() => priority = v.first),
              ),
              const SizedBox(height: 18),
              Row(children: [
                if (task != null)
                  IconButton(
                    tooltip: l.delete,
                    icon: const Icon(Icons.delete_outline_rounded, color: EnjazColors.danger),
                    onPressed: () async {
                      await repo.remove('study_tasks', task.id);
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
                Expanded(
                  child: GlowButton(
                    key: const Key('save_task'),
                    label: l.save,
                    gradient: EnjazColors.planGradient,
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final st = start;
                      await repo.save('study_tasks', {
                        ...?task?.m,
                        'title': title.text.trim(),
                        'subject_id': subjectId,
                        'due_date': isoDate(due),
                        'start_time': st == null ? null : '${hhmm(st.hour * 60 + st.minute)}:00',
                        'estimated_minutes': int.tryParse(minutes.text),
                        'priority': priority,
                        'is_done': task?.isDone ?? false,
                        'source': task?.source ?? 'manual',
                      });
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Simple bar chart (minutes per day for the last 7 days).
class WeeklyBars extends StatelessWidget {
  const WeeklyBars({super.key, required this.minutes, required this.labels});
  final List<int> minutes;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maxV = minutes.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < minutes.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(minutes[i] == 0 ? '' : (minutes[i] / 60).toStringAsFixed(minutes[i] < 600 ? 1 : 0),
                  style: TextStyle(fontSize: 10, color: context.mutedText)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: minutes[i] / maxV),
                duration: Duration(milliseconds: 500 + i * 60),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Container(
                  width: 16,
                  height: 4 + 96 * v,
                  decoration: BoxDecoration(
                    gradient: i == minutes.length - 1
                        ? EnjazColors.progressGradient
                        : const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: [EnjazColors.primary, EnjazColors.cyan]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i], maxLines: 1, style: TextStyle(fontSize: 10.5, color: context.mutedText)),
            ]),
          ),
      ]),
    );
  }
}

/// Avatar from the Google profile picture, or the initial.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.url, this.size = 46});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: EnjazColors.brandGradient,
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: url != null
            ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initial())
            : _initial(),
      );

  Widget _initial() => Center(
      child: Text(name.isEmpty ? '؟' : name.characters.first,
          style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w800)));
}
