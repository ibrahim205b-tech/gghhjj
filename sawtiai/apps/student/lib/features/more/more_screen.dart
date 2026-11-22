import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../common/shared.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final p = ref.watch(repositoryProvider).profile;
    final items = <(IconData, String, String, Color)>[
      (Icons.local_library_rounded, l.myLibrary, '/library', EnjazColors.cyan),
      (Icons.quiz_rounded, l.questionBank, '/quiz', EnjazColors.violet),
      (Icons.wb_sunny_rounded, l.motivation, '/motivation', EnjazColors.warning),
      (Icons.auto_awesome_rounded, l.planner, '/planner', EnjazColors.success),
      (Icons.timer_rounded, l.pomodoro, '/tools/pomodoro', EnjazColors.danger),
      (Icons.av_timer_rounded, l.stopwatch, '/tools/stopwatch', EnjazColors.primary),
      (Icons.checklist_rounded, l.tasks, '/tasks', EnjazColors.violet),
      (Icons.sticky_note_2_rounded, l.myNotes, '/notes', EnjazColors.warning),
      (Icons.flag_rounded, l.goals, '/goals', EnjazColors.success),
      (Icons.emoji_events_rounded, l.myAchievements, '/achievements', EnjazColors.streak),
      (Icons.insights_rounded, l.statistics, '/stats', EnjazColors.cyan),
      (Icons.calculate_rounded, l.gradeCalculator, '/tools/grade-calculator', EnjazColors.primary),
      (Icons.percent_rounded, l.percentageCalculator, '/tools/percentage', EnjazColors.violet),
      (Icons.account_balance_wallet_rounded, l.expenses, '/expenses', EnjazColors.success),
      (Icons.school_rounded, l.guidance, '/guidance', EnjazColors.cyan),
      (Icons.settings_rounded, l.settings, '/settings', EnjazColors.textSecondary),
    ];
    return EnjazPage(
      title: l.moreTab,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        GlassCard(
          blur: true,
          onTap: () => context.push('/settings'),
          child: Row(children: [
            ProfileAvatar(name: p.displayName, url: p.avatarUrl, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(l.slogan, style: TextStyle(color: context.mutedText, fontSize: 12.5)),
              ]),
            ),
            Icon(Icons.chevron_left_rounded, color: context.mutedText),
          ]),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 560 ? 4 : 3;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: [
              for (final (icon, label, route, color) in items)
                GlassCard(
                  radius: EnjazRadii.tile,
                  padding: const EdgeInsets.all(10),
                  onTap: () => context.push(route),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(height: 8),
                    Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ],
          );
        }),
      ]),
    );
  }
}
