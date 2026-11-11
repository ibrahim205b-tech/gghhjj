import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';
import 'subscribers_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  String period = periodOf(DateTime.now());
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    return Loader<(List<Map<String, Object?>>, bool)>(
      key: ValueKey('$period$_rev'),
      load: () async =>
          (await app.os.billing.periodInvoices(g, period), await app.os.billing.isPeriodClosed(g, period)),
      builder: (context, d, reload) {
        final (rows, closed) = d;
        final total = rows.fold<int>(0, (a, r) => a + (r['current_net'] as int));
        final gross = rows.fold<int>(0, (a, r) => a + (r['gross'] as int));
        return PageBody(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => period = previousPeriod(period)),
                  icon: const Icon(Icons.chevron_right),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('فواتير شهر $period', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      closed
                          ? const StatusChip('الشهر مغلق', Brand.danger)
                          : const StatusChip('الشهر مفتوح', Brand.success),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => period = nextPeriod(period)),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            StatGrid(
              children: [
                StatCard(
                  label: 'عدد الفواتير',
                  value: '${rows.length}',
                  icon: Icons.receipt_long,
                  color: Brand.primary,
                ),
                StatCard(label: 'إجمالي قبل الخصم', value: money(gross), icon: Icons.summarize, color: Brand.info),
                StatCard(label: 'صافي الفواتير', value: money(total), icon: Icons.request_quote, color: Brand.success),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!closed && app.can(Perm.billingGenerate))
                  FilledButton.icon(
                    icon: const Icon(Icons.auto_mode),
                    label: const Text('إصدار فواتير الشهر'),
                    onPressed: () async {
                      if (!await confirm(
                        context,
                        'إصدار الفواتير',
                        'سيتم إصدار فاتورة $period لكل مشترك فعال ليس لديه فاتورة لهذا الشهر. لن تتكرر أي فاتورة.',
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      GenerateResult? r;
                      await guard(context, () async => r = await app.os.billing.generateMonth(g, period));
                      if (r != null && context.mounted) {
                        showOk(context, 'تم إصدار ${r!.created} فاتورة، وتجاوز ${r!.skippedExisting} موجودة مسبقاً.');
                        setState(() => _rev++);
                      }
                    },
                  ),
                if (!closed && app.can(Perm.billingClosePeriod))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lock),
                    label: const Text('إغلاق الشهر'),
                    onPressed: () async {
                      if (!await confirm(
                        context,
                        'إغلاق الشهر',
                        'بعد الإغلاق لا يمكن إصدار أو تعديل فواتير $period. الدفعات تبقى مسموحة. هل راجعت الفواتير؟',
                        danger: true,
                        ok: 'إغلاق',
                      )) {
                        return;
                      }
                      if (!context.mounted) return;
                      await guard(context, () => app.os.billing.closePeriod(g, period), success: 'تم إغلاق الشهر');
                      setState(() => _rev++);
                    },
                  ),
                if (closed && app.can(Perm.backupManage))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('إعادة فتح (المالك)'),
                    onPressed: () async {
                      final v = await showFormDialog(
                        context,
                        title: 'إعادة فتح الشهر',
                        fields: const [FieldSpec('reason', 'السبب', required: true)],
                      );
                      if (v == null || !context.mounted) return;
                      await guard(context, () => app.os.billing.reopenPeriod(g, period, v['reason']!));
                      setState(() => _rev++);
                    },
                  ),
              ],
            ),
            if (rows.isEmpty)
              const EmptyState(icon: Icons.receipt_long, title: 'لا توجد فواتير لهذا الشهر')
            else
              Card(
                child: Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        leading: Text('${r['account_no']}'),
                        title: Text('${r['full_name']}'),
                        subtitle: Text(
                          '${r['amps']} × ${money(r['amp_price'] as int)}'
                          '${(r['discount'] as int) > 0 ? ' · ${r['discount_reason'] ?? 'خصم'} ${money(r['discount'] as int)}' : ''}',
                        ),
                        trailing: Text(
                          money(r['current_net'] as int),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SubscriberDetailScreen(id: r['subscriber_id'] as String)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
