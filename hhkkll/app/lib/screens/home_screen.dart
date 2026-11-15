import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'game_hub_screen.dart';
import 'history_screen.dart';
import 'new_game_screen.dart';
import 'players_screen.dart';
import 'question_bank_screen.dart';
import 'settings_screen.dart';

const sectionDescriptions = {
  Category.auction:
      'سؤال بقائمة إجابات. يزايد اللاعبون على عدد الأسماء التي يستطيعون ذكرها، وصاحب أعلى مزايدة يذكرها خلال 30 ثانية.',
  Category.whatDoYouKnow:
      'أسئلة معلومات عميقة بالدور. تمرير PASS للاعب التالي، وكل خطأ STRIKE، وثلاثة أخطاء تعني الإقصاء.',
  Category.buzzer:
      'سباق ردّ الفعل: أول من يضغط الجرس يحصل على الإجابة، ويُقفل الجرس فوراً أمام البقية.',
  Category.whoAmI:
      'لغز شخصية كروية بتلميحات متدرجة يكشفها الحكم. كلما عرفت أبكر حصلت على نقاط أكثر.',
};

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width > 760;

    void go(Widget w) => Navigator.of(context).push(_fade(w));

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlowButton(
          key: const Key('new-game'),
          label: 'ابدأ لعبة جديدة',
          icon: Icons.play_arrow_rounded,
          height: 64,
          onPressed: () => go(const NewGameScreen()),
        ),
        if (c.hasResumableMatch) ...[
          const SizedBox(height: 12),
          GlowButton(
            key: const Key('resume-game'),
            label: 'استكمال اللعبة الحالية',
            icon: Icons.restore_rounded,
            color: C.pitch,
            filled: false,
            onPressed: () async {
              await c.resumeMatch();
              if (context.mounted) go(const GameHubScreen());
            },
          ),
        ],
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: wide ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.5,
          children: [
            _MenuTile('إدارة اللاعبين', Icons.groups_rounded, () => go(const PlayersScreen())),
            _MenuTile('بنك الأسئلة', Icons.inventory_2_rounded, () => go(const QuestionBankScreen())),
            _MenuTile('الإعدادات', Icons.tune_rounded, () => go(const SettingsScreen())),
            _MenuTile('الإحصائيات', Icons.leaderboard_rounded, () => go(const HistoryScreen())),
            if (wide) _MenuTile('عن التطبيق', Icons.info_outline_rounded, () => go(const AboutScreen())),
          ],
        ),
        if (!wide) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: _MenuTile('عن التطبيق والمطور', Icons.info_outline_rounded, () => go(const AboutScreen())),
          ),
        ],
      ],
    );

    final sections = GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 1.35 : 1.05,
      children: [for (final cat in Category.values) _SectionShowcase(cat)],
    );

    return Scaffold(
      body: StageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  const SizedBox(height: 8),
                  const Center(child: Wordmark(size: 54)),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text('ULTIMATE FOOTBALL QUIZ',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontFamily: 'Display', color: C.muted, letterSpacing: 5, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: _SupplyChip()),
                  const SizedBox(height: 22),
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 5, child: sections),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: actions),
                    ])
                  else ...[
                    sections,
                    const SizedBox(height: 20),
                    actions,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

PageRouteBuilder<T> _fade<T>(Widget w) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => w,
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .03), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

Route<T> fadeRoute<T>(Widget w) => _fade<T>(w);

class _SectionShowcase extends StatelessWidget {
  const _SectionShowcase(this.cat);
  final Category cat;
  @override
  Widget build(BuildContext context) {
    final col = C.of(cat);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SectionTag(cat),
            const SizedBox(height: 16),
            Text(sectionDescriptions[cat]!, textAlign: TextAlign.center, style: const TextStyle(height: 1.8)),
          ]),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [col.withValues(alpha: .22), C.surface.withValues(alpha: .9)],
          ),
          border: Border.all(color: col.withValues(alpha: .45)),
          boxShadow: [BoxShadow(color: col.withValues(alpha: .12), blurRadius: 24)],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: col.withValues(alpha: .16), shape: BoxShape.circle),
              child: Icon(C.icon(cat), color: col, size: 26),
            ),
            const Spacer(),
            Text(cat.arabic, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
            Text(cat.english,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontFamily: 'Display', color: col, fontSize: 11, letterSpacing: 1.6)),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: C.surface.withValues(alpha: .85),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(icon, color: C.gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ]),
          ),
        ),
      );
}

/// Live state of the question supply (online / generating / offline).
class _SupplyChip extends StatelessWidget {
  const _SupplyChip();
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (!c.ready) return const SizedBox.shrink();
    final st = c.supply.status;
    final (col, label) = !c.supply.active
        ? (C.muted, 'مخزون الأسئلة: ${st.cached}')
        : st.fetching.isNotEmpty
            ? (C.cyan, 'جاري جلب أسئلة جديدة…')
            : st.online
                ? (C.pitch, 'متصل — الأسئلة تتجدد تلقائياً')
                : (C.orange, 'بدون اتصال — اللعب من المخزون المحلي');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: col.withValues(alpha: .1),
        border: Border.all(color: col.withValues(alpha: .4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: col, fontSize: 12)),
      ]),
    );
  }
}
