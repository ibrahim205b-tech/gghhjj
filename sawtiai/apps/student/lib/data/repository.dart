import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import 'local_db.dart';
import 'models.dart';

/// Server tables owned by the student (pushed and pulled).
const ownedTables = [
  'student_subject_progress', 'study_sessions', 'study_tasks', 'exams', 'student_notes', 'student_goals',
  'student_achievements', 'student_expenses', 'study_logs', 'user_preferences', 'exam_attempts',
  'student_answers', 'saved_questions',
];

/// Admin-published tables cached for offline use (pulled only).
const contentTables = [
  'academic_stages', 'grades', 'academic_branches', 'academic_years', 'subjects', 'chapters', 'topics',
  'questions', 'question_options', 'library_categories', 'library_files', 'daily_motivations', 'announcements',
  'official_exams', 'universities', 'colleges', 'specializations', 'admission_information', 'app_versions',
  'app_settings',
];

class LocalProfile {
  LocalProfile({
    this.displayName = '',
    this.avatarUrl,
    this.stageId,
    this.gradeId,
    this.branchId,
    this.yearId,
    this.governorate,
    this.gradeCode,
    this.branchCode,
  });
  String displayName;
  String? avatarUrl;
  String? stageId;
  String? gradeId;
  String? branchId;
  String? yearId;
  String? governorate;
  // Codes let a profile chosen offline (bundled structure) map onto server ids.
  String? gradeCode;
  String? branchCode;

  bool get complete => displayName.trim().isNotEmpty && gradeId != null && stageId != null;

  Map<String, dynamic> toJson() => {
        'display_name': displayName, 'avatar_url': avatarUrl, 'stage_id': stageId, 'grade_id': gradeId,
        'branch_id': branchId, 'year_id': yearId, 'governorate': governorate, 'grade_code': gradeCode,
        'branch_code': branchCode,
      };

  factory LocalProfile.fromJson(Map<String, dynamic> j) => LocalProfile(
        displayName: j['display_name'] as String? ?? '',
        avatarUrl: j['avatar_url'] as String?,
        stageId: j['stage_id'] as String?,
        gradeId: j['grade_id'] as String?,
        branchId: j['branch_id'] as String?,
        yearId: j['year_id'] as String?,
        governorate: j['governorate'] as String?,
        gradeCode: j['grade_code'] as String?,
        branchCode: j['branch_code'] as String?,
      );
}

class Repository extends ChangeNotifier {
  Repository(this.db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LocalDb db;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  final Map<String, Map<String, Map<String, dynamic>>> _records = {};
  final Map<String, List<Map<String, dynamic>>> _content = {};
  final Map<String, String> _kv = {};
  final Map<String, Map<String, Object?>> _downloads = {};
  Map<String, dynamic>? _bundledStructure;

  String? userId; // set when signed in with a cloud account
  bool loaded = false;
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  DateTime now() => _clock();
  String newId() => _uuid.v4();

  /// Deterministic UUID for records derived from something else (so the same
  /// event never creates two rows, even across devices).
  String stableId(String name) => _uuid.v5(Namespace.url.value, 'enjaz:$name');

  Future<void> load() async {
    for (final r in await db.allRecords()) {
      _records.putIfAbsent(r['tbl'] as String, () => {})[r['id'] as String] =
          (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>();
    }
    for (final r in await db.allContent()) {
      _content.putIfAbsent(r['tbl'] as String, () => []).add((jsonDecode(r['json'] as String) as Map).cast<String, dynamic>());
    }
    _kv.addAll(await db.allKv());
    for (final d in await db.allDownloads()) {
      _downloads[d['file_id'] as String] = d;
    }
    try {
      _bundledStructure = (jsonDecode(await rootBundle.loadString('assets/default_structure.json')) as Map).cast<String, dynamic>();
    } catch (_) {
      _bundledStructure = null;
    }
    loaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Key-value
  // ---------------------------------------------------------------------------
  String? kv(String key) => _kv[key];
  Future<void> setKv(String key, String? value) async {
    if (value == null) {
      _kv.remove(key);
    } else {
      _kv[key] = value;
    }
    await db.setKv(key, value);
    notifyListeners();
  }

  bool get onboardingDone => _kv['onboarding_done'] == '1';
  String get authMode => _kv['auth_mode'] ?? 'none'; // none | local | cloud

  LocalProfile get profile =>
      _kv['profile'] == null ? LocalProfile() : LocalProfile.fromJson((jsonDecode(_kv['profile']!) as Map).cast<String, dynamic>());
  Future<void> saveProfile(LocalProfile p) => setKv('profile', jsonEncode(p.toJson()));

  // ---------------------------------------------------------------------------
  // Generic record writes (always local first, marked dirty for sync)
  // ---------------------------------------------------------------------------
  Iterable<Map<String, dynamic>> records(String tbl) =>
      (_records[tbl]?.values ?? const <Map<String, dynamic>>[]).where((r) => r['deleted_at'] == null);

  Map<String, dynamic>? record(String tbl, String id) {
    final r = _records[tbl]?[id];
    return r == null || r['deleted_at'] != null ? null : r;
  }

  Future<Map<String, dynamic>> save(String tbl, Map<String, dynamic> values) async {
    final stamp = now().toUtc().toIso8601String();
    final row = Map<String, dynamic>.from(values);
    row['id'] ??= newId();
    row['client_modified_at'] = stamp;
    if (userId != null) row['user_id'] = userId;
    _records.putIfAbsent(tbl, () => {})[row['id'] as String] = row;
    await db.putRecord(tbl, row, dirty: true);
    notifyListeners();
    return row;
  }

  Future<void> remove(String tbl, String id) async {
    final row = _records[tbl]?[id];
    if (row == null) return;
    final copy = Map<String, dynamic>.from(row)
      ..['deleted_at'] = now().toUtc().toIso8601String()
      ..['client_modified_at'] = now().toUtc().toIso8601String();
    _records[tbl]![id] = copy;
    await db.putRecord(tbl, copy, dirty: true);
    notifyListeners();
  }

  /// Applied by the sync engine for rows coming from the server.
  /// [dirtyKeys] holds "table/id" of local rows not yet pushed.
  Future<void> applyRemote(String tbl, Map<String, dynamic> row, {Set<String> dirtyKeys = const {}}) async {
    final id = row['id'].toString();
    final local = _records[tbl]?[id];
    if (local != null) {
      final localStamp = DateTime.tryParse(local['client_modified_at']?.toString() ?? '');
      final remoteStamp = DateTime.tryParse(row['client_modified_at']?.toString() ?? '');
      final dirty = dirtyKeys.contains('$tbl/$id');
      if (dirty && localStamp != null && remoteStamp != null && localStamp.isAfter(remoteStamp)) {
        return; // our unsynced change is newer; it will be pushed
      }
    }
    _records.putIfAbsent(tbl, () => {})[id] = row;
    await db.putRecord(tbl, row, dirty: false);
  }

  Future<void> replaceContent(String tbl, List<Map<String, dynamic>> rows) async {
    _content[tbl] = rows;
    await db.replaceContent(tbl, rows);
  }

  List<Map<String, dynamic>> content(String tbl) => _content[tbl] ?? const [];

  void notify() => notifyListeners();

  // ---------------------------------------------------------------------------
  // Academic structure (server cache, falling back to the bundled structure)
  // ---------------------------------------------------------------------------
  List<Map<String, dynamic>> _structure(String tbl) {
    final c = content(tbl);
    if (c.isNotEmpty) return c;
    return ((_bundledStructure?[tbl] as List?) ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  bool get usingBundledStructure => content('grades').isEmpty;

  List<Stage> get stages => _structure('academic_stages').map(Stage.new).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Grade> gradesOf(String stageId) =>
      _structure('grades').map(Grade.new).where((g) => g.stageId == stageId).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Grade> get allGrades => _structure('grades').map(Grade.new).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Branch> branchesOf(String gradeId) =>
      _structure('academic_branches').map(Branch.new).where((b) => b.gradeId == gradeId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<AcademicYear> get years => _structure('academic_years').map(AcademicYear.new).toList();
  Grade? grade(String? id) => allGrades.where((g) => g.id == id).firstOrNull;
  Branch? branch(String? id) => _structure('academic_branches').map(Branch.new).where((b) => b.id == id).firstOrNull;

  /// After the first sync, re-point a profile picked from the bundled
  /// structure to the server ids (matched by code).
  Future<void> reconcileProfileIds() async {
    final p = profile;
    if (p.gradeCode == null) return;
    final g = content('grades').map(Grade.new).where((g) => g.code == p.gradeCode).firstOrNull;
    if (g == null || g.id == p.gradeId) return;
    p.gradeId = g.id;
    p.stageId = g.stageId;
    p.branchId = p.branchCode == null
        ? null
        : content('academic_branches').map(Branch.new).where((b) => b.gradeId == g.id && b.code == p.branchCode).firstOrNull?.id;
    final cur = content('academic_years').map(AcademicYear.new).where((y) => y.isCurrent).firstOrNull;
    p.yearId = cur?.id;
    await saveProfile(p);
  }

  /// Subjects for the student's grade + branch + year (never mixed).
  List<Subject> get mySubjects {
    final p = profile;
    return content('subjects')
        .map(Subject.new)
        .where((s) =>
            s.gradeId == p.gradeId &&
            (s.branchId == null || s.branchId == p.branchId) &&
            (s.yearId == null || s.yearId == p.yearId))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Subject? subject(String? id) => content('subjects').map(Subject.new).where((s) => s.id == id).firstOrNull;
  List<Chapter> chaptersOf(String subjectId) =>
      content('chapters').map(Chapter.new).where((c) => c.subjectId == subjectId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Topic> topicsOf(String chapterId) =>
      content('topics').map(Topic.new).where((t) => t.chapterId == chapterId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Topic> topicsOfSubject(String subjectId) => [for (final c in chaptersOf(subjectId)) ...topicsOf(c.id)];

  // ---------------------------------------------------------------------------
  // Published content
  // ---------------------------------------------------------------------------
  List<Question> questions({String? subjectId, String? chapterId, String? topicId}) {
    final opts = <String, List<QuestionOption>>{};
    for (final o in content('question_options').map(QuestionOption.new)) {
      opts.putIfAbsent(o.questionId, () => []).add(o);
    }
    final p = profile;
    return content('questions')
        .where((q) => q['grade_id'] == p.gradeId && (q['branch_id'] == null || q['branch_id'] == p.branchId))
        .map((q) => Question(q, (opts[q['id']] ?? [])..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))))
        .where((q) =>
            (subjectId == null || q.subjectId == subjectId) &&
            (chapterId == null || q.chapterId == chapterId) &&
            (topicId == null || q.topicId == topicId))
        .toList();
  }

  Question? question(String id) => questions().where((q) => q.id == id).firstOrNull;

  List<LibraryFile> get libraryFiles => content('library_files').map(LibraryFile.new).toList()
    ..sort((a, b) => (b.publishedAt ?? DateTime(2000)).compareTo(a.publishedAt ?? DateTime(2000)));
  List<Map<String, dynamic>> get libraryCategories => content('library_categories');

  List<Motivation> get motivations =>
      content('daily_motivations').map(Motivation.new).toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

  Motivation? get todaysMotivation {
    final today = dayOnly(now());
    final list = motivations;
    return list.where((m) => m.showOn != null && dayOnly(m.showOn!) == today).firstOrNull ??
        list.where((m) => m.showOn == null).firstOrNull ??
        list.firstOrNull;
  }

  List<Announcement> get announcements =>
      content('announcements').map(Announcement.new).toList()
        ..sort((a, b) => b.priority != a.priority ? b.priority.compareTo(a.priority) : b.publishedAt.compareTo(a.publishedAt));

  AppVersionInfo? get latestVersion {
    final v = content('app_versions').map(AppVersionInfo.new).toList()..sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
    return v.firstOrNull;
  }

  dynamic setting(String key) {
    final row = content('app_settings').where((s) => s['key'] == key).firstOrNull;
    if (row != null) return row['value'];
    return ((_bundledStructure?['settings'] as Map?) ?? const {})[key];
  }

  // ---------------------------------------------------------------------------
  // Student data views
  // ---------------------------------------------------------------------------
  List<StudyTask> get tasks => records('study_tasks').map(StudyTask.new).toList();
  List<StudySession> get sessions => records('study_sessions').map(StudySession.new).toList();
  List<ExamItem> get exams => [
        ...records('exams').map(ExamItem.new),
        ...content('official_exams').map(ExamItem.new),
      ]..sort((a, b) => a.examAt.compareTo(b.examAt));
  List<StudyLog> get studyLogs => records('study_logs').map(StudyLog.new).toList();
  List<Note> get notes => records('student_notes').map(Note.new).toList()
    ..sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : b.modified.compareTo(a.modified));
  List<Goal> get goals => records('student_goals').map(Goal.new).toList();
  List<Expense> get expenses => records('student_expenses').map(Expense.new).toList()
    ..sort((a, b) => b.spentOn.compareTo(a.spentOn));
  List<ExamAttempt> get attempts => records('exam_attempts').map(ExamAttempt.new).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  List<StudentAnswer> answersOf(String attemptId) =>
      records('student_answers').map(StudentAnswer.new).where((a) => a.attemptId == attemptId).toList();
  Set<String> get savedQuestionIds => records('saved_questions').map((r) => r['question_id'] as String).toSet();
  Set<String> get achievementCodes => records('student_achievements').map((r) => r['code'] as String).toSet();

  Map<String, TopicProgress> get topicProgress =>
      {for (final r in records('student_subject_progress')) r['topic_id'] as String: TopicProgress(r)};

  Future<void> setTopicStatus(String topicId, {TopicStatus? status, bool? difficult, String? note}) async {
    final existing = records('student_subject_progress').where((r) => r['topic_id'] == topicId).firstOrNull;
    final row = Map<String, dynamic>.from(existing ??
        {'id': stableId('progress:$topicId:${userId ?? 'local'}'), 'topic_id': topicId, 'status': 'not_started', 'is_difficult': false});
    if (status != null) {
      row['status'] = topicStatusDb(status);
      row['completed_at'] = status == TopicStatus.completed ? now().toUtc().toIso8601String() : null;
      if (status == TopicStatus.needsRevision) row['revision_count'] = ((row['revision_count'] as num?) ?? 0) + 1;
    }
    if (difficult != null) row['is_difficult'] = difficult;
    if (note != null) row['note'] = note;
    await save('student_subject_progress', row);
  }

  double subjectCompletion(String subjectId) {
    final topics = topicsOfSubject(subjectId);
    if (topics.isEmpty) return 0;
    final prog = topicProgress;
    final done = topics.where((t) => prog[t.id]?.status == TopicStatus.completed).length;
    return done / topics.length;
  }

  Map<String, dynamic> get preferences => record('user_preferences', 'prefs') ??
      {'id': 'prefs', 'notify_motivation': true, 'notify_study': true, 'notify_exams': true,
       'notify_announcements': true, 'theme_mode': 'dark', 'daily_study_hours': 3, 'cloud_sync_enabled': true};

  Future<void> setPreference(String key, Object value) => save('user_preferences', {...preferences, key: value, 'id': 'prefs'});

  // ---------------------------------------------------------------------------
  // Downloads
  // ---------------------------------------------------------------------------
  Map<String, Object?>? download(String fileId) => _downloads[fileId];
  List<Map<String, Object?>> get downloads => _downloads.values.toList();
  Future<void> putDownload(Map<String, Object?> row) async {
    _downloads[row['file_id'] as String] = row;
    await db.putDownload(row);
    notifyListeners();
  }

  Future<void> updateDownload(String fileId, Map<String, Object?> values) async {
    final d = _downloads[fileId];
    if (d == null) return;
    _downloads[fileId] = {...d, ...values};
    await db.updateDownload(fileId, values);
    notifyListeners();
  }

  Future<void> removeDownload(String fileId) async {
    _downloads.remove(fileId);
    await db.deleteDownload(fileId);
    notifyListeners();
  }

  /// Full local export (works offline).
  Map<String, dynamic> exportLocal() => {
        'exported_at': now().toUtc().toIso8601String(),
        'profile': profile.toJson(),
        for (final t in ownedTables) t: records(t).toList(),
      };

  Future<void> wipeAll() async {
    await db.wipe();
    _records.clear();
    _content.clear();
    _kv.clear();
    _downloads.clear();
    userId = null;
    notifyListeners();
  }
}
