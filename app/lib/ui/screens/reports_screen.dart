import 'package:flutter/material.dart';
import 'package:generator_core/generator_core.dart';

import '../../app_state.dart';
import '../../services/export_service.dart';
import '../../services/pdf_service.dart';
import '../common.dart';
import '../payment_flow.dart';

class _Report {
  final String title;
  final bool needsFinance;
  final bool usesRange;
  final Future<(List<String>, List<List<Object?>>)> Function(AppState app, String g, DateRange r, String? filter) build;
  const _Report(this.title, this.build, {this.needsFinance = false, this.usesRange = true});
}

String _fmt(Object? v) =>
    v is int ? formatMoney(v, withCurrency: false) : (v is double ? v.toStringAsFixed(1) : '${v ?? ''}');

final _reports = <String, _Report>{
  'collections': _Report('تقرير الجباية', (app, g, r, f) async {
    final rows = await app.os.reports.collectionsReport(g, r, collectorId: f);
    return (
      ['التاريخ', 'الوصل', 'رقم الاشتراك', 'المشترك', 'المنطقة', 'الجابي', 'المبلغ'],
      [
        for (final x in rows)
          [
            x['pay_date'],
            x['receipt_no'],
            x['account_no'],
            x['full_name'],
            x['area_name'],
            x['collector_name'],
            x['amount'],
          ],
      ],
    );
  }),
  'pnl': _Report('الإيرادات والمصروفات والأرباح', needsFinance: true, (app, g, r, f) async {
    final p = await app.os.reports.pnl(g, r);
    final ex = await app.os.reports.expensesByAccount(g, r);
    final col = await app.os.reports.collections(g, r);
    return (
      ['البند', 'المبلغ'],
      [
        ['الإيرادات (الفواتير بعد الخصومات)', p.revenue],
        ['المقبوضات النقدية من المشتركين', col],
        for (final e in ex) ['مصروف: ${e['name']}', e['amount']],
        ['إجمالي المصروفات', p.expenses],
        ['صافي الربح', p.profit],
      ],
    );
  }),
  'debts': _Report('تقرير الديون', usesRange: false, (app, g, r, f) async {
    final rows = await app.os.reports.debtors(g, limit: 5000);
    return (
      ['رقم الاشتراك', 'المشترك', 'الهاتف', 'المنطقة', 'الكابينة', 'الدين'],
      [
        for (final x in rows)
          [x['account_no'], x['full_name'], x['phone'], x['area_name'], x['cabinet_code'], x['balance']],
      ],
    );
  }),
  'debt_area': _Report('الديون حسب المنطقة', usesRange: false, (app, g, r, f) async {
    final rows = await app.os.reports.debtByArea(g);
    return (
      ['المنطقة', 'عدد المديونين', 'الدين'],
      [
        for (final x in rows) [x['area'], x['debtors'], x['debt']],
      ],
    );
  }),
  'collectors': _Report('أداء الجباة', (app, g, r, f) async {
    final rows = await app.os.collection.collectorPerformance(g, r);
    return (
      ['الجابي', 'الوصولات', 'المحصل', 'المسلّم', 'بعهدته', 'العمولة'],
      [
        for (final x in rows)
          [x['full_name'], x['receipts'], x['collected'], x['handed_over'], x['custody'], x['commission']],
      ],
    );
  }),
  'fuel': _Report('تقرير الوقود', (app, g, r, f) async {
    final rows = await app.os.fuel.dailyConsumption(g, r);
    final buys = await app.os.fuel.purchases(g, r);
    return (
      ['البيان', 'التاريخ', 'الكمية (لتر)', 'الكلفة', 'المصدر/المجهز'],
      [
        for (final b in buys)
          ['شراء', b['purchase_date'], (b['quantity_ml'] as int) / 1000, b['total'], b['supplier_name']],
        for (final x in rows) ['استهلاك', x['day'], (x['ml'] as int) / 1000, x['cost'], ''],
      ],
    );
  }),
  'expenses': _Report('تقرير المصاريف', needsFinance: true, (app, g, r, f) async {
    final rows = await app.os.finance.listExpenses(g, r);
    return (
      ['التاريخ', 'التصنيف', 'البيان', 'طريقة الدفع', 'المجهز', 'المبلغ', 'ملغى'],
      [
        for (final x in rows)
          [
            x['expense_date'],
            ExpenseCategory.labels[x['category']],
            x['description'],
            PayMethod.labels[x['pay_method']],
            x['supplier_name'],
            x['amount'],
            x['reversed'] == 1 ? 'نعم' : '',
          ],
      ],
    );
  }),
  'maintenance': _Report('تقرير الصيانة', usesRange: false, (app, g, r, f) async {
    final rows = await app.os.operations.maintenanceRecords(g, limit: 1000);
    return (
      ['التاريخ', 'النوع', 'الفني', 'القطع', 'الكلفة', 'القادمة'],
      [
        for (final x in rows)
          [
            x['done_date'],
            MaintenanceKind.labels[x['kind']] ?? x['kind'],
            x['technician'],
            x['parts'],
            (x['parts_cost'] as int) + (x['labor_cost'] as int),
            x['next_due_date'],
          ],
      ],
    );
  }),
  'runs': _Report('ساعات التشغيل', (app, g, r, f) async {
    final rows = await app.os.operations.runs(g, r);
    return (
      ['البدء', 'الإطفاء', 'الساعات', 'سبب التوقف'],
      [
        for (final x in rows)
          [
            (x['started_at'] as String).substring(0, 16),
            x['stopped_at'] == null ? 'مستمر' : (x['stopped_at'] as String).substring(0, 16),
            x['stopped_at'] == null
                ? 0.0
                : DateTime.parse(x['stopped_at'] as String)
                          .difference(DateTime.parse(x['started_at'] as String))
                          .inMinutes /
                      60,
            x['stop_reason'],
          ],
      ],
    );
  }),
  'loads': _Report('تقرير الأحمال (نظري)', usesRange: false, (app, g, r, f) async {
    final rows = await app.os.network.cabinetLoads(g);
    return (
      ['الكابينة', 'المنطقة', 'المشتركون', 'الأمبيرات المتعاقد عليها', 'السعة'],
      [
        for (final x in rows) [x['code'], x['area_name'], x['subscribers'], x['contracted_amps'], x['max_amps']],
      ],
    );
  }),
  'subscribers': _Report('تقرير المشتركين', usesRange: false, (app, g, r, f) async {
    final rows = await app.os.reports.subscribersReport(g);
    return (
      ['الرقم', 'الاسم', 'الهاتف', 'المنطقة', 'الكابينة', 'الأمبير', 'السعر', 'الحالة', 'الرصيد'],
      [
        for (final x in rows)
          [
            x['account_no'],
            x['full_name'],
            x['phone'],
            x['area_name'],
            x['cabinet_code'],
            x['amps'],
            x['amp_price'],
            SubscriberStatus.labels[x['status']],
            x['balance'],
          ],
      ],
    );
  }),
  'cashbox': _Report('تقرير الصندوق', needsFinance: true, (app, g, r, f) async {
    final rows = await app.os.finance.cashboxMovements(NetworkService.mainCashbox(g), r);
    return (
      ['التاريخ', 'البيان', 'داخل', 'خارج'],
      [
        for (final x in rows) [x['entry_date'], x['description'], x['debit'], x['credit']],
      ],
    );
  }),
  'journal': _Report('دفتر اليومية (القيود)', needsFinance: true, (app, g, r, f) async {
    final rows = await app.os.reports.journal(g, r);
    return (
      ['التاريخ', 'القيد', 'البيان', 'الحساب', 'مدين', 'دائن'],
      [
        for (final x in rows)
          [
            x['entry_date'],
            x['entry_id'],
            x['description'],
            '${x['code']} ${x['account_name']}',
            x['debit'],
            x['credit'],
          ],
      ],
    );
  }),
  'trial': _Report('ميزان المراجعة', needsFinance: true, (app, g, r, f) async {
    final rows = await app.os.ledger.trialBalance(g, from: r.from, to: r.to);
    return (
      ['الرمز', 'الحساب', 'مدين', 'دائن', 'الرصيد'],
      [
        for (final x in rows)
          [x['code'], x['name'], x['debit'], x['credit'], (x['debit'] as int) - (x['credit'] as int)],
      ],
    );
  }),
  'compare': _Report('مقارنة المولدات', needsFinance: true, (app, g, r, f) async {
    final rows = await app.os.reports.compareGenerators(r);
    return (
      [
        'المولدة',
        'الإيرادات',
        'المصاريف',
        'الربح',
        'المقبوضات',
        'الديون',
        'الوقود (لتر)',
        'ساعات التشغيل',
        'الأعطال',
        'المشتركون',
      ],
      [
        for (final x in rows)
          [
            x['name'],
            x['revenue'],
            x['expenses'],
            x['profit'],
            x['collections'],
            x['debt'],
            (x['fuel_ml'] as int) / 1000,
            x['run_hours'],
            x['faults'],
            x['subscribers'],
          ],
      ],
    );
  }),
};

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _key = 'collections';
  String _rangeKey = 'month';
  DateRange? _custom;

  DateRange get _range {
    final n = DateTime.now();
    return switch (_rangeKey) {
      'today' => DateRange.day(n),
      'week' => DateRange.lastDays(n, 7),
      'last_month' => DateRange.month(DateTime(n.year, n.month - 1, 1)),
      'year' => DateRange.year(n),
      'custom' => _custom ?? DateRange.month(n),
      _ => DateRange.month(n),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final g = app.generatorId!;
    final available = _reports.entries.where((e) => !e.value.needsFinance || app.can(Perm.financeView)).toList();
    if (!available.any((e) => e.key == _key)) _key = available.first.key;
    final rep = _reports[_key]!;
    final range = _range;
    return PageBody(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                initialValue: _key,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'التقرير'),
                items: [for (final e in available) DropdownMenuItem(value: e.key, child: Text(e.value.title))],
                onChanged: (v) => setState(() => _key = v!),
              ),
            ),
            if (rep.usesRange)
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _rangeKey,
                  decoration: const InputDecoration(labelText: 'الفترة'),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('اليوم')),
                    DropdownMenuItem(value: 'week', child: Text('آخر 7 أيام')),
                    DropdownMenuItem(value: 'month', child: Text('هذا الشهر')),
                    DropdownMenuItem(value: 'last_month', child: Text('الشهر الماضي')),
                    DropdownMenuItem(value: 'year', child: Text('هذه السنة')),
                    DropdownMenuItem(value: 'custom', child: Text('فترة مخصصة')),
                  ],
                  onChanged: (v) async {
                    if (v == 'custom') {
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2015),
                        lastDate: DateTime(2100),
                      );
                      if (r == null) return;
                      _custom = DateRange(ymd(r.start), ymd(r.end));
                    }
                    setState(() => _rangeKey = v!);
                  },
                ),
              ),
            if (rep.usesRange) Text('${range.from} ← ${range.to}'),
          ],
        ),
        Loader<(List<String>, List<List<Object?>>)>(
          key: ValueKey('$_key$range$g'),
          load: () => rep.build(app, g, range, null),
          builder: (context, d, _) {
            final (headers, rows) = d;
            final strRows = [
              for (final r in rows) [for (final c in r) _fmt(c)],
            ];
            final name = '${rep.title} ${rep.usesRange ? range.toString() : ymd(DateTime.now())}';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      onPressed: () =>
                          sharePdf(context, (_) => PdfService.table(rep.title, name, headers, strRows), '$name.pdf'),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.grid_on),
                      label: const Text('Excel'),
                      onPressed: () => guard(
                        context,
                        () async => ExportService.share(await ExportService.xlsx(name, headers, rows)),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.table_view),
                      label: const Text('CSV'),
                      onPressed: () =>
                          guard(context, () async => ExportService.share(await ExportService.csv(name, headers, rows))),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('طباعة'),
                      onPressed: () =>
                          printOrShare(context, (_) => PdfService.table(rep.title, name, headers, strRows), name),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: DataTableCard(headers: headers, rows: strRows),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
