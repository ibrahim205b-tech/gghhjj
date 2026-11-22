import 'package:enjaz_student/data/models.dart';
import 'package:enjaz_student/logic/achievements.dart';
import 'package:enjaz_student/logic/planner.dart';
import 'package:enjaz_student/logic/quiz.dart';
import 'package:enjaz_student/logic/stats.dart';
import 'package:flutter_test/flutter_test.dart';

StudyTask task(String id, {String? due, bool done = false, String? doneAt, int priority = 2, int? minutes}) => StudyTask({
      'id': id, 'title': id, 'due_date': due, 'is_done': done, 'done_at': doneAt, 'priority': priority,
      'estimated_minutes': minutes,
    });

StudyLog log(String date, int minutes) => StudyLog({'id': date, 'log_date': date, 'minutes': minutes});

void main() {
  final now = DateTime(2026, 11, 22, 10); // Sunday

  group('stats (real data only)', () {
    test('today progress counts tasks and sessions due today', () {
      final s = Stats(
        tasks: [task('a', due: '2026-11-22', done: true), task('b', due: '2026-11-22'), task('c', due: '2026-11-23')],
        logs: [log('2026-11-22', 45), log('2026-11-22', 90)],
        sessions: [
          StudySession({'id': 's', 'start_time': '16:00:00', 'end_time': '17:00:00', 'repeats_weekly': true, 'weekday': 7,
            'completed_dates': ['2026-11-22']}),
        ],
        now: now,
      );
      final p = s.todayProgress;
      expect(p.total, 3);
      expect(p.done, 2);
      expect(p.minutes, 135);
    });

    test('empty data gives zero, not fake numbers', () {
      final s = Stats(tasks: const [], logs: const [], sessions: const [], now: now);
      expect(s.todayProgress.ratio, 0);
      expect(s.weeklyCompletion, isNull);
      expect(s.changeVsYesterday, isNull);
      expect(s.streak, 0);
    });

    test('streak counts consecutive active days, tolerating no activity yet today', () {
      final s = Stats(tasks: const [], logs: [log('2026-11-21', 30), log('2026-11-20', 30), log('2026-11-18', 30)],
          sessions: const [], now: now);
      expect(s.streak, 2);
    });

    test('last 7 days minutes oldest first', () {
      final s = Stats(tasks: const [], logs: [log('2026-11-16', 10), log('2026-11-22', 70)], sessions: const [], now: now);
      expect(s.last7DaysMinutes, [10, 0, 0, 0, 0, 0, 70]);
    });

    test('overdue and upcoming ordering', () {
      final s = Stats(tasks: [task('old', due: '2026-11-20'), task('hi', due: '2026-11-23', priority: 3), task('lo', due: '2026-11-23', priority: 1)],
          logs: const [], sessions: const [], now: now);
      expect(s.overdueTasks.map((t) => t.id), ['old']);
      expect(s.upcomingTasks.map((t) => t.id), ['hi', 'lo']);
    });

    test('required score toward target', () {
      expect(requiredScoreForTarget(scoredPercents: [80, 90], remainingExams: 2, targetPercent: 90), 95);
      expect(requiredScoreForTarget(scoredPercents: [80], remainingExams: 0, targetPercent: 90), isNull);
    });
  });

  group('planner (offline)', () {
    final planner = StudyPlanner(today: now);
    List<PlannerTopic> topics() => [
          PlannerTopic(topicId: 'm1', subjectId: 'math', title: 'm1', difficulty: 3),
          PlannerTopic(topicId: 'm2', subjectId: 'math', title: 'm2', difficulty: 1),
          PlannerTopic(topicId: 'p1', subjectId: 'phys', title: 'p1', difficulty: 2),
          PlannerTopic(topicId: 'p2', subjectId: 'phys', title: 'p2', difficulty: 2, status: TopicStatus.completed),
        ];

    test('skips completed topics and respects daily capacity', () {
      final plan = planner.generate(topics: topics(), nextExamBySubject: {}, dailyMinutes: 90, days: 7);
      expect(plan.map((p) => p.topicId), isNot(contains('p2')));
      expect(plan.length, 3);
      final byDay = <DateTime, int>{};
      for (final p in plan) {
        byDay[p.date] = (byDay[p.date] ?? 0) + p.minutes;
      }
      expect(byDay.values.every((m) => m <= 90), isTrue);
    });

    test('urgent exam subject is scheduled first and before the exam', () {
      final plan = planner.generate(
          topics: topics(), nextExamBySubject: {'phys': DateTime(2026, 11, 24)}, dailyMinutes: 60, days: 7);
      final p1 = plan.firstWhere((p) => p.topicId == 'p1');
      expect(p1.date.isBefore(DateTime(2026, 11, 24)), isTrue);
      expect(plan.first.subjectId, 'phys');
    });

    test('already planned minutes reduce capacity', () {
      final plan = planner.generate(topics: topics(), nextExamBySubject: {}, dailyMinutes: 60, days: 2,
          alreadyPlanned: {DateTime(2026, 11, 22): 60});
      expect(plan.every((p) => p.date != DateTime(2026, 11, 22)), isTrue);
    });

    test('redistribute moves overdue tasks to days with room', () {
      final moves = planner.redistribute(
        overdue: [task('x', due: '2026-11-19', minutes: 60, priority: 3), task('y', due: '2026-11-20', minutes: 60)],
        plannedMinutesByDay: {DateTime(2026, 11, 22): 120},
        dailyMinutes: 120,
      );
      expect(moves['x'], DateTime(2026, 11, 23));
      expect(moves['y'], DateTime(2026, 11, 23));
    });

    test('nothing to plan', () {
      expect(planner.generate(topics: const [], nextExamBySubject: {}, dailyMinutes: 60, days: 7), isEmpty);
    });
  });

  group('quiz grading', () {
    Question q(String type, {List<Map<String, dynamic>> opts = const [], String? answer}) => Question(
        {'id': 'q', 'grade_id': 'g', 'subject_id': 's', 'question_type': type, 'question_text': 't', 'answer_text': answer},
        opts.map(QuestionOption.new).toList());

    test('multiple choice', () {
      final mc = q('multiple_choice', opts: [
        {'id': 'a', 'question_id': 'q', 'option_text': 'A', 'is_correct': false},
        {'id': 'b', 'question_id': 'q', 'option_text': 'B', 'is_correct': true},
      ]);
      expect(isCorrect(mc, AnswerInput(optionId: 'b')), isTrue);
      expect(isCorrect(mc, AnswerInput(optionId: 'a')), isFalse);
      expect(isCorrect(mc, AnswerInput()), isFalse);
    });

    test('short answers ignore diacritics, hamza forms and spacing', () {
      final sa = q('short_answer', answer: 'الأكسجين|اوكسجين');
      expect(isCorrect(sa, AnswerInput(text: ' الاكسجين ')), isTrue);
      expect(isCorrect(sa, AnswerInput(text: 'أوكسجين')), isTrue);
      expect(isCorrect(sa, AnswerInput(text: 'الهيدروجين')), isFalse);
      expect(normalizeAnswer('مَدْرَسَةٌ'), 'مدرسه');
    });

    test('grade percent', () {
      final mc = q('true_false', opts: [{'id': 't', 'question_id': 'q', 'option_text': 'صح', 'is_correct': true}]);
      final r = grade([mc], {'q': AnswerInput(optionId: 't')});
      expect(r.percent, 100);
    });
  });

  test('achievements come from real activity', () {
    final s = Stats(tasks: [task('a', done: true, doneAt: '2026-11-22T08:00:00Z')], logs: const [], sessions: const [], now: now);
    expect(newlyEarned(s, const [], {}), contains('first_task'));
    expect(newlyEarned(s, const [], {'first_task'}), isNot(contains('first_task')));
    expect(newlyEarned(Stats(tasks: const [], logs: const [], sessions: const [], now: now), const [], {}), isEmpty);
  });
}
