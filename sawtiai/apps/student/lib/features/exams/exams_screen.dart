import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../logic/stats.dart';

class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final now = repo.now();
    final upcoming = repo.exams.where((e) => !dayOnly(e.examAt).isBefore(dayOnly(now))).toList();
    final past = repo.exams.where((e) => dayOnly(e.examAt).isBefore(dayOnly(now))).toList().reversed.toList();
    final scored = past.where((e) => e.score != null && (e.maxScore ?? 0) > 0).map((e) => e.score! * 100 / e.maxScore!).toList();
    final target = past.map((e) => e.targetScore).whereType<double>().lastOrNull ??
        upcoming.map((e) => e.targetScore).whereType<double>().firstOrNull;
    final need = target == null
        ? null
        : requiredScoreForTarget(scoredPercents: scored, remainingExams: upcoming.length, targetPercent: target);

    return EnjazPage(
      title: l.examsTab,
      fab: FloatingActionButton.extended(
        heroTag: null,
        key: const Key('add_exam_fab'),
        backgroundColor: EnjazColors.violet,
        foregroundColor: Colors.white,
        onPressed: () => showExamSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addExam),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
        Row(children: [
          Expanded(child: _QuickCard(icon: Icons.quiz_rounded, label: l.questionBank, onTap: () => context.push('/quiz'))),
          const SizedBox(width: 10),
          Expanded(child: _QuickCard(icon: Icons.bookmark_rounded, label: l.savedQuestions, onTap: () => context.push('/quiz/saved'))),
          const SizedBox(width: 10),
          Expanded(child: _QuickCard(icon: Icons.history_rounded, label: l.testHistory, onTap: () => context.push('/quiz/history'))),
        ]),
        if (need != null && target != null) ...[
          const SizedBox(height: 12),
          GlassCard(
            child: Row(children: [
              const Icon(Icons.calculate_rounded, color: EnjazColors.cyan),
              const SizedBox(width: 10),
              Expanded(child: Text(l.requiredScore(target.toStringAsFixed(0), need.clamp(0, 999).toStringAsFixed(1)))),
            ]),
          ),
        ],
        SectionHeader(title: l.upcomingExams),
        if (upcoming.isEmpty) EmptyState(icon: Icons.event_available_rounded, message: l.noExams),
        for (final e in upcoming) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ExamTile(exam: e, now: now)),
        if (past.isNotEmpty) ...[
          SectionHeader(title: l.examPassed),
          for (final e in past.take(20)) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ExamTile(exam: e, now: now)),
        ],
      ]),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassCard(
        radius: EnjazRadii.tile,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        onTap: onTap,
        child: Column(children: [
          Icon(icon, color: EnjazColors.cyan),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _ExamTile extends ConsumerWidget {
  const _ExamTile({required this.exam, required this.now});
  final ExamItem exam;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    final days = dayOnly(exam.examAt).difference(dayOnly(now)).inDays;
    final label = days < 0 ? l.examPassed : days == 0 ? l.examToday : days == 1 ? l.examTomorrow : l.daysLeft(days);
    final subject = repo.subject(exam.subjectId);
    return GlassCard(
      key: ValueKey('exam_${exam.id}'),
      radius: EnjazRadii.tile,
      onTap: exam.isOfficial ? null : () => showExamSheet(context, ref, exam: exam),
      child: Row(children: [
        Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: days >= 0 && days <= 3 ? EnjazColors.studyGradient : EnjazColors.planGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Text('${days < 0 ? '✓' : days}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            if (days > 0) Text(l.dayUnit, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(exam.title, style: const TextStyle(fontWeight: FontWeight.w800))),
              StatusChip(
                  label: exam.isOfficial ? l.officialExam : l.personalExam,
                  color: exam.isOfficial ? EnjazColors.cyan : EnjazColors.violet),
            ]),
            Text([if (subject != null) subject.nameAr, formatDay(l, exam.examAt), label].join(' • '),
                style: TextStyle(fontSize: 12, color: context.mutedText)),
            if (exam.score != null)
              Text('${l.score}: ${exam.score!.toStringAsFixed(1)}${exam.maxScore != null ? ' / ${exam.maxScore!.toStringAsFixed(0)}' : ''}',
                  style: const TextStyle(color: EnjazColors.success, fontWeight: FontWeight.w700)),
            if (exam.isOfficial && exam.sourceUrl != null)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => launchUrl(Uri.parse(exam.sourceUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(l.source),
              ),
          ]),
        ),
      ]),
    );
  }
}

Future<void> showExamSheet(BuildContext context, WidgetRef ref, {ExamItem? exam}) async {
  final l = context.l10n;
  final repo = ref.read(repositoryProvider);
  final title = TextEditingController(text: exam?.title);
  final score = TextEditingController(text: exam?.score?.toString() ?? '');
  final max = TextEditingController(text: exam?.maxScore?.toString() ?? '100');
  final target = TextEditingController(text: exam?.targetScore?.toString() ?? '');
  var when = exam?.examAt ?? repo.now().add(const Duration(days: 7));
  String? subjectId = exam?.subjectId;
  final formKey = GlobalKey<FormState>();
  String? numValidator(String? v) => (v == null || v.isEmpty || double.tryParse(v) != null) ? null : l.errorGeneric;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(exam == null ? l.addExam : l.edit, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('exam_title'),
                controller: title,
                decoration: InputDecoration(labelText: l.examTitle),
                validator: (v) => (v == null || v.trim().isEmpty) ? l.requiredField : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: subjectId,
                decoration: InputDecoration(labelText: l.subject),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.noSubject)),
                  for (final s in repo.mySubjects) DropdownMenuItem(value: s.id, child: Text(s.nameAr)),
                ],
                onChanged: (v) => subjectId = v,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text('${l.examDate}: ${formatDay(l, when, withYear: true)}'),
                onPressed: () async {
                  final d = await showDatePicker(context: c, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setS(() => when = DateTime(d.year, d.month, d.day, 9));
                },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(controller: score, keyboardType: TextInputType.number, validator: numValidator,
                    decoration: InputDecoration(labelText: l.score))),
                const SizedBox(width: 10),
                Expanded(child: TextFormField(controller: max, keyboardType: TextInputType.number, validator: numValidator,
                    decoration: InputDecoration(labelText: l.maxScore))),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: target, keyboardType: TextInputType.number, validator: numValidator,
                  decoration: InputDecoration(labelText: '${l.targetScore} (%)')),
              const SizedBox(height: 16),
              Row(children: [
                if (exam != null)
                  IconButton(
                    tooltip: l.delete,
                    icon: const Icon(Icons.delete_outline_rounded, color: EnjazColors.danger),
                    onPressed: () async {
                      await repo.remove('exams', exam.id);
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
                Expanded(
                  child: GlowButton(
                    key: const Key('save_exam'),
                    label: l.save,
                    gradient: EnjazColors.planGradient,
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      await repo.save('exams', {
                        ...?exam?.m,
                        'is_official': false,
                        'title': title.text.trim(),
                        'subject_id': subjectId,
                        'exam_at': when.toUtc().toIso8601String(),
                        'score': double.tryParse(score.text),
                        'max_score': double.tryParse(max.text),
                        'target_score': double.tryParse(target.text),
                        'status': 'published',
                      });
                      if (c.mounted) Navigator.pop(c);
                    },
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}
