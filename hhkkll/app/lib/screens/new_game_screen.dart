import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../app.dart';
import '../services/controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'game_hub_screen.dart';
import 'home_screen.dart';
import 'players_screen.dart';

class NewGameScreen extends StatefulWidget {
  const NewGameScreen({super.key});
  @override
  State<NewGameScreen> createState() => _NewGameScreenState();
}

class _NewGameScreenState extends State<NewGameScreen> {
  final Set<String> _selected = {};
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (!_initialised) {
      _selected.addAll(c.roster.map((p) => p.id));
      _initialised = true;
    }
    final chosen = c.roster.where((p) => _selected.contains(p.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('لعبة جديدة')),
      body: StageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            const Text('المتنافسون', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 4),
            const Text('اختر لاعبين اثنين على الأقل. ترتيبهم هنا هو ترتيب الدور.',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, p) in c.roster.indexed)
                FilterChip(
                  key: Key('pick-${p.name}'),
                  label: Text(p.name),
                  selected: _selected.contains(p.id),
                  selectedColor: C.player(i).withValues(alpha: .25),
                  checkmarkColor: C.player(i),
                  side: BorderSide(color: C.player(i).withValues(alpha: .6)),
                  onSelected: (v) => setState(() => v ? _selected.add(p.id) : _selected.remove(p.id)),
                ),
              ActionChip(
                key: const Key('quick-add'),
                avatar: const Icon(Icons.add_rounded, size: 18, color: C.gold),
                label: const Text('لاعب جديد'),
                onPressed: () async {
                  final n = await askName(context, title: 'إضافة لاعب');
                  if (n == null || n.trim().isEmpty) return;
                  await c.addRosterPlayer(n);
                  setState(() => _selected.add(c.roster.last.id));
                },
              ),
            ]),
            const SizedBox(height: 22),
            _RulesCard(rules: c.settings.rules),
            const SizedBox(height: 24),
            GlowButton(
              key: const Key('start-match'),
              label: chosen.length < 2 ? 'اختر لاعبين اثنين على الأقل' : 'انطلاق المنافسة (${chosen.length} لاعبين)',
              icon: Icons.sports_soccer_rounded,
              height: 64,
              onPressed: chosen.length < 2
                  ? null
                  : () async {
                      await c.startNewMatch(List<RosterPlayer>.of(chosen));
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(fadeRoute(const GameHubScreen()));
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.rules});
  final GameSettings rules;
  @override
  Widget build(BuildContext context) {
    final r = rules;
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(color: C.muted, fontSize: 13))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.rule_rounded, color: C.gold),
            SizedBox(width: 8),
            Text('قواعد هذه المنافسة', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          row('الأخطاء قبل الإقصاء', '${r.strikeLimit}'),
          row('وقت المزاد', '${r.auctionSeconds} ث'),
          row('نجاح / فشل المزاد', '+${r.auctionSuccessPoints} / −${r.auctionFailPenalty}'),
          row('ماذا تعرف؟', '+${r.wdykPoints}'),
          row('الجرس صح / خطأ', '+${r.buzzerPoints} / −${r.buzzerWrongPenalty}'),
          row('من أنا؟ حسب التلميح', r.whoAmIPoints.join(' · ')),
          const SizedBox(height: 6),
          const Text('تُعدّل من الإعدادات، ويستطيع الحكم تعديل النقاط يدوياً أثناء اللعب.',
              style: TextStyle(color: C.muted, fontSize: 11)),
        ]),
      ),
    );
  }
}
