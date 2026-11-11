import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class CollectorsScreen extends StatefulWidget {
  const CollectorsScreen({super.key});
  @override
  State<CollectorsScreen> createState() => _CollectorsScreenState();
}

class _CollectorsScreenState extends State<CollectorsScreen> {
  int _rev = 0;
  bool _month = true;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final range = _month ? DateRange.month(DateTime.now()) : DateRange.day(DateTime.now());
    return Scaffold(
      floatingActionButton: app.can(Perm.collectorsManage)
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, app),
              icon: const Icon(Icons.person_add),
              label: const Text('جابي جديد'),
            )
          : null,
      body: Loader<List<Map<String, Object?>>>(
        key: ValueKey('$_rev$_month'),
        load: () => app.os.collection.collectorPerformance(g, range),
        builder: (context, rows, reload) => PageBody(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('اليوم')),
                ButtonSegment(value: true, label: Text('هذا الشهر')),
              ],
              selected: {_month},
              onSelectionChanged: (s) => setState(() => _month = s.first),
            ),
            if (rows.isEmpty) const EmptyState(icon: Icons.badge, title: 'لا يوجد جباة مسجلون'),
            for (final c in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.badge)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${c['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          if (c['last_handover'] != null)
                            Text('آخر تسليم ${c['last_handover']}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      StatGrid(
                        children: [
                          StatCard(
                            label: 'المحصل',
                            value: money(c['collected'] as int),
                            icon: Icons.south_west,
                            color: Brand.success,
                            hint: '${c['receipts']} وصل',
                          ),
                          StatCard(
                            label: 'المسلّم للصندوق',
                            value: money(c['handed_over'] as int),
                            icon: Icons.move_to_inbox,
                            color: Brand.info,
                          ),
                          StatCard(
                            label: 'الرصيد بعهدته',
                            value: money(c['custody'] as int),
                            icon: Icons.account_balance_wallet,
                            color: (c['custody'] as int) > 0 ? Brand.warning : Brand.success,
                          ),
                          StatCard(
                            label: 'العمولة (${c['commission_percent']}%)',
                            value: money(c['commission'] as int),
                            icon: Icons.percent,
                            color: Brand.primary,
                            hint: 'الراتب ${money(c['monthly_salary'] as int)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (app.can(Perm.cashboxManage) && (c['custody'] as int) > 0)
                            FilledButton.icon(
                              icon: const Icon(Icons.move_to_inbox),
                              label: const Text('استلام المبالغ'),
                              onPressed: () async {
                                final v = await showFormDialog(
                                  context,
                                  title: 'استلام من ${c['full_name']}',
                                  fields: [
                                    FieldSpec(
                                      'amount',
                                      'المبلغ المستلم',
                                      type: FieldType.money,
                                      required: true,
                                      initial: '${c['custody']}',
                                    ),
                                    const FieldSpec('notes', 'ملاحظات'),
                                  ],
                                );
                                if (v == null || !context.mounted) return;
                                await guard(
                                  context,
                                  () => app.os.collection.handover(
                                    generatorId: g,
                                    collectorId: c['id'] as String,
                                    amount: parseMoney(v['amount'])!,
                                    notes: emptyToNull(v['notes']),
                                  ),
                                  success: 'تم الاستلام وتسجيله في الصندوق',
                                );
                                setState(() => _rev++);
                              },
                            ),
                          if (app.can(Perm.collectorsManage))
                            OutlinedButton.icon(
                              icon: const Icon(Icons.map),
                              label: const Text('المناطق المخصصة'),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => _AssignmentsScreen(collector: c)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, AppState app) async {
    final users = (app.can(Perm.usersManage) ? await app.os.auth.listUsers() : <Map<String, Object?>>[])
        .where((u) => u['role_id'] == roleCollector)
        .toList();
    if (!context.mounted) return;
    final v = await showFormDialog(
      context,
      title: 'جابي جديد',
      fields: [
        const FieldSpec('name', 'الاسم الكامل', required: true),
        const FieldSpec('phone', 'رقم الهاتف', type: FieldType.phone),
        FieldSpec(
          'user',
          'حساب الدخول (دور الجابي)',
          type: FieldType.dropdown,
          options: {for (final u in users) u['id'] as String: '${u['full_name']} (${u['username']})'},
        ),
        const FieldSpec('commission', 'نسبة العمولة %', type: FieldType.number, initial: '0'),
        const FieldSpec('salary', 'الراتب الشهري', type: FieldType.money, initial: '0'),
      ],
      note: 'لإنشاء حساب دخول للجابي أضفه أولاً من "المستخدمون والصلاحيات" بدور الجابي.',
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.collection.createCollector(
        fullName: v['name']!,
        phone: emptyToNull(v['phone']),
        userId: emptyToNull(v['user']),
        commissionPercent: parseMoney(v['commission']) ?? 0,
        monthlySalary: parseMoney(v['salary']) ?? 0,
      ),
      success: 'تمت إضافة الجابي',
    );
    setState(() => _rev++);
  }
}

class _AssignmentsScreen extends StatefulWidget {
  final Map<String, Object?> collector;
  const _AssignmentsScreen({required this.collector});
  @override
  State<_AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<_AssignmentsScreen> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final id = widget.collector['id'] as String;
    return Scaffold(
      appBar: AppBar(title: Text('مناطق ${widget.collector['full_name']}')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final areas = await app.os.network.listAreas(g);
          final cabs = await app.os.network.listCabinets(g);
          if (!context.mounted) return;
          final v = await showFormDialog(
            context,
            title: 'تخصيص منطقة أو كابينة',
            fields: [
              FieldSpec(
                'area',
                'المنطقة',
                type: FieldType.dropdown,
                options: {for (final a in areas) a['id'] as String: a['name'] as String},
              ),
              FieldSpec(
                'cab',
                'أو كابينة محددة',
                type: FieldType.dropdown,
                options: {for (final c in cabs) c['id'] as String: c['code'] as String},
              ),
            ],
            note: 'اترك الحقلين فارغين لتخصيص كل مشتركي المولدة لهذا الجابي.',
          );
          if (v == null || !context.mounted) return;
          await guard(
            context,
            () => app.os.collection.assign(id, g, areaId: emptyToNull(v['area']), cabinetId: emptyToNull(v['cab'])),
          );
          setState(() => _rev++);
        },
      ),
      body: Loader<List<Map<String, Object?>>>(
        key: ValueKey(_rev),
        load: () => app.os.collection.assignments(id),
        builder: (context, rows, _) => rows.isEmpty
            ? const EmptyState(
                icon: Icons.map,
                title: 'لا توجد مناطق مخصصة',
                subtitle: 'الجابي لن يرى أي مشترك حتى تخصص له منطقة.',
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final a in rows)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.place),
                        title: Text(
                          a['cabinet_code'] != null
                              ? 'كابينة ${a['cabinet_code']}'
                              : a['area_name'] != null
                              ? 'منطقة ${a['area_name']}'
                              : 'كل مشتركي ${a['generator_name']}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await guard(context, () => app.os.collection.unassign(a['id'] as String));
                            setState(() => _rev++);
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
