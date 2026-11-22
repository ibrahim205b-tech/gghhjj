import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../logic/quiz.dart';

class QuizConfig {
  QuizConfig({this.subjectId, this.chapterId, required this.mode, required this.questionIds});
  final String? subjectId;
  final String? chapterId;
  final String mode; // timed | untimed | review_mistakes
  final List<String> questionIds;
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------
class QuizSetupScreen extends ConsumerStatefulWidget {
  const QuizSetupScreen({super.key});

  @override
  ConsumerState<QuizSetupScreen> createState() => _QuizSetupScreenState();
}

class _QuizSetupScreenState extends ConsumerState<QuizSetupScreen> {
  String? _subject, _chapter;
  bool _timed = false;
  double _count = 10;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final subjects = repo.mySubjects;
    _subject ??= subjects.firstOrNull?.id;
    final available = _subject == null ? <Question>[] : repo.questions(subjectId: _subject, chapterId: _chapter);
    final wrongIds = repo.records('student_answers').where((a) => a['is_correct'] == false).map((a) => a['question_id'] as String).toSet();
    return EnjazPage(
      title: l.questionBank,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _subject,
          decoration: InputDecoration(labelText: l.chooseSubject),
          items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.nameAr))],
          onChanged: (v) => setState(() {
            _subject = v;
            _chapter = null;
          }),
        ),
        const SizedBox(height: 12),
        if (_subject != null)
          DropdownButtonFormField<String?>(
            initialValue: _chapter,
            decoration: InputDecoration(labelText: l.chooseChapter),
            items: [
              DropdownMenuItem(value: null, child: Text(l.allChapters)),
              for (final c in repo.chaptersOf(_subject!)) DropdownMenuItem(value: c.id, child: Text(c.title)),
            ],
            onChanged: (v) => setState(() => _chapter = v),
          ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l.untimedTest), icon: const Icon(Icons.all_inclusive_rounded)),
            ButtonSegment(value: true, label: Text(l.timedTest), icon: const Icon(Icons.timer_rounded)),
          ],
          selected: {_timed},
          onSelectionChanged: (v) => setState(() => _timed = v.first),
        ),
        const SizedBox(height: 16),
        if (available.isEmpty)
          EmptyState(icon: Icons.quiz_outlined, message: l.noQuestions)
        else ...[
          Text('${l.questionsCount}: ${_count.round().clamp(1, available.length)} / ${available.length}'),
          Slider(
            value: _count.clamp(1, available.length.toDouble()),
            min: 1,
            max: available.length.toDouble(),
            divisions: available.length > 1 ? available.length - 1 : null,
            onChanged: (v) => setState(() => _count = v),
          ),
          const SizedBox(height: 12),
          GlowButton(
            key: const Key('start_quiz'),
            label: l.startTest,
            gradient: EnjazColors.studyGradient,
            icon: Icons.play_arrow_rounded,
            onPressed: () {
              final qs = [...available]..shuffle();
              context.push('/quiz/run', extra: QuizConfig(
                subjectId: _subject, chapterId: _chapter, mode: _timed ? 'timed' : 'untimed',
                questionIds: qs.take(_count.round().clamp(1, qs.length)).map((q) => q.id).toList(),
              ));
            },
          ),
        ],
        const SizedBox(height: 12),
        if (wrongIds.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => context.push('/quiz/run', extra: QuizConfig(
                mode: 'review_mistakes', questionIds: wrongIds.where((id) => repo.question(id) != null).take(30).toList())),
            icon: const Icon(Icons.replay_rounded),
            label: Text(l.retryMistakes),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------
class QuizRunScreen extends ConsumerStatefulWidget {
  const QuizRunScreen({super.key, required this.config});
  final QuizConfig config;

  @override
  ConsumerState<QuizRunScreen> createState() => _QuizRunScreenState();
}

class _QuizRunScreenState extends ConsumerState<QuizRunScreen> {
  late final List<Question> _qs;
  final Map<String, AnswerInput> _answers = {};
  final _text = TextEditingController();
  int _i = 0;
  late final DateTime _started;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(repositoryProvider);
    _qs = widget.config.questionIds.map(repo.question).whereType<Question>().toList();
    _started = repo.now();
    if (widget.config.mode == 'timed') {
      _secondsLeft = _qs.length * 60;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) {
          _timer?.cancel();
          showEnjazSnack(context, context.l10n.timeUp);
          _submit(force: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _go(int i) {
    final q = _qs[_i];
    if (q.type == QuestionType.shortAnswer) _answers[q.id] = AnswerInput(text: _text.text);
    setState(() => _i = i);
    final nq = _qs[i];
    _text.text = nq.type == QuestionType.shortAnswer ? (_answers[nq.id]?.text ?? '') : '';
  }

  Future<void> _submit({bool force = false}) async {
    if (_submitting) return;
    final l = context.l10n;
    final q = _qs[_i];
    if (q.type == QuestionType.shortAnswer) _answers[q.id] = AnswerInput(text: _text.text);
    final unanswered = _qs.where((q) => _answers[q.id]?.isEmpty ?? true).length;
    if (!force && unanswered > 0) {
      final ok = await confirmDialog(context, title: l.submit, body: l.submitConfirm, ok: l.submit, cancel: l.cancel);
      if (!ok) return;
    }
    _submitting = true;
    _timer?.cancel();
    final repo = ref.read(repositoryProvider);
    final result = grade(_qs, _answers);
    final attempt = await repo.save('exam_attempts', {
      'subject_id': widget.config.subjectId,
      'chapter_id': widget.config.chapterId,
      'mode': widget.config.mode,
      'time_limit_seconds': widget.config.mode == 'timed' ? _qs.length * 60 : null,
      'started_at': _started.toUtc().toIso8601String(),
      'finished_at': repo.now().toUtc().toIso8601String(),
      'total_questions': result.total,
      'correct_count': result.correct,
      'score_percent': double.parse(result.percent.toStringAsFixed(2)),
    });
    for (final q in _qs) {
      final a = _answers[q.id] ?? AnswerInput();
      await repo.save('student_answers', {
        'attempt_id': attempt['id'],
        'question_id': q.id,
        'selected_option_id': a.optionId,
        'text_answer': a.text,
        'is_correct': isCorrect(q, a),
        'answered_at': repo.now().toUtc().toIso8601String(),
      });
    }
    if (mounted) context.pushReplacement('/quiz/result/${attempt['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_qs.isEmpty) return EnjazPage(title: l.questionBank, body: EmptyState(icon: Icons.quiz_outlined, message: l.noQuestions));
    final q = _qs[_i];
    final repo = ref.watch(repositoryProvider);
    final saved = repo.savedQuestionIds.contains(q.id);
    final img = ref.read(backendProvider).publicImageUrl(q.imagePath);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context, title: l.areYouSure, body: l.areYouSure, ok: l.close, cancel: l.cancel);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: EnjazPage(
        title: l.questionNofM(_i + 1, _qs.length),
        actions: [
          if (widget.config.mode == 'timed')
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('${(_secondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: _secondsLeft < 60 ? EnjazColors.danger : null)),
              ),
            ),
          IconButton(
            tooltip: l.saveQuestion,
            icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: saved ? EnjazColors.warning : null),
            onPressed: () => toggleSaved(repo, q.id),
          ),
        ],
        body: ListView(padding: const EdgeInsets.all(16), children: [
          LinearProgressIndicator(value: (_i + 1) / _qs.length, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 14),
          GlassCard(
            blur: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusChip(
                  label: q.isOfficial ? '${l.officialSourceBadge}${q.year != null ? ' ${q.year}' : ''}' : l.practiceBadge,
                  color: q.isOfficial ? EnjazColors.cyan : EnjazColors.violet),
              const SizedBox(height: 10),
              // Official content is shown exactly as published (no rewriting).
              SelectableText(q.text, style: const TextStyle(fontSize: 17, height: 1.7, fontWeight: FontWeight.w600)),
              if (img != null) ...[
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(img, errorBuilder: (_, _, _) => const SizedBox())),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          if (q.type == QuestionType.shortAnswer)
            TextField(key: const Key('short_answer'), controller: _text, decoration: InputDecoration(labelText: l.typeAnswer))
          else
            for (final o in q.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  key: ValueKey('option_${o.id}'),
                  radius: EnjazRadii.tile,
                  gradient: _answers[q.id]?.optionId == o.id ? EnjazColors.planGradient : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => setState(() => _answers[q.id] = AnswerInput(optionId: o.id)),
                  child: Row(children: [
                    Icon(_answers[q.id]?.optionId == o.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        color: _answers[q.id]?.optionId == o.id ? Colors.white : context.mutedText),
                    const SizedBox(width: 12),
                    Expanded(child: Text(o.text, style: TextStyle(color: _answers[q.id]?.optionId == o.id ? Colors.white : null))),
                  ]),
                ),
              ),
          const SizedBox(height: 16),
          Row(children: [
            if (_i > 0) Expanded(child: OutlinedButton(onPressed: () => _go(_i - 1), child: Text(l.back))),
            if (_i > 0) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _i < _qs.length - 1
                  ? GlowButton(key: const Key('next_question'), label: l.next, gradient: EnjazColors.planGradient, onPressed: () => _go(_i + 1))
                  : GlowButton(key: const Key('submit_quiz'), label: l.submit, gradient: EnjazColors.studyGradient, loading: _submitting, onPressed: _submit),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> toggleSaved(Repository repo, String questionId) async {
  final existing = repo.records('saved_questions').where((r) => r['question_id'] == questionId).firstOrNull;
  if (existing != null) {
    await repo.remove('saved_questions', existing['id'] as String);
  } else {
    await repo.save('saved_questions', {
      'id': repo.stableId('saved:$questionId:${repo.userId ?? 'local'}'),
      'question_id': questionId,
      'reason': 'difficult',
    });
  }
}

// ---------------------------------------------------------------------------
// Result / review
// ---------------------------------------------------------------------------
class QuizResultScreen extends ConsumerWidget {
  const QuizResultScreen({super.key, required this.attemptId});
  final String attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final attempt = repo.attempts.where((a) => a.id == attemptId).firstOrNull;
    if (attempt == null) return EnjazPage(title: l.result, body: EmptyState(icon: Icons.error_outline, message: l.errorGeneric));
    final answers = repo.answersOf(attemptId);
    final pct = attempt.scorePercent ?? 0;
    final wrong = answers.where((a) => !a.isCorrect).map((a) => a.questionId).toList();
    return EnjazPage(
      title: l.result,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        GlassCard(
          blur: true,
          child: Column(children: [
            Text(pct >= 90 ? l.congrats : l.result, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text('${pct.round()}%', key: const Key('score_percent'),
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: pct >= 50 ? EnjazColors.success : EnjazColors.danger)),
            Text(l.correctOf(attempt.correct, attempt.total), style: TextStyle(color: context.mutedText)),
            const SizedBox(height: 12),
            EnjazProgressBar(value: pct / 100, showLabel: false, height: 12),
          ]),
        ),
        const SizedBox(height: 12),
        if (wrong.isNotEmpty)
          GlowButton(
            label: l.retryMistakes,
            gradient: EnjazColors.studyGradient,
            icon: Icons.replay_rounded,
            onPressed: () => context.pushReplacement('/quiz/run', extra: QuizConfig(mode: 'review_mistakes', questionIds: wrong)),
          ),
        SectionHeader(title: l.reviewAnswers),
        for (final a in answers) _ReviewCard(answer: a),
      ]),
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.answer});
  final StudentAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final q = repo.question(answer.questionId);
    if (q == null) return const SizedBox.shrink();
    final chosen = q.options.where((o) => o.id == answer.selectedOptionId).firstOrNull?.text ?? answer.textAnswer ?? '—';
    final correct = q.type == QuestionType.shortAnswer
        ? (q.answerText ?? '').split('|').first
        : q.options.where((o) => o.isCorrect).map((o) => o.text).join('، ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(answer.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: answer.isCorrect ? EnjazColors.success : EnjazColors.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(q.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.6))),
            IconButton(
              tooltip: l.saveQuestion,
              icon: Icon(repo.savedQuestionIds.contains(q.id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
              onPressed: () => toggleSaved(repo, q.id),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${l.yourAnswer}: $chosen', style: TextStyle(color: answer.isCorrect ? EnjazColors.success : EnjazColors.danger)),
          if (!answer.isCorrect) Text('${l.correctAnswer}: $correct', style: const TextStyle(color: EnjazColors.success)),
          if (q.explanation?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text('${l.explanation}: ${q.explanation}', style: TextStyle(color: context.mutedText, height: 1.6)),
          ],
          if (q.source != null) Text('${l.source}: ${q.source}', style: TextStyle(color: context.mutedText, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

class QuizHistoryScreen extends ConsumerWidget {
  const QuizHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final list = repo.attempts;
    return EnjazPage(
      title: l.testHistory,
      body: list.isEmpty
          ? EmptyState(icon: Icons.history_rounded, message: l.noQuestions)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final a = list[i];
                return GlassCard(
                  onTap: () => context.push('/quiz/result/${a.id}'),
                  child: Row(children: [
                    Text('${(a.scorePercent ?? 0).round()}%',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: (a.scorePercent ?? 0) >= 50 ? EnjazColors.success : EnjazColors.danger)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(repo.subject(a.subjectId)?.nameAr ?? l.retryMistakes, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${formatDay(l, a.startedAt)} • ${l.correctOf(a.correct, a.total)}', style: TextStyle(fontSize: 12, color: context.mutedText)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class SavedQuestionsScreen extends ConsumerWidget {
  const SavedQuestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final qs = repo.savedQuestionIds.map(repo.question).whereType<Question>().toList();
    return EnjazPage(
      title: l.savedQuestions,
      fab: qs.isEmpty
          ? null
          : FloatingActionButton.extended(
        heroTag: null,
              backgroundColor: EnjazColors.violet,
              foregroundColor: Colors.white,
              onPressed: () => context.push('/quiz/run', extra: QuizConfig(mode: 'untimed', questionIds: qs.map((q) => q.id).toList())),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l.startTest),
            ),
      body: qs.isEmpty
          ? EmptyState(icon: Icons.bookmark_border_rounded, message: l.noQuestions)
          : ListView(padding: const EdgeInsets.all(16), children: [
              for (final q in qs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    child: Row(children: [
                      Expanded(child: Text(q.text, maxLines: 3, overflow: TextOverflow.ellipsis)),
                      IconButton(icon: const Icon(Icons.bookmark_remove_rounded), tooltip: l.delete, onPressed: () => toggleSaved(repo, q.id)),
                    ]),
                  ),
                ),
            ]),
    );
  }
}
