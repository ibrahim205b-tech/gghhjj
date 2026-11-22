import '../data/models.dart';

/// Personal statistics computed only from the student's real data.
class DayProgress {
  DayProgress({required this.total, required this.done, required this.minutes});
  final int total;
  final int done;
  final int minutes;
  double get ratio => total == 0 ? 0 : done / total;
}

class Stats {
  Stats({required this.tasks, required this.logs, required this.sessions, required this.now});
  final List<StudyTask> tasks;
  final List<StudyLog> logs;
  final List<StudySession> sessions;
  final DateTime now;

  DateTime get today => dayOnly(now);

  int minutesOn(DateTime day) =>
      logs.where((l) => dayOnly(l.date) == dayOnly(day)).fold(0, (a, l) => a + l.minutes);

  /// Tasks due that day (plus undated tasks completed that day) and sessions scheduled that day.
  DayProgress progressOn(DateTime day) {
    final d = dayOnly(day);
    final dayTasks = tasks.where((t) =>
        (t.dueDate != null && dayOnly(t.dueDate!) == d) ||
        (t.dueDate == null && t.isDone && t.doneAt != null && dayOnly(t.doneAt!) == d));
    final daySessions = sessions.where((s) => s.occursOn(d));
    final total = dayTasks.length + daySessions.length;
    final done = dayTasks.where((t) => t.isDone).length + daySessions.where((s) => s.doneOn(d)).length;
    return DayProgress(total: total, done: done, minutes: minutesOn(d));
  }

  DayProgress get todayProgress => progressOn(today);
  DayProgress get yesterdayProgress => progressOn(today.subtract(const Duration(days: 1)));

  /// Percentage-point change of today's completion ratio vs yesterday (null if not comparable).
  int? get changeVsYesterday {
    final y = yesterdayProgress;
    final t = todayProgress;
    if (y.total == 0 || t.total == 0) return null;
    return ((t.ratio - y.ratio) * 100).round();
  }

  bool _activeOn(DateTime d) =>
      minutesOn(d) > 0 ||
      tasks.any((t) => t.isDone && t.doneAt != null && dayOnly(t.doneAt!) == d) ||
      sessions.any((s) => s.doneOn(d));

  /// Consecutive active days ending today (or yesterday if today has no activity yet).
  int get streak {
    var d = today;
    if (!_activeOn(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (_activeOn(d) && n < 3650) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Minutes studied for each of the last 7 days (oldest first).
  List<int> get last7DaysMinutes => [for (var i = 6; i >= 0; i--) minutesOn(today.subtract(Duration(days: i)))];

  /// Completion of all tasks/sessions due this week (Mon..Sun), null when nothing planned.
  double? get weeklyCompletion {
    final start = today.subtract(Duration(days: today.weekday - 1));
    var total = 0, done = 0;
    for (var i = 0; i < 7; i++) {
      final p = progressOn(start.add(Duration(days: i)));
      total += p.total;
      done += p.done;
    }
    return total == 0 ? null : done / total;
  }

  int get totalMinutes => logs.fold(0, (a, l) => a + l.minutes);
  int get completedTasks => tasks.where((t) => t.isDone).length;

  List<StudyTask> get upcomingTasks => tasks
      .where((t) => !t.isDone && (t.dueDate == null || !dayOnly(t.dueDate!).isBefore(today)))
      .toList()
    ..sort((a, b) {
      final ad = a.dueDate ?? DateTime(9999), bd = b.dueDate ?? DateTime(9999);
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      final p = b.priority.compareTo(a.priority);
      return p != 0 ? p : (a.startTime ?? '99').compareTo(b.startTime ?? '99');
    });

  List<StudyTask> get overdueTasks =>
      tasks.where((t) => !t.isDone && t.dueDate != null && dayOnly(t.dueDate!).isBefore(today)).toList();
}

/// Required average on remaining exams to reach a target average.
/// Returns null when impossible to compute.
double? requiredScoreForTarget({required List<double> scoredPercents, required int remainingExams, required double targetPercent}) {
  if (remainingExams <= 0) return null;
  final n = scoredPercents.length + remainingExams;
  final need = (targetPercent * n - scoredPercents.fold(0.0, (a, b) => a + b)) / remainingExams;
  return need;
}
