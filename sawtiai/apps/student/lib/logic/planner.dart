import '../data/models.dart';

/// Offline study planner. No AI service: a deterministic, explainable
/// scheduler that weighs difficulty, exam urgency and student priorities.
class PlannerTopic {
  PlannerTopic({
    required this.topicId,
    required this.subjectId,
    required this.title,
    required this.difficulty,
    this.status = TopicStatus.notStarted,
    this.isDifficult = false,
    this.subjectPriority = 1.0,
  });
  final String topicId;
  final String subjectId;
  final String title;
  final int difficulty;           // 1..3
  final TopicStatus status;
  final bool isDifficult;         // flagged by the student
  final double subjectPriority;   // 0.5 .. 2 (student preference)
}

class PlannedTask {
  PlannedTask({required this.topicId, required this.subjectId, required this.title, required this.date,
      required this.minutes, required this.isRevision});
  final String topicId;
  final String subjectId;
  final String title;
  final DateTime date;
  final int minutes;
  final bool isRevision;
}

class StudyPlanner {
  StudyPlanner({required this.today});
  final DateTime today;

  /// Minutes a topic needs: harder -> longer; revision is shorter.
  static int minutesFor(PlannerTopic t) {
    final base = switch (t.difficulty) { 1 => 30, 3 => 75, _ => 50 };
    final flagged = t.isDifficult ? 15 : 0;
    return t.status == TopicStatus.needsRevision ? (base * 0.6).round() + flagged : base + flagged;
  }

  /// Builds a plan over [days] days with [dailyMinutes] each, skipping minutes
  /// already planned per day in [alreadyPlanned] (date -> minutes).
  List<PlannedTask> generate({
    required List<PlannerTopic> topics,
    required Map<String, DateTime> nextExamBySubject,
    required int dailyMinutes,
    required int days,
    Map<DateTime, int> alreadyPlanned = const {},
  }) {
    final remaining = topics.where((t) => t.status != TopicStatus.completed).toList();
    if (remaining.isEmpty || dailyMinutes <= 0 || days <= 0) return [];

    double urgency(PlannerTopic t) {
      final exam = nextExamBySubject[t.subjectId];
      if (exam == null) return 1;
      final daysLeft = dayOnly(exam).difference(dayOnly(today)).inDays;
      if (daysLeft < 0) return 1;
      return 1 + 10 / (daysLeft + 1); // exam tomorrow -> ~6x, in 30 days -> ~1.3x
    }

    double score(PlannerTopic t) =>
        urgency(t) * (1 + (t.difficulty - 1) * 0.25) * (t.isDifficult ? 1.3 : 1) *
        (t.status == TopicStatus.needsRevision ? 1.2 : 1) * t.subjectPriority;

    remaining.sort((a, b) => score(b).compareTo(score(a)));

    final plan = <PlannedTask>[];
    final capacity = <int, int>{
      for (var i = 0; i < days; i++)
        i: (dailyMinutes - (alreadyPlanned[dayOnly(today.add(Duration(days: i)))] ?? 0)).clamp(0, dailyMinutes),
    };

    // Round-robin across subjects so one subject doesn't take a whole day.
    final bySubject = <String, List<PlannerTopic>>{};
    for (final t in remaining) {
      bySubject.putIfAbsent(t.subjectId, () => []).add(t);
    }
    final queue = <PlannerTopic>[];
    while (bySubject.values.any((l) => l.isNotEmpty)) {
      final order = bySubject.keys.toList()
        ..sort((a, b) => (bySubject[b]!.isEmpty ? 0 : score(bySubject[b]!.first))
            .compareTo(bySubject[a]!.isEmpty ? 0 : score(bySubject[a]!.first)));
      for (final s in order) {
        if (bySubject[s]!.isNotEmpty) queue.add(bySubject[s]!.removeAt(0));
      }
    }

    for (final t in queue) {
      final need = minutesFor(t);
      final exam = nextExamBySubject[t.subjectId];
      final lastDay = exam == null
          ? days - 1
          : (dayOnly(exam).difference(dayOnly(today)).inDays - 1).clamp(0, days - 1);
      // first day (before the exam) that still has room
      int? slot;
      for (var i = 0; i <= lastDay; i++) {
        if (capacity[i]! >= need || (capacity[i]! >= 20 && capacity[i] == dailyMinutes)) {
          slot = i;
          break;
        }
      }
      if (slot == null) continue; // doesn't fit in the window; leave it unplanned
      final minutes = need.clamp(0, capacity[slot]!);
      capacity[slot] = capacity[slot]! - minutes;
      plan.add(PlannedTask(
        topicId: t.topicId,
        subjectId: t.subjectId,
        title: t.title,
        date: dayOnly(today.add(Duration(days: slot))),
        minutes: minutes,
        isRevision: t.status == TopicStatus.needsRevision,
      ));
    }
    plan.sort((a, b) => a.date.compareTo(b.date));
    return plan;
  }

  /// Moves overdue, unfinished tasks onto upcoming days with free capacity.
  /// Returns task id -> new due date.
  Map<String, DateTime> redistribute({
    required List<StudyTask> overdue,
    required Map<DateTime, int> plannedMinutesByDay,
    required int dailyMinutes,
    int horizonDays = 14,
  }) {
    final result = <String, DateTime>{};
    final cap = <DateTime, int>{
      for (var i = 0; i < horizonDays; i++)
        dayOnly(today.add(Duration(days: i))):
            (dailyMinutes - (plannedMinutesByDay[dayOnly(today.add(Duration(days: i)))] ?? 0)).clamp(0, 1440),
    };
    final sorted = [...overdue]..sort((a, b) {
        final p = b.priority.compareTo(a.priority);
        return p != 0 ? p : (a.dueDate ?? today).compareTo(b.dueDate ?? today);
      });
    for (final t in sorted) {
      final need = t.estimatedMinutes ?? 45;
      final day = cap.entries.where((e) => e.value >= need).map((e) => e.key).firstOrNull ??
          cap.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      cap[day] = (cap[day]! - need).clamp(0, 1440);
      result[t.id] = day;
    }
    return result;
  }
}
