import 'package:enjaz_student/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saves locally, marks dirty, survives reload (offline persistence)', () async {
    final repo = await makeRepo();
    final row = await repo.save('study_tasks', {'title': 'مراجعة', 'priority': 3, 'is_done': false});
    expect(repo.tasks.single.title, 'مراجعة');
    final dirty = await repo.db.dirtyRecords();
    expect(dirty.single['id'], row['id']);
    // Re-open the same database as the app would after a restart.
    final reopened = await makeRepoFrom(repo);
    expect(reopened.tasks.single.title, 'مراجعة');
  });

  test('delete is a tombstone (so other devices learn about it)', () async {
    final repo = await makeRepo();
    final row = await repo.save('student_notes', {'title': 'x', 'body': 'y'});
    await repo.remove('student_notes', row['id'] as String);
    expect(repo.notes, isEmpty);
    final dirty = await repo.db.dirtyRecords();
    expect(dirty.single['deleted'], 1);
  });

  test('remote rows never overwrite a newer unsynced local change', () async {
    var t = DateTime.utc(2026, 11, 22, 10);
    final repo = await makeRepo(clock: () => t);
    final row = await repo.save('study_tasks', {'title': 'local newer', 'is_done': false});
    final dirtyKeys = {'study_tasks/${row['id']}'};
    await repo.applyRemote('study_tasks',
        {...row, 'title': 'remote older', 'client_modified_at': DateTime.utc(2026, 11, 22, 9).toIso8601String()},
        dirtyKeys: dirtyKeys);
    expect(repo.tasks.single.title, 'local newer');
    await repo.applyRemote('study_tasks',
        {...row, 'title': 'remote newer', 'client_modified_at': DateTime.utc(2026, 11, 22, 11).toIso8601String()},
        dirtyKeys: dirtyKeys);
    expect(repo.tasks.single.title, 'remote newer');
  });

  test('subjects are filtered to the student grade + branch (never mixed)', () async {
    final repo = await makeRepo();
    await seedContent(repo);
    await completeOnboarding(repo, branch: 'b-app');
    expect(repo.mySubjects.map((s) => s.id), ['math']);
    await completeOnboarding(repo, branch: 'b-bio');
    expect(repo.mySubjects.map((s) => s.id), ['math', 'bio']);
    expect(repo.questions().length, 2);
  });

  test('topic progress drives subject completion', () async {
    final repo = await makeRepo();
    await seedContent(repo);
    await completeOnboarding(repo);
    expect(repo.subjectCompletion('math'), 0);
    await repo.setTopicStatus('t1', status: TopicStatus.completed);
    expect(repo.subjectCompletion('math'), 0.5);
    await repo.setTopicStatus('t1', difficult: true);
    expect(repo.topicProgress['t1']!.status, TopicStatus.completed);
    expect(repo.topicProgress['t1']!.isDifficult, isTrue);
  });

  test('offline profile on bundled structure maps to server ids after sync', () async {
    final repo = await makeRepo();
    expect(repo.usingBundledStructure, isTrue);
    expect(repo.stages.length, 2);
    final g = repo.allGrades.firstWhere((g) => g.code == 'grade_12');
    final b = repo.branchesOf(g.id).firstWhere((b) => b.code == 'applied');
    await repo.saveProfile(repo.profile
      ..displayName = 'سارة'
      ..stageId = g.stageId
      ..gradeId = g.id
      ..branchId = b.id
      ..gradeCode = g.code
      ..branchCode = b.code);
    await seedContent(repo); // the first sync delivered the real structure
    await repo.reconcileProfileIds();
    expect(repo.profile.gradeId, 'g12');
    expect(repo.profile.branchId, 'b-app');
    expect(repo.profile.yearId, 'y26');
  });

  test('stable ids are deterministic and valid UUIDs', () async {
    final repo = await makeRepo();
    final a = repo.stableId('achievement:first_task:u1');
    expect(a, repo.stableId('achievement:first_task:u1'));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
  });

  test('export contains everything the student owns', () async {
    final repo = await makeRepo();
    await repo.save('student_expenses', {'title': 'نقل', 'amount_iqd': 1000, 'spent_on': '2026-11-22'});
    final e = repo.exportLocal();
    expect((e['student_expenses'] as List).single['title'], 'نقل');
  });

  test('wipe removes all local data (sign out / account deletion)', () async {
    final repo = await makeRepo();
    await repo.save('study_tasks', {'title': 'x'});
    await repo.setKv('onboarding_done', '1');
    await repo.wipeAll();
    expect(repo.tasks, isEmpty);
    expect(repo.onboardingDone, isFalse);
  });
}
