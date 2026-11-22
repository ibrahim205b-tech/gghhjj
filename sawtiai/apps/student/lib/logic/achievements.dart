import '../data/models.dart';
import 'stats.dart';

/// Achievement rules, evaluated from real data only.
class AchievementRule {
  const AchievementRule(this.code, this.icon, this.check);
  final String code;
  final int icon; // Material icon code point
  final bool Function(Stats s, List<ExamAttempt> attempts) check;
}

final achievementRules = <AchievementRule>[
  AchievementRule('first_task', 0xe86c, (s, _) => s.completedTasks >= 1),
  AchievementRule('tasks_50', 0xe877, (s, _) => s.completedTasks >= 50),
  AchievementRule('streak_3', 0xe518, (s, _) => s.streak >= 3),
  AchievementRule('streak_7', 0xe518, (s, _) => s.streak >= 7),
  AchievementRule('streak_30', 0xea65, (s, _) => s.streak >= 30),
  AchievementRule('hours_10', 0xe425, (s, _) => s.totalMinutes >= 600),
  AchievementRule('hours_100', 0xe425, (s, _) => s.totalMinutes >= 6000),
  AchievementRule('first_test', 0xe873, (_, a) => a.isNotEmpty),
  AchievementRule('perfect_test', 0xe838, (_, a) => a.any((x) => x.total >= 5 && x.correct == x.total)),
];

/// Codes newly earned given what the student already has.
List<String> newlyEarned(Stats stats, List<ExamAttempt> attempts, Set<String> owned) =>
    [for (final r in achievementRules) if (!owned.contains(r.code) && r.check(stats, attempts)) r.code];
