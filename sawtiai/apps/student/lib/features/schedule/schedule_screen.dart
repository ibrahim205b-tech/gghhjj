import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../common/shared.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _day = dayOnly(ref.read(repositoryProvider).now());
  bool _calendar = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final sessions = repo.sessions.where((s) => s.occursOn(_day)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final tasks = repo.tasks.where((t) => t.dueDate != null && dayOnly(t.dueDate!) == _day).toList();
    final planned = sessions.fold<int>(0, (a, s) => a + s.plannedMinutes);
    final actual = repo.studyLogs.where((g) => dayOnly(g.date) == _day).fold<int>(0, (a, g) => a + g.minutes);

    return EnjazPage(
      title: l.studySchedule,
      actions: [
        IconButton(
          tooltip: _calendar ? l.listView : l.calendarView,
          icon: Icon(_calendar ? Icons.view_agenda_rounded : Icons.calendar_month_rounded),
          onPressed: () => setState(() => _calendar = !_calendar),
        ),
      ],
      fab: FloatingActionButton.extended(
        heroTag: null,
        key: const Key('add_session_fab'),
        backgroundColor: EnjazColors.violet,
        foregroundColor: Colors.white,
        onPressed: () => showSessionSheet(context, ref, day: _day),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addSession),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        if (_calendar)
          _MonthCalendar(
            selected: _day,
            hasItems: (d) => repo.sessions.any((s) => s.occursOn(d)) || repo.tasks.any((t) => t.dueDate != null && dayOnly(t.dueDate!) == d),
            onSelect: (d) => setState(() => _day = d),
          )
        else
          _WeekStrip(selected: _day, onSelect: (d) => setState(() => _day = d)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text(formatDay(l, _day, withYear: true), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          Text(l.plannedVsActual(formatMinutes(l, planned), formatMinutes(l, actual)),
              style: TextStyle(color: context.mutedText, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        if (sessions.isEmpty && tasks.isEmpty) EmptyState(icon: Icons.event_available_rounded, message: l.noSessions),
        for (final s in sessions)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: _SessionTile(session: s, day: _day)),
        if (tasks.isNotEmpty) ...[
          SectionHeader(title: l.tasks),
          for (final t in tasks) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskTile(task: t)),
        ],
      ]),
    );
  }
}

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.selected, required this.onSelect});
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final names = weekdayNames(l);
    final start = selected.subtract(Duration(days: selected.weekday - 1));
    final today = dayOnly(ref.read(repositoryProvider).now());
    return Row(children: [
      IconButton(onPressed: () => onSelect(selected.subtract(const Duration(days: 7))), icon: const Icon(Icons.chevron_right_rounded)),
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Builder(builder: (context) {
            final d = start.add(Duration(days: i));
            final on = d == selected;
            return GestureDetector(
              onTap: () => onSelect(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: on ? EnjazColors.planGradient : null,
                  color: on ? null : EnjazColors.glassFill(context.isDark),
                  borderRadius: BorderRadius.circular(16),
                  border: d == today && !on ? Border.all(color: EnjazColors.cyan) : null,
                ),
                child: Column(children: [
                  Text(names[d.weekday - 1].substring(0, 3), style: TextStyle(fontSize: 10.5, color: on ? Colors.white : context.mutedText)),
                  const SizedBox(height: 4),
                  Text('${d.day}', style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : null)),
                ]),
              ),
            );
          }),
        ),
      IconButton(onPressed: () => onSelect(selected.add(const Duration(days: 7))), icon: const Icon(Icons.chevron_left_rounded)),
    ]);
  }
}

class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({required this.selected, required this.hasItems, required this.onSelect});
  final DateTime selected;
  final bool Function(DateTime) hasItems;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late DateTime _month = DateTime(widget.selected.year, widget.selected.month);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final names = weekdayNames(l);
    final first = _month;
    final lead = first.weekday - 1;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_right_rounded)),
          Expanded(child: Text(formatDay(l, _month, withWeekday: false, withYear: true).replaceFirst(RegExp(r'^\d+ '), ''),
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_left_rounded)),
        ]),
        Row(children: [for (final n in names) Expanded(child: Center(child: Text(n.substring(0, 2), style: TextStyle(fontSize: 11, color: context.mutedText))))]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= daysInMonth; d++)
              Builder(builder: (context) {
                final date = DateTime(first.year, first.month, d);
                final on = date == widget.selected;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onSelect(date),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(gradient: on ? EnjazColors.planGradient : null, borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('$d', style: TextStyle(fontWeight: FontWeight.w700, color: on ? Colors.white : null)),
                      if (widget.hasItems(date))
                        Container(width: 5, height: 5, decoration: const BoxDecoration(color: EnjazColors.cyan, shape: BoxShape.circle)),
                    ]),
                  ),
                );
              }),
          ],
        ),
      ]),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, required this.day});
  final StudySession session;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final subject = repo.subject(session.subjectId);
    final done = session.doneOn(day);
    final color = subject == null ? EnjazColors.cyan : hexColor(subject.color);
    return GlassCard(
      key: ValueKey('session_${session.id}'),
      radius: EnjazRadii.tile,
      padding: const EdgeInsets.all(14),
      onTap: () => showSessionSheet(context, ref, session: session, day: day),
      child: Row(children: [
        Container(width: 5, height: 52, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.title ?? subject?.nameAr ?? session.customSubject ?? '',
                style: TextStyle(fontWeight: FontWeight.w700, decoration: done ? TextDecoration.lineThrough : null)),
            Text('${session.startTime.substring(0, 5)} - ${session.endTime.substring(0, 5)}'
                '${session.breakMinutes > 0 ? ' • ${l.breakMinutes}: ${session.breakMinutes}' : ''}',
                style: TextStyle(fontSize: 12, color: context.mutedText)),
            if (session.note?.isNotEmpty ?? false)
              Text(session.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.mutedText)),
          ]),
        ),
        if (session.repeatsWeekly) Icon(Icons.repeat_rounded, size: 16, color: context.mutedText),
        IconButton(
          tooltip: l.markDone,
          icon: Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: done ? EnjazColors.success : EnjazColors.violet),
          onPressed: () => toggleSessionDone(repo, session, day),
        ),
      ]),
    );
  }
}

/// Marking a session done records real study time (a study_log) once.
Future<void> toggleSessionDone(Repository repo, StudySession s, DateTime day) async {
  final key = isoDate(day);
  final dates = s.completedDates.toList();
  final logId = repo.stableId('session:${s.id}:$key');
  if (dates.contains(key)) {
    dates.remove(key);
    await repo.save('study_sessions', {...s.m, 'completed_dates': dates, 'actual_minutes': (s.actualMinutes - s.plannedMinutes).clamp(0, 1 << 30)});
    if (repo.record('study_logs', logId) != null) await repo.remove('study_logs', logId);
  } else {
    dates.add(key);
    await repo.save('study_sessions', {...s.m, 'completed_dates': dates, 'actual_minutes': s.actualMinutes + s.plannedMinutes});
    if (s.plannedMinutes > 0) {
      await repo.save('study_logs', {
        'id': logId, 'log_date': key, 'subject_id': s.subjectId, 'minutes': s.plannedMinutes, 'source': 'session',
      });
    }
  }
}

Future<void> showSessionSheet(BuildContext context, WidgetRef ref, {StudySession? session, required DateTime day}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final title = TextEditingController(text: session?.title);
  final note = TextEditingController(text: session?.note);
  final breakCtl = TextEditingController(text: '${session?.breakMinutes ?? 0}');
  String? subjectId = session?.subjectId;
  var repeat = session?.repeatsWeekly ?? false;
  var start = session == null
      ? const TimeOfDay(hour: 16, minute: 0)
      : TimeOfDay(hour: minutesOf(session.startTime) ~/ 60, minute: minutesOf(session.startTime) % 60);
  var end = session == null
      ? const TimeOfDay(hour: 17, minute: 0)
      : TimeOfDay(hour: minutesOf(session.endTime) ~/ 60, minute: minutesOf(session.endTime) % 60);
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(session == null ? l.addSession : l.editSession, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(key: const Key('session_title'), controller: title, decoration: InputDecoration(labelText: l.sessionTitle)),
            const SizedBox(height: 12),
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
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: c, initialTime: start);
                    if (t != null) setS(() => start = t);
                  },
                  child: Text('${l.startTime}: ${start.format(c)}'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: c, initialTime: end);
                    if (t != null) setS(() => end = t);
                  },
                  child: Text('${l.endTime}: ${end.format(c)}'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: breakCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.breakMinutes)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.repeatWeekly),
              subtitle: Text(weekdayNames(l)[day.weekday - 1]),
              value: repeat,
              onChanged: (v) => setS(() => repeat = v),
            ),
            TextField(controller: note, maxLines: 2, decoration: InputDecoration(labelText: l.note)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: EnjazColors.danger))),
            const SizedBox(height: 16),
            Row(children: [
              if (session != null)
                IconButton(
                  tooltip: l.delete,
                  icon: const Icon(Icons.delete_outline_rounded, color: EnjazColors.danger),
                  onPressed: () async {
                    await repo.remove('study_sessions', session.id);
                    if (c.mounted) Navigator.pop(c);
                  },
                ),
              Expanded(
                child: GlowButton(
                  key: const Key('save_session'),
                  label: l.save,
                  gradient: EnjazColors.planGradient,
                  onPressed: () async {
                    final s = start.hour * 60 + start.minute, e = end.hour * 60 + end.minute;
                    final br = int.tryParse(breakCtl.text) ?? 0;
                    if (e <= s || br < 0 || br >= e - s) {
                      setS(() => error = l.errorGeneric);
                      return;
                    }
                    await repo.save('study_sessions', {
                      ...?session?.m,
                      'title': title.text.trim().isEmpty ? null : title.text.trim(),
                      'subject_id': subjectId,
                      'start_time': '${hhmm(s)}:00',
                      'end_time': '${hhmm(e)}:00',
                      'break_minutes': br,
                      'repeats_weekly': repeat,
                      'weekday': repeat ? day.weekday : null,
                      'session_date': repeat ? null : isoDate(day),
                      'note': note.text.trim().isEmpty ? null : note.text.trim(),
                      'completed_dates': session?.completedDates ?? <String>[],
                      'actual_minutes': session?.actualMinutes ?? 0,
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
  );
}
