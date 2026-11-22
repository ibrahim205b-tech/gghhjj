// Typed views over rows that use the exact server column names, so a row can
// travel between SQLite, Dart and Supabase without mapping code.

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String hhmm(int minutesOfDay) =>
    '${(minutesOfDay ~/ 60).toString().padLeft(2, '0')}:${(minutesOfDay % 60).toString().padLeft(2, '0')}';
int minutesOf(String? time) {
  if (time == null || !time.contains(':')) return 0;
  final p = time.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

abstract class DbRow {
  DbRow(this.m);
  final Map<String, dynamic> m;
  String get id => m['id'].toString();
  DateTime? get deletedAt => _dt(m['deleted_at']);
}

// ---------------------------------------------------------------------------
// Academic structure (content)
// ---------------------------------------------------------------------------
class Stage extends DbRow {
  Stage(super.m);
  String get code => m['code'] as String;
  String get nameAr => m['name_ar'] as String;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class Grade extends DbRow {
  Grade(super.m);
  String get stageId => m['stage_id'] as String;
  String get code => m['code'] as String;
  String get nameAr => m['name_ar'] as String;
  bool get hasBranches => m['has_branches'] == true;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class Branch extends DbRow {
  Branch(super.m);
  String get gradeId => m['grade_id'] as String;
  String get code => m['code'] as String;
  String get nameAr => m['name_ar'] as String;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class AcademicYear extends DbRow {
  AcademicYear(super.m);
  String get label => m['label'] as String;
  bool get isCurrent => m['is_current'] == true;
}

class Subject extends DbRow {
  Subject(super.m);
  String get gradeId => m['grade_id'] as String;
  String? get branchId => m['branch_id'] as String?;
  String? get yearId => m['year_id'] as String?;
  String get nameAr => m['name_ar'] as String;
  String get icon => m['icon'] as String? ?? 'book';
  String get color => m['color'] as String? ?? '#3DA9FC';
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class Chapter extends DbRow {
  Chapter(super.m);
  String get subjectId => m['subject_id'] as String;
  String get title => m['title'] as String;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class Topic extends DbRow {
  Topic(super.m);
  String get chapterId => m['chapter_id'] as String;
  String get title => m['title'] as String;
  int get difficulty => (m['difficulty'] as num?)?.toInt() ?? 2;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

// ---------------------------------------------------------------------------
// Published content
// ---------------------------------------------------------------------------
enum QuestionType { multipleChoice, trueFalse, shortAnswer }

class QuestionOption extends DbRow {
  QuestionOption(super.m);
  String get questionId => m['question_id'] as String;
  String get text => m['option_text'] as String;
  bool get isCorrect => m['is_correct'] == true;
  int get sortOrder => (m['sort_order'] as num?)?.toInt() ?? 0;
}

class Question extends DbRow {
  Question(super.m, this.options);
  final List<QuestionOption> options;
  String get gradeId => m['grade_id'] as String;
  String get subjectId => m['subject_id'] as String;
  String? get chapterId => m['chapter_id'] as String?;
  String? get topicId => m['topic_id'] as String?;
  QuestionType get type => switch (m['question_type']) {
        'true_false' => QuestionType.trueFalse,
        'short_answer' => QuestionType.shortAnswer,
        _ => QuestionType.multipleChoice,
      };
  String get text => m['question_text'] as String;
  String? get imagePath => m['image_path'] as String?;
  String? get answerText => m['answer_text'] as String?;
  String? get explanation => m['explanation'] as String?;
  int get difficulty => (m['difficulty'] as num?)?.toInt() ?? 2;
  String? get source => m['source'] as String?;
  String get sourceType => m['source_type'] as String? ?? 'practice';
  int? get year => (m['question_year'] as num?)?.toInt();
  bool get isOfficial => sourceType == 'official_ministerial';
}

class LibraryFile extends DbRow {
  LibraryFile(super.m);
  String? get categoryId => m['category_id'] as String?;
  String? get subjectId => m['subject_id'] as String?;
  String? get chapterId => m['chapter_id'] as String?;
  String get title => m['title'] as String;
  String? get description => m['description'] as String?;
  String get storagePath => m['storage_path'] as String;
  String? get coverPath => m['cover_path'] as String?;
  String get mimeType => m['mime_type'] as String;
  int get sizeBytes => (m['size_bytes'] as num?)?.toInt() ?? 0;
  DateTime? get publishedAt => _dt(m['publish_at']) ?? _dt(m['created_at']);
  bool get isPdf => mimeType == 'application/pdf';
}

class Motivation extends DbRow {
  Motivation(super.m);
  String? get title => m['title'] as String?;
  String get body => m['body'] as String;
  String? get imagePath => m['image_path'] as String?;
  String? get author => m['author'] as String?;
  bool get authorVerified => m['author_verified'] == true;
  DateTime? get showOn => _date(m['show_on']);
  DateTime get publishedAt => _dt(m['publish_at']) ?? _dt(m['created_at']) ?? DateTime(2000);
}

enum DisplayFrequency { once, untilAcknowledged, everyLaunch }

class Announcement extends DbRow {
  Announcement(super.m);
  String get kind => m['kind'] as String? ?? 'general';
  String get title => m['title'] as String;
  String? get description => m['description'] as String?;
  String? get imagePath => m['image_path'] as String?;
  String? get actionLabel => m['action_label'] as String?;
  String? get actionUrl => m['action_url'] as String?;
  String? get telegramUrl => m['telegram_url'] as String?;
  int get priority => (m['priority'] as num?)?.toInt() ?? 0;
  bool get requiresAck => m['requires_acknowledgment'] == true;
  DisplayFrequency get frequency => switch (m['display_frequency']) {
        'until_acknowledged' => DisplayFrequency.untilAcknowledged,
        'every_launch' => DisplayFrequency.everyLaunch,
        _ => DisplayFrequency.once,
      };
  DateTime get publishedAt => _dt(m['publish_at']) ?? _dt(m['created_at']) ?? DateTime(2000);
}

class AppVersionInfo extends DbRow {
  AppVersionInfo(super.m);
  String get versionName => m['version_name'] as String;
  int get buildNumber => (m['build_number'] as num).toInt();
  int get minSupportedBuild => (m['min_supported_build'] as num?)?.toInt() ?? 1;
  bool get isMandatory => m['is_mandatory'] == true;
  String? get description => m['description'] as String?;
  String? get imagePath => m['image_path'] as String?;
  String? get downloadUrl => m['download_url'] as String?;
  String? get playStoreUrl => m['play_store_url'] as String?;
  String? get telegramUrl => m['telegram_url'] as String?;
}

// ---------------------------------------------------------------------------
// Student records (synced)
// ---------------------------------------------------------------------------
class StudyTask extends DbRow {
  StudyTask(super.m);
  String get title => m['title'] as String;
  String? get subjectId => m['subject_id'] as String?;
  String? get topicId => m['topic_id'] as String?;
  DateTime? get dueDate => _date(m['due_date']);
  String? get startTime => m['start_time'] as String?;
  String? get endTime => m['end_time'] as String?;
  int? get estimatedMinutes => (m['estimated_minutes'] as num?)?.toInt();
  int get priority => (m['priority'] as num?)?.toInt() ?? 2;
  bool get isDone => m['is_done'] == true;
  DateTime? get doneAt => _dt(m['done_at']);
  String get source => m['source'] as String? ?? 'manual';
}

class StudySession extends DbRow {
  StudySession(super.m);
  String? get subjectId => m['subject_id'] as String?;
  String? get customSubject => m['custom_subject'] as String?;
  String? get title => m['title'] as String?;
  int? get weekday => (m['weekday'] as num?)?.toInt();
  DateTime? get sessionDate => _date(m['session_date']);
  String get startTime => m['start_time'] as String;
  String get endTime => m['end_time'] as String;
  int get breakMinutes => (m['break_minutes'] as num?)?.toInt() ?? 0;
  bool get repeatsWeekly => m['repeats_weekly'] == true;
  String? get note => m['note'] as String?;
  List<String> get completedDates => ((m['completed_dates'] as List?) ?? const []).map((e) => e.toString()).toList();
  int get actualMinutes => (m['actual_minutes'] as num?)?.toInt() ?? 0;
  int get plannedMinutes => (minutesOf(endTime) - minutesOf(startTime) - breakMinutes).clamp(0, 1440);
  bool occursOn(DateTime day) =>
      repeatsWeekly ? weekday == day.weekday : (sessionDate != null && dayOnly(sessionDate!) == dayOnly(day));
  bool doneOn(DateTime day) => completedDates.contains(isoDate(day));
}

class ExamItem extends DbRow {
  ExamItem(super.m);
  bool get isOfficial => m['is_official'] == true;
  String get title => m['title'] as String;
  String? get subjectId => m['subject_id'] as String?;
  DateTime get examAt => _dt(m['exam_at'])!;
  String? get sourceUrl => m['source_url'] as String?;
  double? get score => _num(m['score']);
  double? get maxScore => _num(m['max_score']);
  double? get targetScore => _num(m['target_score']);
  String? get note => m['note'] as String?;
  DateTime? get verifiedAt => _dt(m['verified_at']);
}

enum TopicStatus { notStarted, inProgress, completed, needsRevision }

TopicStatus topicStatusFrom(String? s) => switch (s) {
      'in_progress' => TopicStatus.inProgress,
      'completed' => TopicStatus.completed,
      'needs_revision' => TopicStatus.needsRevision,
      _ => TopicStatus.notStarted,
    };

String topicStatusDb(TopicStatus s) => switch (s) {
      TopicStatus.notStarted => 'not_started',
      TopicStatus.inProgress => 'in_progress',
      TopicStatus.completed => 'completed',
      TopicStatus.needsRevision => 'needs_revision',
    };

class TopicProgress extends DbRow {
  TopicProgress(super.m);
  String get topicId => m['topic_id'] as String;
  TopicStatus get status => topicStatusFrom(m['status'] as String?);
  bool get isDifficult => m['is_difficult'] == true;
  String? get note => m['note'] as String?;
}

class StudyLog extends DbRow {
  StudyLog(super.m);
  DateTime get date => _date(m['log_date'])!;
  int get minutes => (m['minutes'] as num).toInt();
  String? get subjectId => m['subject_id'] as String?;
}

class Note extends DbRow {
  Note(super.m);
  String? get title => m['title'] as String?;
  String get body => m['body'] as String? ?? '';
  bool get pinned => m['is_pinned'] == true;
  DateTime get modified => _dt(m['client_modified_at']) ?? DateTime(2000);
}

class Goal extends DbRow {
  Goal(super.m);
  String get period => m['period'] as String;
  String get title => m['title'] as String;
  double get target => _num(m['target_value']) ?? 1;
  double get current => _num(m['current_value']) ?? 0;
  String get unit => m['unit'] as String? ?? 'count';
  DateTime get startsOn => _date(m['starts_on'])!;
  DateTime get endsOn => _date(m['ends_on'])!;
  double get ratio => target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();
}

class Expense extends DbRow {
  Expense(super.m);
  String get title => m['title'] as String;
  double get amount => _num(m['amount_iqd']) ?? 0;
  String get category => m['category'] as String? ?? 'other';
  DateTime get spentOn => _date(m['spent_on'])!;
}

class ExamAttempt extends DbRow {
  ExamAttempt(super.m);
  String? get subjectId => m['subject_id'] as String?;
  String get mode => m['mode'] as String? ?? 'untimed';
  DateTime get startedAt => _dt(m['started_at'])!;
  int get total => (m['total_questions'] as num?)?.toInt() ?? 0;
  int get correct => (m['correct_count'] as num?)?.toInt() ?? 0;
  double? get scorePercent => _num(m['score_percent']);
}

class StudentAnswer extends DbRow {
  StudentAnswer(super.m);
  String get attemptId => m['attempt_id'] as String;
  String get questionId => m['question_id'] as String;
  String? get selectedOptionId => m['selected_option_id'] as String?;
  String? get textAnswer => m['text_answer'] as String?;
  bool get isCorrect => m['is_correct'] == true;
}
