import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../services/pdf_service.dart';
import '../../theme.dart';
import '../common.dart';
import '../payment_flow.dart';

class CashboxScreen extends StatefulWidget {
  const CashboxScreen({super.key});
  @override
  State<CashboxScreen> createState() => _CashboxScreenState();
}

class _CashboxScreenState extends State<CashboxScreen> {
  String? _box;
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final today = ymd(DateTime.now());
    return Loader<List<Map<String, Object?>>>(
      key: ValueKey('boxes$_rev'),
      load: () => app.os.network.listCashboxes(g),
      builder: (context, boxes, _) {
        final box = boxes.any((b) => b['id'] == _box) ? _box! : boxes.first['id'] as String;
        return Loader<(int, CashReconciliation, List<Map<String, Object?>>, List<Map<String, Object?>>)>(
          key: ValueKey('$box$_rev'),
          load: () async => (
            await app.os.finance.cashboxBalance(box),
            await app.os.finance.reconcile(box, today),
            await app.os.finance.cashboxMovements(box, DateRange.lastDays(DateTime.now(), 30)),
            await app.os.finance.closings(g),
          ),
          builder: (context, d, _) {
            final (bal, rec, moves, closings) = d;
            return PageBody(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: box,
                        decoration: const InputDecoration(labelText: 'الصندوق'),
                        items: [
                          for (final b in boxes)
                            DropdownMenuItem(value: b['id'] as String, child: Text('${b['name']}')),
                        ],
                        onChanged: (v) => setState(() => _box = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'صندوق جديد',
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        final v = await showFormDialog(
                          context,
                          title: 'صندوق جديد',
                          fields: const [FieldSpec('name', 'اسم الصندوق', required: true)],
                        );
                        if (v == null || !context.mounted) return;
                        await guard(context, () => app.os.network.createCashbox(g, v['name']!));
                        setState(() => _rev++);
                      },
                    ),
                  ],
                ),
                StatGrid(
                  children: [
                    StatCard(
                      label: 'الرصيد الدفتري',
                      value: money(bal),
                      icon: Icons.account_balance_wallet,
                      color: Brand.primary,
                    ),
                    StatCard(
                      label: 'رصيد أول اليوم',
                      value: money(rec.opening),
                      icon: Icons.wb_twilight,
                      color: Brand.info,
                    ),
                    StatCard(
                      label: 'مقبوضات اليوم',
                      value: money(rec.receipts),
                      icon: Icons.south_west,
                      color: Brand.success,
                    ),
                    StatCard(
                      label: 'مدفوعات اليوم',
                      value: money(rec.disbursements),
                      icon: Icons.north_east,
                      color: Brand.danger,
                    ),
                  ],
                ),
                Section(
                  title: 'مطابقة وإغلاق اليوم',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'المتوقع = الرصيد الافتتاحي (${money(rec.opening)}) + المقبوضات (${money(rec.receipts)}) '
                        '− المدفوعات والمسحوبات (${money(rec.disbursements)}) = ${money(rec.expected)}',
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        icon: const Icon(Icons.fact_check),
                        label: const Text('عدّ النقد وإغلاق اليوم'),
                        onPressed: () async {
                          final v = await showFormDialog(
                            context,
                            title: 'إغلاق صندوق اليوم',
                            note: 'المتوقع: ${money(rec.expected)}',
                            fields: const [
                              FieldSpec('counted', 'النقد المعدود فعلياً', type: FieldType.money, required: true),
                              FieldSpec('notes', 'ملاحظات (إلزامية عند وجود فرق)', type: FieldType.multiline),
                            ],
                          );
                          if (v == null || !context.mounted) return;
                          Map<String, Object?>? r;
                          await guard(
                            context,
                            () async => r = await app.os.finance.closeDay(
                              box,
                              counted: parseMoney(v['counted'])!,
                              notes: emptyToNull(v['notes']),
                            ),
                          );
                          if (r != null && context.mounted) {
                            final diff = r!['difference'] as int;
                            showOk(
                              context,
                              diff == 0 ? 'الصندوق مطابق ✔' : 'تم الإغلاق مع فرق ${money(diff)} وسُجل قيد تسوية',
                            );
                            setState(() => _rev++);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in CashOp.labels.entries)
                      OutlinedButton(
                        onPressed: () => _cashOp(context, app, g, box, boxes, e.key),
                        child: Text(e.value),
                      ),
                  ],
                ),
                Section(
                  title: 'حركات آخر 30 يوماً',
                  actions: [
                    IconButton(
                      tooltip: 'طباعة تقرير الصندوق',
                      icon: const Icon(Icons.print),
                      onPressed: () => printOrShare(
                        context,
                        (_) => PdfService.table(
                          'تقرير الصندوق',
                          'آخر 30 يوماً — الرصيد ${money(bal)}',
                          ['التاريخ', 'البيان', 'داخل', 'خارج'],
                          [
                            for (final m in moves)
                              [
                                '${m['entry_date']}',
                                '${m['description']}',
                                (m['debit'] as int) > 0 ? money(m['debit'] as int) : '',
                                (m['credit'] as int) > 0 ? money(m['credit'] as int) : '',
                              ],
                          ],
                        ),
                        'cashbox',
                      ),
                    ),
                  ],
                  child: moves.isEmpty
                      ? const EmptyState(icon: Icons.swap_vert, title: 'لا توجد حركات')
                      : Column(
                          children: [
                            for (final m in moves.take(100))
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  (m['debit'] as int) > 0 ? Icons.south_west : Icons.north_east,
                                  color: (m['debit'] as int) > 0 ? Brand.success : Brand.danger,
                                ),
                                title: Text('${m['description']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${m['entry_date']}${m['reversed'] == 1 ? ' · ملغى بقيد عكسي' : ''}'),
                                trailing: Text(
                                  money((m['debit'] as int) - (m['credit'] as int)),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                onLongPress:
                                    app.can(Perm.paymentsReverse) &&
                                        m['reversed'] != 1 &&
                                        m['reverses_id'] == null &&
                                        (m['source_type'] as String).startsWith('cash_op')
                                    ? () async {
                                        final v = await showFormDialog(
                                          context,
                                          title: 'إلغاء العملية بقيد عكسي',
                                          fields: const [FieldSpec('reason', 'السبب', required: true)],
                                        );
                                        if (v == null || !context.mounted) return;
                                        await guard(
                                          context,
                                          () => app.os.finance.reverseEntry(
                                            m['entry_id'] as String,
                                            reason: v['reason']!,
                                          ),
                                        );
                                        setState(() => _rev++);
                                      }
                                    : null,
                              ),
                          ],
                        ),
                ),
                Section(
                  title: 'سجل الإغلاقات اليومية',
                  child: closings.isEmpty
                      ? const Text('لا توجد إغلاقات بعد.')
                      : Column(
                          children: [
                            for (final c in closings)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text('${c['close_date']} — ${c['cashbox_name']}'),
                                subtitle: Text(
                                  'المتوقع ${money(c['expected'] as int)} · المعدود ${money(c['counted'] as int)}'
                                  '${c['notes'] != null ? '\n${c['notes']}' : ''}',
                                ),
                                trailing: (c['difference'] as int) == 0
                                    ? const StatusChip('مطابق', Brand.success)
                                    : StatusChip('فرق ${money(c['difference'] as int)}', Brand.danger),
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _cashOp(
    BuildContext context,
    AppState app,
    String g,
    String box,
    List<Map<String, Object?>> boxes,
    String kind,
  ) async {
    final suppliers = kind == CashOp.supplierPayment
        ? await app.os.finance.listSuppliers(g)
        : const <Map<String, Object?>>[];
    final employees = kind == CashOp.employeeAdvance || kind == CashOp.advanceRepayment
        ? await app.os.finance.listEmployees(g)
        : const <Map<String, Object?>>[];
    if (!context.mounted) return;
    final v = await showFormDialog(
      context,
      title: CashOp.labels[kind]!,
      fields: [
        const FieldSpec('amount', 'المبلغ', type: FieldType.money, required: true),
        if (kind == CashOp.supplierPayment)
          FieldSpec(
            'supplier',
            'المجهز',
            type: FieldType.dropdown,
            required: true,
            options: {for (final s in suppliers) s['id'] as String: '${s['name']} (مستحق ${money(s['owed'] as int)})'},
          ),
        if (employees.isNotEmpty || kind == CashOp.employeeAdvance || kind == CashOp.advanceRepayment)
          FieldSpec(
            'employee',
            'الموظف',
            type: FieldType.dropdown,
            required: true,
            options: {for (final e in employees) e['id'] as String: '${e['full_name']}'},
          ),
        if (kind == CashOp.transfer)
          FieldSpec(
            'target',
            'إلى صندوق',
            type: FieldType.dropdown,
            required: true,
            options: {for (final b in boxes.where((b) => b['id'] != box)) b['id'] as String: '${b['name']}'},
          ),
        const FieldSpec('desc', 'البيان'),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.finance.cashOperation(
        generatorId: g,
        kind: kind,
        amount: parseMoney(v['amount'])!,
        cashboxId: box,
        supplierId: emptyToNull(v['supplier']),
        employeeId: emptyToNull(v['employee']),
        targetCashboxId: emptyToNull(v['target']),
        description: emptyToNull(v['desc']),
      ),
      success: 'تم تسجيل العملية',
    );
    setState(() => _rev++);
  }
}
