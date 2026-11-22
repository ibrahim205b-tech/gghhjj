import 'package:enjaz_student/app/app.dart';
import 'package:enjaz_student/data/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'helpers.dart';

Future<Repository> _repo(WidgetTester t, {bool onboarded = true}) async {
  final repo = (await t.runAsync(() async {
    final r = await makeRepo(clock: () => DateTime(2026, 11, 22, 10));
    await seedContent(r);
    if (onboarded) await completeOnboarding(r);
    return r;
  }))!;
  return repo;
}

Future<void> _launch(WidgetTester t, Repository repo) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.75;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(overrides: overridesFor(repo), child: const EnjazApp()));
  await t.pump(const Duration(milliseconds: 1600)); // splash
  await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

/// Real file I/O (SQLite) must run outside the fake clock.
Future<void> _settleIo(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => PackageInfo.setMockInitialValues(
      appName: 'إنجاز', packageName: 'com.enjaz.student', version: '1.0.0', buildNumber: '1', buildSignature: ''));

  testWidgets('first launch: offline onboarding through to the personalised home (RTL, Iraqi)', (t) async {
    final repo = await _repo(t, onboarded: false);
    await _launch(t, repo);
    expect(find.text('هلا بيك بإنجاز'), findsOneWidget);
    expect(Directionality.of(t.element(find.text('هلا بيك بإنجاز'))), TextDirection.rtl);

    await t.tap(find.text('يلا نبدي'));
    await t.pumpAndSettle();
    // No backend in this build: the app says so honestly and works offline.
    expect(find.textContaining('خدمة الحسابات بعدها ما مفعّلة'), findsOneWidget);
    await t.tap(find.byKey(const Key('continue_offline')));
    await _settleIo(t);
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('name_field')), 'زينب');
    await t.tap(find.byKey(const Key('next_button')));
    await t.pumpAndSettle();
    expect(find.text('بأي مرحلة أنت؟'), findsOneWidget);
    await t.tap(find.text('المرحلة الإعدادية'));
    await t.pump();
    await t.tap(find.byKey(const Key('next_button')));
    await t.pumpAndSettle();
    await t.tap(find.text('السادس الإعدادي'));
    await t.pump();
    await t.tap(find.byKey(const Key('next_button')));
    await t.pumpAndSettle();
    expect(find.text('شنو فرعك؟'), findsOneWidget);
    await t.tap(find.text('العلمي الإحيائي'));
    await t.pump();
    await t.tap(find.byKey(const Key('next_button')));
    await t.pumpAndSettle();
    expect(find.text('السنة الدراسية'), findsOneWidget);
    await t.tap(find.byKey(const Key('next_button')));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('كلشي جاهز!'), findsOneWidget);
    await t.tap(find.byKey(const Key('enter_app')));
    await t.pumpAndSettle();

    expect(find.text('زينب'), findsOneWidget);
    expect(find.text('شكد أنجزت اليوم؟'), findsOneWidget);
    expect(find.text('حالياً ما عندك مهام'), findsOneWidget);
    expect(repo.onboardingDone, isTrue);
    expect(repo.profile.branchId, 'b-bio');
    expect(repo.mySubjects.map((s) => s.nameAr), ['الرياضيات', 'الأحياء']);
  });

  testWidgets('home: add a task, complete it, progress updates from real data', (t) async {
    final repo = await _repo(t);
    await _launch(t, repo);
    expect(find.text('0 من 0 مهام'), findsOneWidget);
    await t.tap(find.byKey(const Key('add_task_fab')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('task_title')), 'حل تمارين الفصل الأول');
    await t.tap(find.byKey(const Key('save_task')));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('حل تمارين الفصل الأول'), findsOneWidget);
    expect(find.text('0 من 1 مهام'), findsOneWidget);
    await t.tap(find.byTooltip('خلصتها').first);
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('1 من 1 مهام'), findsOneWidget);
    expect(repo.tasks.single.isDone, isTrue);
  });

  testWidgets('subjects: only my grade/branch, topic status changes completion', (t) async {
    final repo = await _repo(t);
    await _launch(t, repo);
    await t.tap(find.text('موادي'));
    await t.pumpAndSettle();
    expect(find.text('الرياضيات'), findsOneWidget);
    expect(find.text('الأحياء'), findsNothing, reason: 'applied branch must not see biology');
    expect(find.text('مادة صف ثاني'), findsNothing, reason: 'other grades are never mixed in');
    await t.tap(find.text('الرياضيات'));
    await t.pumpAndSettle();
    await t.tap(find.text('الأعداد المركبة'));
    await t.pumpAndSettle();
    await t.tap(find.text('تعريف العدد المركب'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('status_completed')));
    await t.pump();
    await t.tap(find.byKey(const Key('save_topic')));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('خلصت 50٪'), findsWidgets);
  });

  testWidgets('question bank: take a test, submit, see the real score and review', (t) async {
    final repo = await _repo(t);
    await _launch(t, repo);
    await t.tap(find.text('الاختبارات'));
    await t.pumpAndSettle();
    await t.tap(find.text('بنك الأسئلة'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('start_quiz')));
    await t.pumpAndSettle();
    // Answer every question correctly, whatever order they were shuffled into.
    for (var i = 0; i < 2; i++) {
      if (find.byKey(const ValueKey('option_o1')).evaluate().isNotEmpty) {
        await t.tap(find.byKey(const ValueKey('option_o1')));
      } else {
        await t.tap(find.byKey(const ValueKey('option_o3')));
      }
      await t.pump();
      final next = find.byKey(const Key('next_question'));
      if (next.evaluate().isNotEmpty) {
        await t.tap(next);
        await t.pumpAndSettle();
      }
    }
    await t.tap(find.byKey(const Key('submit_quiz')));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('2 صح من 2'), findsOneWidget);
    expect(repo.attempts.single.correct, 2);
    expect(repo.records('student_answers').length, 2);
  });

  testWidgets('schedule: add a weekly session and mark it done (logs real study time)', (t) async {
    final repo = await _repo(t);
    await _launch(t, repo);
    await t.tap(find.text('جدولي'));
    await t.pumpAndSettle();
    expect(find.text('ماكو حصص بهذا اليوم'), findsOneWidget);
    await t.tap(find.byKey(const Key('add_session_fab')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('session_title')), 'مراجعة رياضيات');
    await t.tap(find.text('تتكرر كل أسبوع'));
    await t.pump();
    await t.tap(find.byKey(const Key('save_session')));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(find.text('مراجعة رياضيات'), findsOneWidget);
    expect(repo.sessions.single.repeatsWeekly, isTrue);
    await t.tap(find.byTooltip('خلصتها').first);
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(repo.studyLogs.single.minutes, 60);
  });

  testWidgets('settings: switching to light theme applies immediately and persists', (t) async {
    final repo = await _repo(t);
    await _launch(t, repo);
    await t.tap(find.text('المزيد'));
    await t.pumpAndSettle();
    await t.dragUntilVisible(find.byIcon(Icons.settings_rounded), find.byType(ListView).last, const Offset(0, -300));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.settings_rounded));
    await t.pumpAndSettle();
    expect(find.text('الإعدادات'), findsOneWidget);
    await t.dragUntilVisible(find.text('فاتح'), find.byType(ListView).last, const Offset(0, -300));
    await t.pumpAndSettle();
    await t.tap(find.text('فاتح'));
    await _settleIo(t);
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.text('فاتح'))).brightness, Brightness.light);
    expect(repo.preferences['theme_mode'], 'light');
  });
}
