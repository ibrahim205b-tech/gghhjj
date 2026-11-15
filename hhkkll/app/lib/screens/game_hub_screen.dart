import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/referee_panel.dart';
import '../widgets/scoreboard.dart';
import 'final_screen.dart';
import 'home_screen.dart';
import 'rounds/auction_screen.dart';
import 'rounds/buzzer_screen.dart';
import 'rounds/round_common.dart';
import 'rounds/whoami_screen.dart';
import 'rounds/wdyk_screen.dart';

RoundScreen roundScreenFor(Category c, {(Round, Question)? resume}) => switch (c) {
      Category.auction => AuctionScreen(resume: resume),
      Category.whatDoYouKnow => WdykScreen(resume: resume),
      Category.buzzer => BuzzerScreen(resume: resume),
      Category.whoAmI => WhoAmIScreen(resume: resume),
    };

/// The competition board: live ranking, the four sections and the
/// referee's match controls.
class GameHubScreen extends StatelessWidget {
  const GameHubScreen({super.key});

  Future<void> _end(BuildContext context) async {
    final c = AppScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء اللعبة؟'),
        content: const Text('سيُعلن الفائز وتُحفظ نتائج المنافسة في الإحصائيات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('متابعة اللعب')),
          FilledButton(
            key: const Key('confirm-end'),
            style: FilledButton.styleFrom(backgroundColor: C.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إنهاء وإعلان الفائز'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final rec = await c.finishMatch();
    if (rec != null && context.mounted) {
      Navigator.of(context).pushReplacement(fadeRoute(FinalScreen(record: rec)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.session;
    if (s == null) {
      return const Scaffold(body: Center(child: Text('لا توجد منافسة جارية')));
    }
    final pending = c.pendingRound;
    final wide = MediaQuery.sizeOf(context).width > 760;

    Future<void> open(Category cat, {(Round, Question)? resume}) async {
      await Navigator.of(context).push(fadeRoute(roundScreenFor(cat, resume: resume)));
    }

    final sections = GridView.count(
      crossAxisCount: wide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: wide ? 1.15 : 1.25,
      children: [
        for (final cat in Category.values)
          _SectionButton(
            cat: cat,
            ready: c.supply.queued(cat),
            fetching: c.supply.status.fetching.contains(cat),
            onTap: pending != null ? null : () => open(cat),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المنافسة'),
        leading: IconButton(
          tooltip: 'الرئيسية (المنافسة محفوظة)',
          icon: const Icon(Icons.home_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            key: const Key('hub-referee'),
            tooltip: 'لوحة الحكم',
            icon: const Icon(Icons.admin_panel_settings_rounded, color: C.gold),
            onPressed: () => showRefereePanel(context),
          ),
        ],
      ),
      body: StageBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
            children: [
              if (pending != null) ...[
                GlowButton(
                  key: const Key('resume-round'),
                  label: 'استكمال جولة ${pending.$2.category.arabic} الجارية',
                  icon: Icons.play_circle_fill_rounded,
                  color: C.of(pending.$2.category),
                  onPressed: () => open(pending.$2.category, resume: pending),
                ),
                const SizedBox(height: 14),
              ],
              const Text('اختر القسم', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 10),
              sections,
              const SizedBox(height: 20),
              Row(children: [
                const Text('الترتيب', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                const Spacer(),
                Text('أسئلة مستخدمة: ${s.used.length}', style: const TextStyle(color: C.muted, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Scoreboard(session: s, onTap: (_) => showRefereePanel(context)),
              const SizedBox(height: 16),
              GlowButton(
                key: const Key('end-game'),
                label: 'إنهاء اللعبة وإعلان الفائز',
                icon: Icons.emoji_events_rounded,
                color: C.red,
                filled: false,
                onPressed: () => _end(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({required this.cat, required this.ready, required this.fetching, required this.onTap});
  final Category cat;
  final int ready;
  final bool fetching;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final col = C.of(cat);
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: InkWell(
        key: Key('section-${cat.code}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [col.withValues(alpha: .25), C.surface.withValues(alpha: .95)],
            ),
            border: Border.all(color: col.withValues(alpha: .55)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(C.icon(cat), color: col, size: 30),
              const Spacer(),
              if (fetching)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: col)),
            ]),
            const Spacer(),
            Text(cat.arabic, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            Text(ready > 0 ? 'جاهز: $ready سؤال' : (fetching ? 'جاري الجلب…' : 'بانتظار أسئلة'),
                style: TextStyle(color: ready > 0 ? C.muted : C.orange, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
