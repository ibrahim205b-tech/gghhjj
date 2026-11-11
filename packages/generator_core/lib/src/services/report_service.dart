import '../security/permissions.dart';
import '../util/dates.dart';
import 'context.dart';
import 'ledger_service.dart';
import 'subscriber_service.dart';

class PnL {
  final int revenue; // subscription revenue net of discounts + other revenue
  final int expenses;
  int get profit => revenue - expenses;
  const PnL(this.revenue, this.expenses);
}

class DashboardData {
  final int collectionsToday;
  final int expensesToday;
  final int collectionsMonth;
  final PnL month;
  final int totalDebt;
  final Map<String, int> subscriberCounts;
  final int fuelBookMl;
  final double runHoursToday;
  final double runHoursMonth;
  final List<Map<String, Object?>> recentPayments;
  final List<Map<String, Object?>> collectors;
  final int openFaults;
  final List<Map<String, Object?>> upcomingMaintenance;
  final int unreadAlerts;
  final bool financeVisible;
  const DashboardData({
    required this.collectionsToday,
    required this.expensesToday,
    required this.collectionsMonth,
    required this.month,
    required this.totalDebt,
    required this.subscriberCounts,
    required this.fuelBookMl,
    required this.runHoursToday,
    required this.runHoursMonth,
    required this.recentPayments,
    required this.collectors,
    required this.openFaults,
    required this.upcomingMaintenance,
    required this.unreadAlerts,
    required this.financeVisible,
  });
}

enum Granularity { day, month, year }

class SeriesPoint {
  final String label;
  final int collections;
  final int revenue;
  final int expenses;
  int get profit => revenue - expenses;
  const SeriesPoint(this.label, this.collections, this.revenue, this.expenses);
}

/// Read-only reporting. All numbers come from the ledger and source tables;
/// nothing here estimates or invents figures.
class ReportService {
  final CoreContext ctx;
  final LedgerService ledger;
  final SubscriberService subscribers;
  ReportService(this.ctx, this.ledger, this.subscribers);

  /// Accrual P&L for a generator (or all accessible ones when null).
  Future<PnL> pnl(String? generatorId, DateRange r) async {
    ctx.require(Perm.financeView);
    // Revenue accounts are credit-normal: revenue = -(debit - credit).
    final rev = -(await ledger.typeBalance(generatorId, AccountType.revenue, from: r.from, to: r.to));
    final exp = await ledger.typeBalance(generatorId, AccountType.expense, from: r.from, to: r.to);
    return PnL(rev, exp);
  }

  /// Cash collected from subscribers (net of reversals).
  Future<int> collections(String generatorId, DateRange r, {String? collectorId}) async {
    final q = await ctx.db.rawQuery('''SELECT COALESCE(SUM(CASE WHEN reversal_of IS NULL THEN amount ELSE -amount END),0) s
        FROM payments WHERE generator_id = ? AND pay_date BETWEEN ? AND ? ${collectorId != null ? 'AND collector_id = ?' : ''}''',
        [generatorId, r.from, r.to, if (collectorId != null) collectorId]);
    return q.first['s'] as int;
  }

  Future<int> totalDebt(String generatorId) async {
    // Only positive balances count as debt; advance payments are not netted.
    final r = await ctx.db.rawQuery('''SELECT COALESCE(SUM(b),0) t FROM (SELECT SUM(debit - credit) b FROM journal_lines
        WHERE account_id = ? AND party_type = 'subscriber' GROUP BY party_id HAVING b > 0)''',
        [LedgerService.accountId(generatorId, Acc.receivables)]);
    return r.first['t'] as int;
  }

  Future<List<Map<String, Object?>>> debtors(String generatorId, {String? areaId, int limit = 500}) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT s.id, s.account_no, s.full_name, s.phone, a.name AS area_name, c.code AS cabinet_code,
        SUM(l.debit - l.credit) AS balance FROM journal_lines l JOIN subscribers s ON s.id = l.party_id
        LEFT JOIN areas a ON a.id = s.area_id LEFT JOIN cabinets c ON c.id = s.cabinet_id
        WHERE l.account_id = ? AND l.party_type = 'subscriber' ${areaId != null ? 'AND s.area_id = ?' : ''}
        GROUP BY s.id HAVING balance > 0 ORDER BY balance DESC LIMIT ?''',
        [LedgerService.accountId(generatorId, Acc.receivables), if (areaId != null) areaId, limit]);
  }

  Future<List<Map<String, Object?>>> debtByArea(String generatorId) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT COALESCE(a.name, 'بدون منطقة') AS area, COUNT(*) AS debtors, SUM(b) AS debt FROM (
        SELECT l.party_id, SUM(l.debit - l.credit) b FROM journal_lines l WHERE l.account_id = ? AND l.party_type = 'subscriber'
        GROUP BY l.party_id HAVING b > 0) d JOIN subscribers s ON s.id = d.party_id LEFT JOIN areas a ON a.id = s.area_id
        GROUP BY a.id ORDER BY debt DESC''', [LedgerService.accountId(generatorId, Acc.receivables)]);
  }

  Future<List<Map<String, Object?>>> expensesByAccount(String generatorId, DateRange r) {
    ctx.require(Perm.financeView);
    return ctx.db.rawQuery('''SELECT a.code, a.name, SUM(l.debit - l.credit) AS amount FROM journal_lines l
        JOIN accounts a ON a.id = l.account_id WHERE l.generator_id = ? AND a.type = 'expense'
        AND l.entry_date BETWEEN ? AND ? GROUP BY a.id HAVING amount != 0 ORDER BY amount DESC''',
        [generatorId, r.from, r.to]);
  }

  Future<int> _expenses(String generatorId, DateRange r) =>
      ledger.typeBalance(generatorId, AccountType.expense, from: r.from, to: r.to);

  Future<DashboardData> dashboard(String generatorId) async {
    ctx.require(Perm.dashboardView);
    ctx.requireGenerator(generatorId);
    final today = DateRange.day(ctx.now);
    final month = DateRange.month(ctx.now);
    final fin = ctx.can(Perm.financeView);
    final fuel = await ctx.db.rawQuery('''SELECT
        (SELECT COALESCE(SUM(quantity_ml),0) FROM fuel_purchases WHERE generator_id = ?) -
        (SELECT COALESCE(SUM(quantity_ml),0) FROM fuel_consumptions WHERE generator_id = ?) AS ml''',
        [generatorId, generatorId]);
    final recent = await ctx.db.rawQuery('''SELECT p.*, s.full_name, c.full_name AS collector_name FROM payments p
        JOIN subscribers s ON s.id = p.subscriber_id LEFT JOIN collectors c ON c.id = p.collector_id
        WHERE p.generator_id = ? ORDER BY p.paid_at DESC LIMIT 8''', [generatorId]);
    final collectors = await ctx.db.rawQuery('''SELECT c.id, c.full_name,
        COALESCE(SUM(CASE WHEN p.reversal_of IS NULL THEN p.amount ELSE -p.amount END),0) AS collected, COUNT(p.id) AS receipts
        FROM collectors c JOIN payments p ON p.collector_id = c.id AND p.generator_id = ? AND p.pay_date BETWEEN ? AND ?
        GROUP BY c.id ORDER BY collected DESC LIMIT 5''', [generatorId, month.from, month.to]);
    final faults = await ctx.db.rawQuery(
        "SELECT COUNT(*) c FROM fault_records WHERE generator_id = ? AND status = 'open'", [generatorId]);
    final alerts = await ctx.db.rawQuery(
        'SELECT COUNT(*) c FROM notifications WHERE read = 0 AND (generator_id = ? OR generator_id IS NULL)', [generatorId]);
    return DashboardData(
      collectionsToday: await collections(generatorId, today),
      expensesToday: fin ? await _expenses(generatorId, today) : 0,
      collectionsMonth: await collections(generatorId, month),
      month: fin ? await pnl(generatorId, month) : const PnL(0, 0),
      totalDebt: await totalDebt(generatorId),
      subscriberCounts: await subscribers.counts(generatorId),
      fuelBookMl: fuel.first['ml'] as int,
      runHoursToday: await _runHours(generatorId, today),
      runHoursMonth: await _runHours(generatorId, month),
      recentPayments: recent,
      collectors: collectors,
      openFaults: faults.first['c'] as int,
      upcomingMaintenance: const [],
      unreadAlerts: alerts.first['c'] as int,
      financeVisible: fin,
    );
  }

  Future<double> _runHours(String generatorId, DateRange r) async {
    final rows = await ctx.db.query('generator_runs',
        where: 'generator_id = ? AND started_at >= ? AND started_at <= ?',
        whereArgs: [generatorId, r.from, '${r.to}T23:59:59']);
    var minutes = 0;
    for (final row in rows) {
      final s = DateTime.parse(row['started_at'] as String);
      final e = row['stopped_at'] == null ? ctx.now : DateTime.parse(row['stopped_at'] as String);
      minutes += e.difference(s).inMinutes;
    }
    return minutes / 60;
  }

  /// Time series for charts: daily (last [count] days), monthly (last
  /// [count] months) or yearly (last [count] years).
  Future<List<SeriesPoint>> series(String generatorId, Granularity g, {int count = 14}) async {
    ctx.require(Perm.financeView);
    ctx.requireGenerator(generatorId);
    final now = ctx.now;
    final ranges = <(String, DateRange)>[];
    for (var i = count - 1; i >= 0; i--) {
      switch (g) {
        case Granularity.day:
          final d = DateTime(now.year, now.month, now.day - i);
          ranges.add((ymd(d).substring(5), DateRange.day(d)));
        case Granularity.month:
          final d = DateTime(now.year, now.month - i, 1);
          ranges.add((periodOf(d), DateRange.month(d)));
        case Granularity.year:
          final d = DateTime(now.year - i, 1, 1);
          ranges.add(('${d.year}', DateRange.year(d)));
      }
    }
    final out = <SeriesPoint>[];
    for (final (label, r) in ranges) {
      final p = await pnl(generatorId, r);
      out.add(SeriesPoint(label, await collections(generatorId, r), p.revenue, p.expenses));
    }
    return out;
  }

  /// Side-by-side comparison of all accessible generators.
  Future<List<Map<String, Object?>>> compareGenerators(DateRange r) async {
    ctx.require(Perm.financeView);
    final gens = (await ctx.db.query('generators', where: 'active = 1'))
        .where((g) => ctx.canAccessGenerator(g['id'] as String));
    final out = <Map<String, Object?>>[];
    for (final g in gens) {
      final id = g['id'] as String;
      final p = await pnl(id, r);
      final counts = await subscribers.counts(id);
      final fuel = await ctx.db.rawQuery('''SELECT COALESCE(SUM(quantity_ml),0) ml FROM fuel_consumptions
          WHERE generator_id = ? AND consumption_date BETWEEN ? AND ?''', [id, r.from, r.to]);
      final faults = await ctx.db.rawQuery('''SELECT COUNT(*) c FROM fault_records WHERE generator_id = ?
          AND occurred_at >= ? AND occurred_at <= ?''', [id, r.from, '${r.to}T23:59:59']);
      out.add({
        'id': id,
        'name': g['name'],
        'revenue': p.revenue,
        'expenses': p.expenses,
        'profit': p.profit,
        'collections': await collections(id, r),
        'debt': await totalDebt(id),
        'fuel_ml': fuel.first['ml'],
        'run_hours': await _runHours(id, r),
        'faults': faults.first['c'],
        'subscribers': counts['active'],
      });
    }
    return out;
  }

  Future<List<Map<String, Object?>>> collectionsReport(String generatorId, DateRange r, {String? collectorId}) {
    ctx.require(Perm.reportsView);
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT p.pay_date, p.receipt_no, s.account_no, s.full_name, a.name AS area_name,
        c.full_name AS collector_name, CASE WHEN p.reversal_of IS NULL THEN p.amount ELSE -p.amount END AS amount
        FROM payments p JOIN subscribers s ON s.id = p.subscriber_id LEFT JOIN areas a ON a.id = s.area_id
        LEFT JOIN collectors c ON c.id = p.collector_id
        WHERE p.generator_id = ? AND p.pay_date BETWEEN ? AND ? ${collectorId != null ? 'AND p.collector_id = ?' : ''}
        ORDER BY p.pay_date, p.paid_at''', [generatorId, r.from, r.to, if (collectorId != null) collectorId]);
  }

  Future<List<Map<String, Object?>>> subscribersReport(String generatorId) {
    ctx.require(Perm.reportsView);
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT s.account_no, s.full_name, s.phone, a.name AS area_name, c.code AS cabinet_code,
        s.amps, s.amp_price, s.status,
        COALESCE((SELECT SUM(debit - credit) FROM journal_lines jl WHERE jl.account_id = ? AND jl.party_type = 'subscriber'
          AND jl.party_id = s.id), 0) AS balance
        FROM subscribers s LEFT JOIN areas a ON a.id = s.area_id LEFT JOIN cabinets c ON c.id = s.cabinet_id
        WHERE s.generator_id = ? AND s.status != 'transferred' ORDER BY CAST(s.account_no AS INTEGER)''',
        [LedgerService.accountId(generatorId, Acc.receivables), generatorId]);
  }

  Future<List<Map<String, Object?>>> journal(String generatorId, DateRange r) {
    ctx.require(Perm.financeView);
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT e.entry_date, e.id AS entry_id, e.description, a.code, a.name AS account_name,
        l.debit, l.credit FROM journal_entries e JOIN journal_lines l ON l.entry_id = e.id
        JOIN accounts a ON a.id = l.account_id WHERE e.generator_id = ? AND e.entry_date BETWEEN ? AND ?
        ORDER BY e.entry_date, e.created_at, l.id''', [generatorId, r.from, r.to]);
  }
}

/// RFC 4180 CSV writer with a UTF-8 BOM so Excel opens Arabic correctly.
String toCsv(List<String> headers, List<List<Object?>> rows) {
  String esc(Object? v) {
    final s = v?.toString() ?? '';
    if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  final b = StringBuffer('﻿');
  b.writeln(headers.map(esc).join(','));
  for (final r in rows) {
    b.writeln(r.map(esc).join(','));
  }
  return b.toString();
}
