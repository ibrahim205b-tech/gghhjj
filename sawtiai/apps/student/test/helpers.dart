import 'dart:io';

import 'package:enjaz_student/app/providers.dart';
import 'package:enjaz_student/data/local_db.dart';
import 'package:enjaz_student/data/repository.dart';
import 'package:enjaz_student/services/backend.dart';
import 'package:enjaz_student/services/notifications.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A real SQLite database (in memory) - not a mock.
Future<Repository> makeRepo({DateTime Function()? clock}) async {
  sqfliteFfiInit();
  // A fresh file per repo: ':memory:' is cached and shared by sqflite_ffi.
  final path = '${Directory.systemTemp.createTempSync('enjaz_test_').path}/enjaz.db';
  final db = await LocalDb.open(factory: databaseFactoryFfi, path: path);
  final repo = Repository(db, clock: clock);
  await repo.load();
  return repo;
}

/// Published content as the server would deliver it after RLS filtering.
Future<void> seedContent(Repository repo) async {
  await repo.replaceContent('academic_stages', [
    {'id': 'st-p', 'code': 'preparatory', 'name_ar': 'المرحلة الإعدادية', 'sort_order': 2},
  ]);
  await repo.replaceContent('grades', [
    {'id': 'g12', 'stage_id': 'st-p', 'code': 'grade_12', 'name_ar': 'السادس الإعدادي', 'has_branches': true, 'sort_order': 6},
  ]);
  await repo.replaceContent('academic_branches', [
    {'id': 'b-app', 'grade_id': 'g12', 'code': 'applied', 'name_ar': 'العلمي التطبيقي', 'sort_order': 1},
    {'id': 'b-bio', 'grade_id': 'g12', 'code': 'biological', 'name_ar': 'العلمي الإحيائي', 'sort_order': 2},
  ]);
  await repo.replaceContent('academic_years', [
    {'id': 'y26', 'label': '2026-2027', 'is_current': true},
  ]);
  await repo.replaceContent('subjects', [
    {'id': 'math', 'grade_id': 'g12', 'branch_id': null, 'name_ar': 'الرياضيات', 'icon': 'math', 'color': '#4F8CFF', 'sort_order': 1},
    {'id': 'bio', 'grade_id': 'g12', 'branch_id': 'b-bio', 'name_ar': 'الأحياء', 'icon': 'biology', 'color': '#7BE07A', 'sort_order': 2},
    {'id': 'other', 'grade_id': 'g7', 'branch_id': null, 'name_ar': 'مادة صف ثاني', 'icon': 'book', 'color': '#FFFFFF', 'sort_order': 1},
  ]);
  await repo.replaceContent('chapters', [
    {'id': 'ch1', 'subject_id': 'math', 'title': 'الأعداد المركبة', 'sort_order': 1},
  ]);
  await repo.replaceContent('topics', [
    {'id': 't1', 'chapter_id': 'ch1', 'title': 'تعريف العدد المركب', 'difficulty': 1, 'sort_order': 1},
    {'id': 't2', 'chapter_id': 'ch1', 'title': 'العمليات على الأعداد المركبة', 'difficulty': 3, 'sort_order': 2},
  ]);
  await repo.replaceContent('questions', [
    {'id': 'q1', 'grade_id': 'g12', 'subject_id': 'math', 'chapter_id': 'ch1', 'question_type': 'true_false',
     'question_text': 'مربع الوحدة التخيلية i يساوي -1', 'explanation': 'لأن i = √-1', 'source_type': 'practice'},
    {'id': 'q2', 'grade_id': 'g12', 'subject_id': 'math', 'chapter_id': 'ch1', 'question_type': 'multiple_choice',
     'question_text': 'ناتج (2+3i)+(1-i) هو', 'source_type': 'practice'},
  ]);
  await repo.replaceContent('question_options', [
    {'id': 'o1', 'question_id': 'q1', 'option_text': 'صح', 'is_correct': true, 'sort_order': 1},
    {'id': 'o2', 'question_id': 'q1', 'option_text': 'غلط', 'is_correct': false, 'sort_order': 2},
    {'id': 'o3', 'question_id': 'q2', 'option_text': '3+2i', 'is_correct': true, 'sort_order': 1},
    {'id': 'o4', 'question_id': 'q2', 'option_text': '3+4i', 'is_correct': false, 'sort_order': 2},
  ]);
}

Future<void> completeOnboarding(Repository repo, {String branch = 'b-app'}) async {
  final p = repo.profile
    ..displayName = 'علي'
    ..stageId = 'st-p'
    ..gradeId = 'g12'
    ..branchId = branch
    ..yearId = 'y26'
    ..gradeCode = 'grade_12'
    ..branchCode = branch == 'b-app' ? 'applied' : 'biological';
  await repo.saveProfile(p);
  await repo.setKv('auth_mode', 'local');
  await repo.setKv('onboarding_done', '1');
}

List<Override> overridesFor(Repository repo) => [
      repositoryProvider.overrideWith((ref) => repo),
      backendProvider.overrideWith((ref) => Backend(repo)),
      notificationsProvider.overrideWithValue(NotificationService()),
    ];

/// Simulates an app restart: a brand-new Repository reading the same database.
Future<Repository> makeRepoFrom(Repository old) async {
  final repo = Repository(old.db);
  await repo.load();
  return repo;
}
