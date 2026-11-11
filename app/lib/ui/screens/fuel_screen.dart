import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key});
  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final last30 = DateRange.lastDays(DateTime.now(), 30);
    return Loader<(FuelStock, FuelStats, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
      key: ValueKey(_rev),
      load: () async => (
        await app.os.fuel.stock(g),
        await app.os.fuel.stats(g, last30),
        await app.os.fuel.purchases(g, DateRange.lastDays(DateTime.now(), 90)),
        await app.os.fuel.consumptions(g, DateRange.lastDays(DateTime.now(), 90)),
      ),
      builder: (context, d, _) {
        final (st, stats, buys, uses) = d;
        final gap = st.lastDipMl == null ? null : st.lastDipMl! - st.bookMl;
        return PageBody(
          children: [
            StatGrid(
              children: [
                StatCard(
                  label: 'المخزون الدفتري',
                  value: liters(st.bookMl),
                  icon: Icons.local_gas_station,
                  color: Brand.info,
                  hint: 'المشتريات − الاستهلاك المسجل',
                ),
                StatCard(
                  label: 'آخر قياس فعلي للخزان',
                  value: st.lastDipMl == null ? 'لا يوجد' : liters(st.lastDipMl!),
                  icon: Icons.straighten,
                  color: Brand.primary,
                  hint: st.lastDipMl == null
                      ? 'سجّل قياساً بالمسطرة أو الحساس'
                      : '${FuelSource.labels[st.lastDipSource]} · ${st.lastDipAt!.substring(0, 10)}',
                ),
                if (app.can(Perm.financeView)) ...[
                  StatCard(
                    label: 'قيمة المخزون',
                    value: money(st.value),
                    icon: Icons.inventory,
                    color: Brand.accent,
                    hint: 'متوسط ${money(st.avgCostPerLiter)} للتر',
                  ),
                  StatCard(
                    label: 'كلفة الوقود آخر 30 يوماً',
                    value: money(stats.cost),
                    icon: Icons.paid,
                    color: Brand.danger,
                  ),
                ],
                StatCard(
                  label: 'متوسط الاستهلاك اليومي',
                  value: liters(stats.avgDailyMl.round()),
                  icon: Icons.speed,
                  color: Brand.warning,
                  hint: 'آخر 30 يوماً',
                ),
                StatCard(
                  label: 'لتر لكل ساعة تشغيل',
                  value: stats.litersPerHour == null ? '—' : stats.litersPerHour!.toStringAsFixed(1),
                  icon: Icons.timer,
                  color: Brand.primary,
                  hint: stats.costPerHour == null ? 'يتطلب سجل تشغيل' : 'كلفة الساعة ${money(stats.costPerHour!)}',
                ),
                StatCard(
                  label: 'الاحتياج المتوقع للأسبوع',
                  value: liters(stats.forecastNext7DaysMl),
                  icon: Icons.insights,
                  color: Brand.info,
                  hint: 'تقدير من متوسط 30 يوماً',
                ),
              ],
            ),
            if (gap != null && gap.abs() > 0)
              Card(
                child: ListTile(
                  leading: Icon(Icons.compare_arrows, color: gap.abs() > 20000 ? Brand.danger : Brand.warning),
                  title: Text('فرق بين القياس الفعلي والدفتر: ${liters(gap.abs())} ${gap < 0 ? 'نقص' : 'زيادة'}'),
                  subtitle: const Text(
                    'الدفتر يعتمد على المسجل يدوياً؛ القياس الفعلي هو المرجع. راجع الاستهلاك غير المسجل أو التسرب.',
                  ),
                ),
              ),
            if (stats.anomalies.isNotEmpty)
              Section(
                title: 'استهلاك غير طبيعي (آخر 30 يوماً)',
                child: Column(
                  children: [
                    for (final a in stats.anomalies)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber, color: Brand.warning),
                        title: Text('${a['day']} — ${liters(a['ml'] as int)}'),
                        subtitle: Text('${a['reason']}'),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('شراء كاز'),
                  onPressed: () => _purchase(context, app, g),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.water_drop),
                  label: const Text('تسجيل استهلاك'),
                  onPressed: () => _consume(context, app, g),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.straighten),
                  label: const Text('قياس الخزان'),
                  onPressed: () => _dip(context, app, g),
                ),
              ],
            ),
            Section(
              title: 'المشتريات (90 يوماً)',
              child: buys.isEmpty
                  ? const Text('لا توجد مشتريات.')
                  : Column(
                      children: [
                        for (final b in buys)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.local_shipping, color: Brand.info),
                            title: Text('${liters(b['quantity_ml'] as int)} × ${money(b['price_per_liter'] as int)}'),
                            subtitle: Text(
                              [
                                '${b['purchase_date']}',
                                if (b['supplier_name'] != null) '${b['supplier_name']}',
                                PayMethod.labels[b['pay_method']] ?? '',
                                if (b['invoice_no'] != null) 'فاتورة ${b['invoice_no']}',
                              ].join(' · '),
                            ),
                            trailing: Text(
                              money(b['total'] as int),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
            ),
            Section(
              title: 'الاستهلاك (90 يوماً)',
              child: uses.isEmpty
                  ? const Text('لا يوجد استهلاك مسجل.')
                  : Column(
                      children: [
                        for (final u in uses)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              u['source'] == FuelSource.sensor ? Icons.sensors : Icons.edit_note,
                              color: Brand.warning,
                            ),
                            title: Text(liters(u['quantity_ml'] as int)),
                            subtitle: Text(
                              [
                                '${u['consumption_date']}',
                                FuelSource.labels[u['source']] ?? '',
                                if (u['run_hours_x100'] != null)
                                  '${((u['run_hours_x100'] as int) / 100).toStringAsFixed(1)} ساعة',
                              ].join(' · '),
                            ),
                            trailing: app.can(Perm.financeView) ? Text(money(u['cost'] as int)) : null,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _purchase(BuildContext context, AppState app, String g) async {
    final sup = await app.os.finance.listSuppliers(g);
    if (!context.mounted) return;
    final v = await showFormDialog(
      context,
      title: 'شراء كاز',
      fields: [
        const FieldSpec('liters', 'الكمية (لتر)', type: FieldType.number, required: true),
        const FieldSpec('price', 'سعر اللتر', type: FieldType.money, required: true),
        FieldSpec(
          'supplier',
          'المجهز',
          type: FieldType.dropdown,
          options: {for (final s in sup) s['id'] as String: '${s['name']}'},
        ),
        const FieldSpec(
          'pay',
          'طريقة الدفع',
          type: FieldType.dropdown,
          required: true,
          initial: PayMethod.cash,
          options: PayMethod.labels,
        ),
        const FieldSpec('invoice', 'رقم الفاتورة'),
        FieldSpec('date', 'التاريخ', type: FieldType.date, initial: ymd(DateTime.now())),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.fuel.purchase(
        generatorId: g,
        quantityMl: litersToMl(parseNum(v['liters'])!),
        pricePerLiter: parseMoney(v['price'])!,
        supplierId: emptyToNull(v['supplier']),
        payMethod: v['pay']!,
        invoiceNo: emptyToNull(v['invoice']),
        date: emptyToNull(v['date']),
      ),
      success: 'تم تسجيل الشراء',
    );
    setState(() => _rev++);
  }

  Future<void> _consume(BuildContext context, AppState app, String g) async {
    final v = await showFormDialog(
      context,
      title: 'تسجيل استهلاك',
      note: 'هذا إدخال يدوي. القراءات الآلية تأتي فقط من جهاز مراقبة مربوط.',
      fields: [
        const FieldSpec('liters', 'الكمية المستهلكة (لتر)', type: FieldType.number, required: true),
        const FieldSpec('hours', 'ساعات التشغيل المقابلة (اختياري)', type: FieldType.number),
        FieldSpec('date', 'التاريخ', type: FieldType.date, initial: ymd(DateTime.now())),
        const FieldSpec('notes', 'ملاحظات'),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.fuel.consume(
        generatorId: g,
        quantityMl: litersToMl(parseNum(v['liters'])!),
        runHours: parseNum(v['hours']),
        date: emptyToNull(v['date']),
        notes: emptyToNull(v['notes']),
      ),
      success: 'تم تسجيل الاستهلاك',
    );
    setState(() => _rev++);
  }

  Future<void> _dip(BuildContext context, AppState app, String g) async {
    final v = await showFormDialog(
      context,
      title: 'قياس فعلي للخزان',
      fields: const [
        FieldSpec('liters', 'الكمية المقاسة (لتر)', type: FieldType.number, required: true),
        FieldSpec('notes', 'طريقة القياس / ملاحظات'),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.fuel.recordDip(g, litersToMl(parseNum(v['liters'])!), notes: emptyToNull(v['notes'])),
      success: 'تم تسجيل القياس',
    );
    setState(() => _rev++);
  }
}
