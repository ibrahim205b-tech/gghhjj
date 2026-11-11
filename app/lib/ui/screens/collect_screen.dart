import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';
import '../payment_flow.dart';

/// Collection screen. For collectors it shows only their assigned
/// subscribers and their own custody; works fully offline.
class CollectScreen extends StatefulWidget {
  const CollectScreen({super.key});
  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  final _q = TextEditingController();
  bool _debtOnly = true;
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final s = app.session!;
    return Column(
      children: [
        if (s.isCollector)
          Loader<(int, int)>(
            key: ValueKey('c$_rev'),
            load: () async => s.collectorId == null
                ? (0, 0)
                : (
                    await app.os.collection.custodyBalance(g, s.collectorId!),
                    await app.os.reports.collections(g, DateRange.day(DateTime.now()), collectorId: s.collectorId),
                  ),
            builder: (context, d, _) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: s.collectorId == null
                  ? const Card(
                      child: ListTile(
                        leading: Icon(Icons.warning, color: Brand.warning),
                        title: Text('حسابك غير مرتبط بسجل جابي. اطلب من المالك ربطه.'),
                      ),
                    )
                  : StatGrid(
                      children: [
                        StatCard(label: 'تحصيلي اليوم', value: money(d.$2), icon: Icons.today, color: Brand.success),
                        StatCard(
                          label: 'المبلغ بعهدتي',
                          value: money(d.$1),
                          icon: Icons.account_balance_wallet,
                          color: Brand.warning,
                          hint: 'يُسلم للصندوق',
                        ),
                      ],
                    ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ابحث عن المشترك بالاسم أو الرقم أو الهاتف',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilterChip(
                label: const Text('غير المسددين فقط'),
                selected: _debtOnly,
                onSelected: (v) => setState(() => _debtOnly = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: Loader<List<Map<String, Object?>>>(
            key: ValueKey('${_q.text}$_debtOnly$_rev'),
            load: () => app.os.subscribers.search(
              g,
              SubscriberFilter(query: _q.text, onlyWithDebt: _debtOnly, status: SubscriberStatus.active),
              limit: 300,
            ),
            builder: (context, rows, _) {
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.task_alt,
                  title: _debtOnly ? 'لا يوجد مشتركون غير مسددين' : 'لا يوجد مشتركون',
                  subtitle: s.isCollector ? 'تظهر هنا فقط المناطق والكابينات المخصصة لك.' : null,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final bal = r['balance'] as int;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Card(
                      child: ListTile(
                        minVerticalPadding: 14,
                        title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'رقم ${r['account_no']}${r['area_name'] != null ? ' · ${r['area_name']}' : ''}'
                          '${r['phone'] != null ? ' · ${r['phone']}' : ''}',
                        ),
                        trailing: FilledButton(
                          onPressed: () => showPayDialog(context, r, onDone: () => setState(() => _rev++)),
                          child: Text(bal > 0 ? 'استلام ${money(bal)}' : 'دفعة'),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
