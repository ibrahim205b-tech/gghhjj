import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hhkkll_core/hhkkll_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'common.dart';
import 'effects.dart';

/// Referee control panel — reachable from every round without leaving the
/// question: points, strikes, eliminate / restore, used-question log and the
/// current question's sources.
Future<void> showRefereePanel(BuildContext context, {Question? current}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .82,
      maxChildSize: .95,
      builder: (ctx, scroll) => DefaultTabController(
        length: current == null ? 2 : 3,
        child: Column(children: [
          TabBar(
            indicatorColor: C.gold,
            labelColor: C.gold,
            unselectedLabelColor: C.muted,
            tabs: [
              const Tab(text: 'اللاعبون'),
              const Tab(text: 'سجل الأسئلة'),
              if (current != null) const Tab(text: 'المصدر'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _PlayersControl(scroll: scroll),
              _UsedLog(),
              if (current != null) SourcePanel(question: current),
            ]),
          ),
        ]),
      ),
    ),
  );
}

class _PlayersControl extends StatefulWidget {
  const _PlayersControl({required this.scroll});
  final ScrollController scroll;
  @override
  State<_PlayersControl> createState() => _PlayersControlState();
}

class _PlayersControlState extends State<_PlayersControl> {
  int _step = 5;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.session;
    if (s == null) return const SizedBox.shrink();
    Future<void> apply(VoidCallback f) async {
      f();
      await c.persistSession();
    }

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
      children: [
        Row(children: [
          const Text('خطوة النقاط:', style: TextStyle(color: C.muted)),
          const SizedBox(width: 8),
          for (final v in [1, 5, 10, 20])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ChoiceChip(
                label: Text('$v'),
                selected: _step == v,
                selectedColor: C.gold.withValues(alpha: .3),
                onSelected: (_) => setState(() => _step = v),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        for (final (i, p) in s.players.indexed)
          Card(
            key: Key('ref-${p.name}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: C.player(i), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            decoration: p.eliminated ? TextDecoration.lineThrough : null)),
                  ),
                  Text('${p.score}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'Display', fontSize: 22, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _RoundBtn(Icons.remove_rounded, C.red, 'خصم نقاط', () => apply(() => s.addPoints(p.id, -_step, reason: 'قرار الحكم'))),
                  const SizedBox(width: 6),
                  _RoundBtn(Icons.add_rounded, C.pitch, 'إضافة نقاط', () => apply(() => s.addPoints(p.id, _step, reason: 'قرار الحكم'))),
                  const Spacer(),
                  StrikeMarks(strikes: p.strikes, limit: s.settings.strikeLimit),
                  const SizedBox(width: 6),
                  _RoundBtn(Icons.exposure_neg_1_rounded, C.muted, 'إزالة خطأ', () => apply(() => s.removeStrike(p.id))),
                  const SizedBox(width: 6),
                  _RoundBtn(Icons.close_rounded, C.red, 'إضافة خطأ', () async {
                    final r = s.addStrike(p.id, reason: 'قرار الحكم');
                    c.sound.play(r.eliminatedNow ? Sfx.eliminated : Sfx.strike);
                    await c.persistSession();
                    if (r.eliminatedNow && context.mounted) await showElimination(context, p.name);
                  }),
                ]),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: p.eliminated
                      ? TextButton.icon(
                          onPressed: () => apply(() => s.restore(p.id)),
                          icon: const Icon(Icons.undo_rounded, color: C.pitch),
                          label: const Text('إعادة اللاعب', style: TextStyle(color: C.pitch)),
                        )
                      : TextButton.icon(
                          onPressed: () async {
                            s.eliminate(p.id);
                            c.sound.play(Sfx.eliminated);
                            await c.persistSession();
                            if (context.mounted) await showElimination(context, p.name);
                          },
                          icon: const Icon(Icons.block_rounded, color: C.red),
                          label: const Text('إقصاء', style: TextStyle(color: C.red)),
                        ),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn(this.icon, this.color, this.tip, this.onTap);
  final IconData icon;
  final Color color;
  final String tip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: color.withValues(alpha: .12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, color: color, size: 20)),
          ),
        ),
      );
}

class _UsedLog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final used = c.session?.used.reversed.toList() ?? const [];
    if (used.isEmpty) {
      return const Center(child: Text('لم تُستخدم أسئلة بعد', style: TextStyle(color: C.muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: used.length,
      separatorBuilder: (_, _) => const Divider(height: 14),
      itemBuilder: (context, i) {
        final u = used[i];
        final q = c.usedQuestions[u.id];
        return InkWell(
          onTap: q == null
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => SourcePanel(question: q),
                  ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(C.icon(u.category), color: C.of(u.category), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.category == Category.whoAmI ? 'من أنا؟ — ${u.answer}' : u.text,
                    style: const TextStyle(fontSize: 13, height: 1.6)),
                Text('الإجابة: ${u.answer}', style: const TextStyle(color: C.pitch, fontSize: 12)),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Where a question comes from and how it was checked.
class SourcePanel extends StatelessWidget {
  const SourcePanel({super.key, required this.question});
  final Question question;
  @override
  Widget build(BuildContext context) {
    final q = question;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      shrinkWrap: true,
      children: [
        Row(children: [SectionTag(q.category), const SizedBox(width: 8), VerificationBadge(q)]),
        const SizedBox(height: 12),
        Text(q.category == Category.whoAmI ? q.clues.join('\n') : q.text, style: const TextStyle(height: 1.7)),
        const SizedBox(height: 8),
        Text('الإجابة: ${q.answer}', style: const TextStyle(color: C.pitch, fontWeight: FontWeight.w700)),
        if (q.factAsOf != null)
          Text('المعلومة صحيحة حتى: ${q.factAsOf}', style: const TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 10),
        Text(
          q.verification.isVerified
              ? 'تم التحقق بشكل مستقل عبر صفحات استرجعها المدقق (${q.verification.model ?? ''})'
              : 'سؤال من حزمة البداية المكتوبة يدوياً — راجع الرابط المرجعي عند الشك.',
          style: const TextStyle(color: C.muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 8),
        const Text('المصادر', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final s in q.sources)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_rounded, color: C.cyan),
            title: Text(s.title.isEmpty ? s.url : s.title, textDirection: TextDirection.ltr),
            subtitle: Text(Uri.decodeFull(s.url),
                textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11, color: C.muted)),
            onTap: () async {
              final ok = await launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication)
                  .catchError((_) => false);
              if (!ok) {
                await Clipboard.setData(ClipboardData(text: s.url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الرابط')));
                }
              }
            },
          ),
      ],
    );
  }
}
