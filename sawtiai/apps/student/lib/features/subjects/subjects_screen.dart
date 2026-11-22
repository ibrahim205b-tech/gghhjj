import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../common/shared.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final subjects = repo.mySubjects;
    final g = repo.grade(repo.profile.gradeId);
    final b = repo.branch(repo.profile.branchId);
    return EnjazPage(
      title: l.subjectsTab,
      actions: [IconButton(tooltip: l.planner, icon: const Icon(Icons.auto_awesome_rounded), onPressed: () => context.push('/planner'))],
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text([g?.nameAr, b?.nameAr].whereType<String>().join(' • '), style: TextStyle(color: context.mutedText)),
        const SizedBox(height: 12),
        if (subjects.isEmpty)
          EmptyState(icon: Icons.auto_stories_outlined, message: l.noSubjects)
        else
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > 560 ? 3 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                for (final s in subjects)
                  Builder(builder: (context) {
                    final pct = repo.subjectCompletion(s.id);
                    final color = hexColor(s.color);
                    return GlassCard(
                      key: ValueKey('subject_${s.id}'),
                      radius: EnjazRadii.tile,
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/subject/${s.id}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                          child: Icon(subjectIcon(s.icon), color: color),
                        ),
                        Text(s.nameAr, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        EnjazProgressBar(value: pct, height: 8, showLabel: false),
                        Text(l.subjectProgress((pct * 100).round()), style: TextStyle(fontSize: 11.5, color: context.mutedText)),
                      ]),
                    );
                  }),
              ],
            );
          }),
      ]),
    );
  }
}

class SubjectDetailScreen extends ConsumerWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repo = ref.watch(repositoryProvider);
    final s = repo.subject(subjectId);
    if (s == null) return EnjazPage(title: l.subject, body: EmptyState(icon: Icons.error_outline, message: l.errorGeneric));
    final chapters = repo.chaptersOf(subjectId);
    final prog = repo.topicProgress;
    final pct = repo.subjectCompletion(subjectId);
    final topics = repo.topicsOfSubject(subjectId);
    final difficult = topics.where((t) => prog[t.id]?.isDifficult ?? false).length;
    final revision = topics.where((t) => prog[t.id]?.status == TopicStatus.needsRevision).length;
    return EnjazPage(
      title: s.nameAr,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        GlassCard(
          blur: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.subjectProgress((pct * 100).round()), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            EnjazProgressBar(value: pct),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusChip(label: '${l.topics}: ${topics.length}', color: EnjazColors.cyan),
              StatusChip(label: '${l.difficultTopic}: $difficult', color: EnjazColors.danger),
              StatusChip(label: '${l.needsReview}: $revision', color: EnjazColors.warning),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/quiz'),
              icon: const Icon(Icons.quiz_rounded),
              label: Text(l.questionBank),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push('/library'),
              icon: const Icon(Icons.local_library_rounded),
              label: Text(l.library),
            ),
          ),
        ]),
        SectionHeader(title: l.chapters),
        if (chapters.isEmpty) EmptyState(icon: Icons.list_alt_rounded, message: l.noSubjects),
        for (final c in chapters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Builder(builder: (context) {
                    final ts = repo.topicsOf(c.id);
                    final done = ts.where((t) => prog[t.id]?.status == TopicStatus.completed).length;
                    return Text('$done / ${ts.length}', style: TextStyle(color: context.mutedText, fontSize: 12));
                  }),
                  children: [
                    for (final t in repo.topicsOf(c.id)) _TopicRow(topic: t, progress: prog[t.id]),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _TopicRow extends ConsumerWidget {
  const _TopicRow({required this.topic, required this.progress});
  final Topic topic;
  final TopicProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final status = progress?.status ?? TopicStatus.notStarted;
    final (label, color) = topicStatusLook(l, status);
    return ListTile(
      key: ValueKey('topic_${topic.id}'),
      onTap: () => _editTopic(context, ref),
      leading: Icon(
        progress?.isDifficult ?? false ? Icons.priority_high_rounded : Icons.circle_outlined,
        color: progress?.isDifficult ?? false ? EnjazColors.danger : context.mutedText,
        size: 18,
      ),
      title: Text(topic.title),
      subtitle: (progress?.note?.isNotEmpty ?? false)
          ? Text(progress!.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.mutedText))
          : null,
      trailing: StatusChip(label: label, color: color),
    );
  }

  Future<void> _editTopic(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final repo = ref.read(repositoryProvider);
    var status = progress?.status ?? TopicStatus.notStarted;
    var difficult = progress?.isDifficult ?? false;
    final note = TextEditingController(text: progress?.note);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(topic.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${l.difficulty}: ${[l.easy, l.medium, l.hard][topic.difficulty - 1]}', style: TextStyle(color: c.mutedText)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in TopicStatus.values)
                ChoiceChip(
                  key: ValueKey('status_${s.name}'),
                  label: Text(topicStatusLook(l, s).$1),
                  selected: status == s,
                  onSelected: (_) => setS(() => status = s),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.markDifficult),
              value: difficult,
              onChanged: (v) => setS(() => difficult = v),
            ),
            TextField(controller: note, maxLines: 3, decoration: InputDecoration(labelText: l.note)),
            const SizedBox(height: 16),
            GlowButton(
              key: const Key('save_topic'),
              label: l.save,
              gradient: EnjazColors.planGradient,
              onPressed: () async {
                await repo.setTopicStatus(topic.id, status: status, difficult: difficult, note: note.text.trim());
                if (c.mounted) Navigator.pop(c);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
