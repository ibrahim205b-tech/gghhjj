import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../features/exams/exams_screen.dart';
import '../features/guidance/guidance_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/more/more_screen.dart';
import '../features/motivation/motivation_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/planner/planner_screen.dart';
import '../features/quiz/quiz_screens.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/shell.dart';
import '../features/subjects/subjects_screen.dart';
import '../features/tools/tools_screens.dart';
import 'providers.dart';

GoRouter buildRouter(WidgetRef ref) {
  final repo = ref.read(repositoryProvider);
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/splash' || loc.startsWith('/onboarding')) return null;
      if (!repo.onboardingDone || !repo.profile.complete) return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/schedule', builder: (_, _) => const ScheduleScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/subjects', builder: (_, _) => const SubjectsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/exams', builder: (_, _) => const ExamsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())]),
        ],
      ),
      GoRoute(path: '/subject/:id', builder: (_, s) => SubjectDetailScreen(subjectId: s.pathParameters['id']!)),
      GoRoute(path: '/planner', builder: (_, _) => const PlannerScreen()),
      GoRoute(path: '/quiz', builder: (_, _) => const QuizSetupScreen()),
      GoRoute(path: '/quiz/run', builder: (_, s) => QuizRunScreen(config: s.extra! as QuizConfig)),
      GoRoute(path: '/quiz/result/:id', builder: (_, s) => QuizResultScreen(attemptId: s.pathParameters['id']!)),
      GoRoute(path: '/quiz/history', builder: (_, _) => const QuizHistoryScreen()),
      GoRoute(path: '/quiz/saved', builder: (_, _) => const SavedQuestionsScreen()),
      GoRoute(path: '/library', builder: (_, _) => const LibraryScreen()),
      GoRoute(path: '/motivation', builder: (_, _) => const MotivationScreen()),
      GoRoute(path: '/tools/pomodoro', builder: (_, _) => const PomodoroScreen()),
      GoRoute(path: '/tools/stopwatch', builder: (_, _) => const StopwatchScreen()),
      GoRoute(path: '/tools/grade-calculator', builder: (_, _) => const GradeCalculatorScreen()),
      GoRoute(path: '/tools/percentage', builder: (_, _) => const PercentageCalculatorScreen()),
      GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
      GoRoute(path: '/notes', builder: (_, _) => const NotesScreen()),
      GoRoute(path: '/expenses', builder: (_, _) => const ExpensesScreen()),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/achievements', builder: (_, _) => const AchievementsScreen()),
      GoRoute(path: '/stats', builder: (_, _) => const StatisticsScreen()),
      GoRoute(path: '/guidance', builder: (_, _) => const GuidanceScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/academic', builder: (_, _) => const OnboardingScreen(editAcademicOnly: true)),
    ],
  );
}

class EnjazApp extends ConsumerStatefulWidget {
  const EnjazApp({super.key});

  @override
  ConsumerState<EnjazApp> createState() => _EnjazAppState();
}

class _EnjazAppState extends ConsumerState<EnjazApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(ref);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(backendProvider).sync();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(repositoryProvider.select((r) => r.preferences['theme_mode'] as String? ?? 'dark'));
    return MaterialApp.router(
      onGenerateTitle: (c) => c.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: buildEnjazTheme(Brightness.light),
      darkTheme: buildEnjazTheme(Brightness.dark),
      themeMode: switch (mode) { 'light' => ThemeMode.light, 'system' => ThemeMode.system, _ => ThemeMode.dark },
      locale: const Locale('ar'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: _router,
    );
  }
}
