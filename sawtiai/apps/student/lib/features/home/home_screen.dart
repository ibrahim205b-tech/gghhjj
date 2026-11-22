import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../services/backend.dart';
import '../common/shared.dart';
import '../shell/announcements.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final backend = ref.watch(backendProvider);
    final stats = ref.watch(statsProvider);
    final profile = repo.profile;
    final today = stats.todayProgress;
    final change = stats.changeVsYesterday;
    final weekly = stats.weeklyCompletion;
    final upcoming = stats.upcomingTasks.take(4).toList();
    final exams = repo.exams.where((e) => !e.examAt.isBefore(repo.now())).take(3).toList();
    final motivation = repo.todaysMotivation;
    final announcements = repo.announcements.take(2).toList();
    final hour = repo.now().hour;
    final days = weekdayNames(l);
    final last7 = [for (var i = 6; i >= 0; i--) days[repo.now().subtract(Duration(days: i)).weekday - 1].substring(0, 3)];

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton(
        heroTag: null,
          key: const Key('add_task_fab'),
          tooltip: l.addTask,
          backgroundColor: EnjazColors.violet,
          foregroundColor: Colors.white,
          onPressed: () => showTaskSheet(context, ref),
          child: const Icon(Icons.add_rounded),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: RefreshIndicator(
                onRefresh: () => backend.sync(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
                  children: [
                    _SyncBanner(backend: backend),
                    // Header card (greeting + today's progress)
                    GlassCard(
                      blur: true,
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          ProfileAvatar(name: profile.displayName, url: profile.avatarUrl),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(hour < 12 ? l.goodMorning : l.goodEvening, style: TextStyle(color: context.mutedText, fontSize: 13)),
                              Text(profile.displayName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                            ]),
                          ),
                          Text(formatDay(l, repo.now()), style: TextStyle(color: context.mutedText, fontSize: 12)),
                        ]),
                        const SizedBox(height: 18),
                        Row(children: [
                          Expanded(child: Text(l.todayProgress, style: TextStyle(color: context.mutedText, fontSize: 13))),
                          if (change != null)
                            Text(l.fromYesterday('${change >= 0 ? '+' : ''}$change%'),
                                style: TextStyle(color: change >= 0 ? EnjazColors.success : EnjazColors.warning, fontSize: 12.5)),
                        ]),
                        const SizedBox(height: 8),
                        EnjazProgressBar(key: const Key('today_progress'), value: today.ratio),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: Text(l.tasksOf(today.done, today.total), style: TextStyle(color: context.mutedText, fontSize: 12.5))),
                          Text(l.studiedToday(formatMinutes(l, today.minutes)), style: TextStyle(color: context.mutedText, fontSize: 12.5)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: StatTile(
                          icon: Icons.track_changes_rounded,
                          iconColor: EnjazColors.danger,
                          value: weekly == null ? '—' : '${(weekly * 100).round()}%',
                          label: l.weeklyGoal,
                          onTap: () => context.push('/goals'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          icon: Icons.auto_stories_rounded,
                          iconColor: EnjazColors.violet,
                          value: '${repo.mySubjects.length}',
                          label: l.subjectsCount,
                          onTap: () => context.go('/subjects'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatTile(
                          icon: Icons.local_fire_department_rounded,
                          iconColor: EnjazColors.streak,
                          value: '${stats.streak}',
                          label: l.streakDays,
                          onTap: () => context.push('/stats'),
                        ),
                      ),
                    ]),
                    SectionHeader(title: l.quickActions),
                    Row(children: [
                      Expanded(
                        child: GlowButton(
                          label: l.aiStudyPlan,
                          gradient: EnjazColors.planGradient,
                          icon: Icons.auto_awesome_rounded,
                          onPressed: () => context.push('/planner'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlowButton(
                          label: l.studyNow,
                          gradient: EnjazColors.studyGradient,
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => context.push('/tools/pomodoro'),
                        ),
                      ),
                    ]),
                    SectionHeader(title: l.upcomingTasks, action: l.seeAll, onAction: () => context.push('/tasks')),
                    if (upcoming.isEmpty)
                      GlassCard(child: Text(l.noTasks, style: TextStyle(color: context.mutedText)))
                    else
                      for (final t in upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: TaskTile(task: t)),
                    if (exams.isNotEmpty) ...[
                      SectionHeader(title: l.upcomingExams, action: l.seeAll, onAction: () => context.go('/exams')),
                      SizedBox(
                        height: 108,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: exams.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => _ExamCountdownCard(exam: exams[i], now: repo.now()),
                        ),
                      ),
                    ],
                    SectionHeader(title: l.weeklyPerformance, action: l.seeAll, onAction: () => context.push('/stats')),
                    GlassCard(child: WeeklyBars(minutes: stats.last7DaysMinutes, labels: last7)),
                    if (motivation != null) ...[
                      SectionHeader(title: l.dailyMotivation, action: l.seeAll, onAction: () => context.push('/motivation')),
                      GlassCard(
                        gradient: LinearGradient(colors: [
                          EnjazColors.violet.withValues(alpha: 0.55),
                          EnjazColors.primary.withValues(alpha: 0.35),
                        ]),
                        onTap: () => context.push('/motivation'),
                        child: Row(children: [
                          const Icon(Icons.format_quote_rounded, size: 34, color: Colors.white),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(motivation.body,
                                maxLines: 4, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, height: 1.6, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ],
                    if (announcements.isNotEmpty) ...[
                      SectionHeader(title: l.latestAnnouncements),
                      for (final a in announcements)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: GlassCard(
                            onTap: () => showAnnouncementDialog(context, ref, a),
                            child: Row(children: [
                              const Icon(Icons.campaign_rounded, color: EnjazColors.cyan),
                              const SizedBox(width: 12),
                              Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                              Icon(Icons.chevron_left_rounded, color: context.mutedText),
                            ]),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.backend});
  final Backend backend;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (String? text, Color color, IconData icon) = switch (backend.syncState) {
      SyncState.syncing => (l.syncing, EnjazColors.cyan, Icons.sync_rounded),
      SyncState.offline => ('${l.noInternet} — ${l.offlineHint}', EnjazColors.warning, Icons.wifi_off_rounded),
      SyncState.failed => (l.syncFailed, EnjazColors.warning, Icons.cloud_off_rounded),
      _ => (null, EnjazColors.cyan, Icons.sync_rounded),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5))),
        ]),
      ),
    );
  }
}

class _ExamCountdownCard extends StatelessWidget {
  const _ExamCountdownCard({required this.exam, required this.now});
  final ExamItem exam;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final days = dayOnly(exam.examAt).difference(dayOnly(now)).inDays;
    final label = days == 0 ? l.examToday : days == 1 ? l.examTomorrow : l.daysLeft(days);
    return SizedBox(
      width: 200,
      child: GlassCard(
        radius: EnjazRadii.tile,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Expanded(child: Text(exam.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (exam.isOfficial) const Icon(Icons.verified_rounded, size: 16, color: EnjazColors.cyan),
          ]),
          Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: days <= 1 ? EnjazColors.warning : EnjazColors.cyan)),
          Text(formatDay(l, exam.examAt), style: TextStyle(fontSize: 11.5, color: context.mutedText)),
        ]),
      ),
    );
  }
}
