import 'package:flutter/material.dart';
import 'package:hhkkll_core/hhkkll_core.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/referee_panel.dart';
import 'settings_screen.dart';

/// Live view of the question supply: sources, connection, what is queued,
/// the local reserve, duplicates rejected, and every stored question with
/// its source.
class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key});
  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  Category _cat = Category.auction;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final st = c.supply.status;
    final all = c.supply.cachedQuestions.where((q) => q.category == _cat).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final verified = c.supply.cachedQuestions.where((q) => q.verification.isVerified).length;
    return Scaffold(
      appBar: AppBar(title: const Text('بنك الأسئلة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(st.online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: st.online ? C.pitch : C.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !c.supply.active
                          ? 'التوليد التلقائي يعمل أثناء المنافسة'
                          : st.online
                              ? 'متصل — يتم جلب الأسئلة تلقائياً'
                              : 'بدون اتصال — إعادة المحاولة تلقائياً',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                _kv('المصادر', [
                  if (c.settings.serverUrl.isNotEmpty) 'خادم التوليد',
                  if (c.settings.feedUrl.isNotEmpty) 'الموجز المنشور',
                  'حزمة البداية المدمجة',
                ].join(' + ')),
                _kv('في المخزون المحلي', '${st.cached} سؤال ($verified موثّق آلياً)'),
                _kv('مستخدمة في الجلسة الحالية', '${st.usedThisSession}'),
                _kv('في السجل التاريخي (جلسات سابقة)', '${c.supply.historySize}'),
                _kv('مكررات رُفضت', '${st.rejectedDuplicates}'),
                _kv('غير صالحة رُفضت', '${st.rejectedInvalid}'),
                if (st.lastSuccess != null) _kv('آخر جلب ناجح', '${st.lastSource ?? ''} ${_t(st.lastSuccess!)}'),
                if (st.lastError != null) _kv('آخر خطأ', st.lastError!),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('إعداد المصادر'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.supply.active ? () => c.supply.refillNow(_cat) : null,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('جلب الآن'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await c.supply.clearHistory();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('بدأت دورة أسئلة جديدة — السجل التاريخي مُسح')));
                      }
                    },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('دورة أسئلة جديدة'),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<Category>(
            segments: [
              for (final cat in Category.values)
                ButtonSegment(value: cat, label: Text(cat.arabic, style: const TextStyle(fontSize: 12)), icon: Icon(C.icon(cat), size: 16)),
            ],
            selected: {_cat},
            onSelectionChanged: (s) => setState(() => _cat = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          Text('${all.length} سؤال في المخزون · جاهز للعب الآن: ${c.supply.queued(_cat)}',
              style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 8),
          for (final q in all)
            Card(
              child: ListTile(
                title: Text(q.category == Category.whoAmI ? 'من أنا؟ — ${q.answer}' : q.text,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.6)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    VerificationBadge(q),
                    const SizedBox(width: 6),
                    if (c.usedQuestions.containsKey(q.id))
                      const Text('مستخدم', style: TextStyle(color: C.orange, fontSize: 11)),
                  ]),
                ),
                onTap: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => SourcePanel(question: q)),
              ),
            ),
        ],
      ),
    );
  }

  static String _t(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: Text(k, style: const TextStyle(color: C.muted, fontSize: 13))),
          Expanded(flex: 6, child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      );
}

