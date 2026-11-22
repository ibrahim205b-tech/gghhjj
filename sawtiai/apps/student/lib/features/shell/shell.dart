import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../data/repository.dart';
import '../../logic/achievements.dart';
import 'announcements.dart';

/// Bottom navigation + app-wide background duties: announcements, update
/// prompts, achievements, reminders and push registration.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Timer? _debounce;
  bool _promptsShown = false;
  late final Repository _repo = ref.read(repositoryProvider);

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _repo.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _startup() async {
    final backend = ref.read(backendProvider);
    final notif = ref.read(notificationsProvider);
    await notif.requestPermission();
    _onDataChanged();
    final info = await PackageInfo.fromPlatform();
    await notif.initPush(
      onOpen: (m) {
        final link = m.data['deep_link'] as String?;
        if (link != null && mounted) _openDeepLink(link);
      },
      onToken: (id) => backend.registerDeviceToken(id, '${info.version}+${info.buildNumber}'),
    );
    if (backend.signedIn) await backend.sync();
    if (mounted) await _showPrompts();
  }

  void _openDeepLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'enjaz') return;
    final path = '/${uri.host}${uri.path}';
    const allowed = ['/home', '/schedule', '/subjects', '/exams', '/more', '/library', '/motivation', '/quiz', '/guidance'];
    if (allowed.contains(path)) context.go(path);
  }

  Future<void> _showPrompts() async {
    if (_promptsShown) return;
    _promptsShown = true;
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    await maybeShowUpdatePrompt(context, ref, int.tryParse(info.buildNumber) ?? 0);
    if (!mounted) return;
    await showPendingAnnouncements(context, ref);
  }

  /// Debounced: re-evaluate achievements and reminders after data changes.
  /// Everything is captured before the first await; after each await we
  /// stop if the shell was disposed.
  void _onDataChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      final repo = _repo;
      final l = context.l10n;
      final stats = ref.read(statsProvider);
      final notif = ref.read(notificationsProvider);
      final messenger = ScaffoldMessenger.of(context);
      for (final code in newlyEarned(stats, repo.attempts, repo.achievementCodes)) {
        await repo.save('student_achievements', {
          'id': repo.stableId('achievement:$code:${repo.userId ?? 'local'}'),
          'code': code,
          'earned_at': repo.now().toUtc().toIso8601String(),
        });
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(l.achievementUnlocked(achievementName(l, code)))));
      }
      final prefs = repo.preferences;
      await notif.rescheduleReminders(
        sessions: repo.sessions,
        exams: repo.exams.where((e) => e.examAt.isAfter(repo.now())).toList(),
        studyEnabled: prefs['notify_study'] != false,
        examsEnabled: prefs['notify_exams'] != false,
        studyTitle: l.notifStudyTitle,
        studyBody: l.notifStudyBody,
        examTitle: l.notifExamTitle,
        examBody: l.notifExamBody,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final backend = ref.watch(backendProvider);
    if (backend.suspended) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(l.accountSuspended, textAlign: TextAlign.center))));
    }
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l.homeTab),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month_rounded), label: l.scheduleTab),
          NavigationDestination(icon: const Icon(Icons.menu_book_outlined), selectedIcon: const Icon(Icons.menu_book_rounded), label: l.subjectsTab),
          NavigationDestination(icon: const Icon(Icons.fact_check_outlined), selectedIcon: const Icon(Icons.fact_check_rounded), label: l.examsTab),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: l.moreTab),
        ],
      ),
    );
  }
}

String achievementName(L10n l, String code) => switch (code) {
      'first_task' => l.achievement_first_task,
      'tasks_50' => l.achievement_tasks_50,
      'streak_3' => l.achievement_streak_3,
      'streak_7' => l.achievement_streak_7,
      'streak_30' => l.achievement_streak_30,
      'hours_10' => l.achievement_hours_10,
      'hours_100' => l.achievement_hours_100,
      'first_test' => l.achievement_first_test,
      'perfect_test' => l.achievement_perfect_test,
      _ => code,
    };
