import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  int _rev = 0;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final month = DateRange.month(DateTime.now());
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'المصروفات'),
              Tab(text: 'المجهزون'),
              Tab(text: 'الموظفون'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // ------------------------------------------------ expenses
                Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: () => _addExpense(context, app, g),
                    icon: const Icon(Icons.add),
                    label: const Text('مصروف'),
                  ),
                  body: Loader<List<Map<String, Object?>>>(
                    key: ValueKey('e$_rev'),
                    load: () => app.os.finance.listExpenses(g, DateRange.lastDays(DateTime.now(), 90)),
                    builder: (context, rows, _) {
                      final monthTotal = rows
                          .where((r) => r['reversed'] != 1 && (r['expense_date'] as String).compareTo(month.from) >= 0)
                          .fold<int>(0, (a, r) => a + (r['amount'] as int));
                      return PageBody(
                        children: [
                          StatCard(
                            label: 'مصروفات هذا الشهر (بدون الوقود المستهلك)',
                            value: money(monthTotal),
                            icon: Icons.payments,
                            color: Brand.danger,
                          ),
                          if (rows.isEmpty)
                            const EmptyState(icon: Icons.receipt, title: 'لا توجد مصروفات خلال 90 يوماً'),
                          for (final r in rows)
                            Card(
                              child: ListTile(
                                leading: Icon(
                                  Icons.receipt_long,
                                  color: r['reversed'] == 1 ? Colors.grey : Brand.danger,
                                ),
                                title: Text(
                                  '${ExpenseCategory.labels[r['category']] ?? r['category']}'
                                  '${r['description'] != null ? ' — ${r['description']}' : ''}',
                                ),
                                subtitle: Text(
                                  [
                                    '${r['expense_date']}',
                                    PayMethod.labels[r['pay_method']] ?? '',
                                    if (r['supplier_name'] != null) '${r['supplier_name']}',
                                    if (r['employee_name'] != null) '${r['employee_name']}',
                                    if (r['reversed'] == 1) 'ملغى بقيد عكسي',
                                  ].join(' · '),
                                ),
                                trailing: Text(
                                  money(r['amount'] as int),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    decoration: r['reversed'] == 1 ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                onLongPress: r['reversed'] == 1 || !app.can(Perm.paymentsReverse)
                                    ? null
                                    : () async {
                                        final v = await showFormDialog(
                                          context,
                                          title: 'إلغاء المصروف بقيد عكسي',
                                          fields: const [FieldSpec('reason', 'السبب', required: true)],
                                        );
                                        if (v == null || !context.mounted) return;
                                        await guard(
                                          context,
                                          () => app.os.finance.reverseEntry('je:exp:${r['id']}', reason: v['reason']!),
                                        );
                                        setState(() => _rev++);
                                      },
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                // ------------------------------------------------ suppliers
                Scaffold(
                  floatingActionButton: FloatingActionButton(
                    child: const Icon(Icons.add_business),
                    onPressed: () async {
                      final v = await showFormDialog(
                        context,
                        title: 'مجهز جديد',
                        fields: const [
                          FieldSpec('name', 'الاسم', required: true),
                          FieldSpec('phone', 'الهاتف', type: FieldType.phone),
                          FieldSpec(
                            'kind',
                            'النوع',
                            type: FieldType.dropdown,
                            required: true,
                            initial: 'fuel',
                            options: {'fuel': 'وقود', 'parts': 'قطع غيار', 'services': 'خدمات', 'other': 'أخرى'},
                          ),
                        ],
                      );
                      if (v == null || !context.mounted) return;
                      await guard(
                        context,
                        () => app.os.finance.createSupplier(
                          g,
                          v['name']!,
                          phone: emptyToNull(v['phone']),
                          kind: v['kind']!,
                        ),
                      );
                      setState(() => _rev++);
                    },
                  ),
                  body: Loader<List<Map<String, Object?>>>(
                    key: ValueKey('s$_rev'),
                    load: () => app.os.finance.listSuppliers(g),
                    builder: (context, rows, _) => rows.isEmpty
                        ? const EmptyState(icon: Icons.store, title: 'لا يوجد مجهزون')
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (final s in rows)
                                Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.store),
                                    title: Text('${s['name']}'),
                                    subtitle: Text('${s['phone'] ?? ''}'),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          money(s['owed'] as int),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: (s['owed'] as int) > 0 ? Brand.danger : null,
                                          ),
                                        ),
                                        const Text('مستحق له', style: TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
                // ------------------------------------------------ employees
                Scaffold(
                  floatingActionButton: app.can(Perm.usersManage)
                      ? FloatingActionButton(
                          child: const Icon(Icons.person_add),
                          onPressed: () async {
                            final v = await showFormDialog(
                              context,
                              title: 'موظف جديد',
                              fields: const [
                                FieldSpec('name', 'الاسم الكامل', required: true),
                                FieldSpec('phone', 'الهاتف', type: FieldType.phone),
                                FieldSpec('job', 'الوظيفة'),
                                FieldSpec('salary', 'الراتب الشهري', type: FieldType.money),
                              ],
                            );
                            if (v == null || !context.mounted) return;
                            await guard(
                              context,
                              () => app.os.finance.createEmployee(
                                g,
                                v['name']!,
                                phone: emptyToNull(v['phone']),
                                job: emptyToNull(v['job']),
                                monthlySalary: parseMoney(v['salary']) ?? 0,
                              ),
                            );
                            setState(() => _rev++);
                          },
                        )
                      : null,
                  body: Loader<List<Map<String, Object?>>>(
                    key: ValueKey('m$_rev'),
                    load: () => app.os.finance.listEmployees(g),
                    builder: (context, rows, _) => rows.isEmpty
                        ? const EmptyState(icon: Icons.groups, title: 'لا يوجد موظفون')
                        : ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (final e in rows)
                                Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.engineering),
                                    title: Text('${e['full_name']}'),
                                    subtitle: Text('${e['job'] ?? ''} · الراتب ${money(e['monthly_salary'] as int)}'),
                                    trailing: Text('سلف ${money(e['advances'] as int)}'),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExpense(BuildContext context, AppState app, String g) async {
    final sup = await app.os.finance.listSuppliers(g);
    final emp = await app.os.finance.listEmployees(g);
    if (!context.mounted) return;
    final v = await showFormDialog(
      context,
      title: 'تسجيل مصروف',
      fields: [
        const FieldSpec(
          'category',
          'التصنيف',
          type: FieldType.dropdown,
          required: true,
          options: ExpenseCategory.labels,
        ),
        const FieldSpec('amount', 'المبلغ', type: FieldType.money, required: true),
        const FieldSpec(
          'pay',
          'طريقة الدفع',
          type: FieldType.dropdown,
          required: true,
          initial: PayMethod.cash,
          options: PayMethod.labels,
        ),
        FieldSpec(
          'supplier',
          'المجهز',
          type: FieldType.dropdown,
          options: {for (final s in sup) s['id'] as String: '${s['name']}'},
        ),
        FieldSpec(
          'employee',
          'الموظف (للرواتب)',
          type: FieldType.dropdown,
          options: {for (final e in emp) e['id'] as String: '${e['full_name']}'},
        ),
        FieldSpec('date', 'التاريخ', type: FieldType.date, initial: ymd(DateTime.now())),
        const FieldSpec('desc', 'البيان'),
        const FieldSpec('ref', 'رقم الفاتورة/المرجع'),
      ],
    );
    if (v == null || !context.mounted) return;
    await guard(
      context,
      () => app.os.finance.recordExpense(
        generatorId: g,
        category: v['category']!,
        amount: parseMoney(v['amount'])!,
        payMethod: v['pay']!,
        supplierId: emptyToNull(v['supplier']),
        employeeId: emptyToNull(v['employee']),
        description: emptyToNull(v['desc']),
        reference: emptyToNull(v['ref']),
        date: emptyToNull(v['date']),
      ),
      success: 'تم تسجيل المصروف',
    );
    setState(() => _rev++);
  }
}
