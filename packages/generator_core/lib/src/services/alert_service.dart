import 'package:sqflite_common/sqlite_api.dart';

import '../util/dates.dart';
import '../util/ids.dart';
import '../util/money.dart';
import 'context.dart';
import 'fuel_service.dart';
import 'network_service.dart';
import 'operations_service.dart';
import 'report_service.dart';

class AlertKind {
  static const debts = 'debts';
  static const fuelLow = 'fuel_low';
  static const maintenance = 'maintenance';
  static const overload = 'overload';
  static const syncStalled = 'sync_stalled';
  static const cashDifference = 'cash_difference';
  static const collectorLate = 'collector_late';
  static const security = 'security';
  static const complaint = 'complaint';
  static const fuelAnomaly = 'fuel_anomaly';

  static const labels = {
    debts: 'ديون المشتركين',
    fuelLow: 'انخفاض الكاز',
    maintenance: 'مواعيد الصيانة',
    overload: 'تجاوز الحمل',
    syncStalled: 'توقف المزامنة',
    cashDifference: 'اختلاف الصندوق',
    collectorLate: 'تأخر تسليم أموال الجابي',
    security: 'محاولات دخول غير طبيعية',
    complaint: 'الشكاوى الجديدة',
    fuelAnomaly: 'استهلاك وقود غير طبيعي',
  };
}

/// In-app notification centre. Checks are idempotent via dedupe keys.
class AlertService {
  final CoreContext ctx;
  final FuelService fuel;
  final OperationsService ops;
  final NetworkService network;
  final ReportService reports;
  AlertService(this.ctx, this.fuel, this.ops, this.network, this.reports);

  Future<bool> enabled(String kind) async {
    final r = await ctx.db.query('settings', where: 'key = ?', whereArgs: ['notify.$kind']);
    return r.isEmpty || r.first['value'] != '0';
  }

  Future<void> setEnabled(String kind, bool on) async {
    await ctx.db.insert('settings', {'key': 'notify.$kind', 'value': on ? '1' : '0', 'updated_at': ctx.nowIso},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> setting(String key, int fallback) async {
    final r = await ctx.db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? fallback : int.tryParse(r.first['value'] as String? ?? '') ?? fallback;
  }

  Future<void> _add(String? generatorId, String kind, String severity, String title, String body, String dedupe) async {
    if (!await enabled(kind)) return;
    await ctx.db.insert(
        'notifications',
        {
          'id': newId(), 'generator_id': generatorId, 'kind': kind, 'severity': severity, 'title': title,
          'body': body, 'created_at': ctx.nowIso, 'dedupe_key': dedupe,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Runs all checks for a generator. Returns the number of unread alerts.
  Future<int> runChecks(String generatorId) async {
    final today = ctx.today;
    final g = (await ctx.db.query('generators', where: 'id = ?', whereArgs: [generatorId])).first;

    // Fuel low (book stock vs threshold).
    final st = await fuel.stock(generatorId);
    final threshold = g['fuel_low_threshold_ml'] as int;
    if (st.bookMl <= threshold) {
      await _add(generatorId, AlertKind.fuelLow, 'high', 'انخفاض مخزون الكاز',
          'المخزون المسجل ${formatLiters(st.bookMl)} وهو أقل من حد التنبيه ${formatLiters(threshold)}.',
          'fuel:$generatorId:$today');
    }

    // Fuel anomalies over the last 30 days.
    final fs = await fuel.stats(generatorId, DateRange.lastDays(ctx.now, 30));
    for (final a in fs.anomalies) {
      await _add(generatorId, AlertKind.fuelAnomaly, 'normal', 'استهلاك وقود غير طبيعي',
          '${a['day']}: ${formatLiters(a['ml'] as int)} — ${a['reason']}', 'fuelanom:$generatorId:${a['day']}');
    }

    // Maintenance due.
    for (final m in await ops.upcomingMaintenance(generatorId, withinDays: 3)) {
      final kind = MaintenanceKind.labels[m['kind']] ?? m['kind'];
      await _add(generatorId, AlertKind.maintenance, m['overdue'] == true ? 'high' : 'normal',
          m['overdue'] == true ? 'صيانة متأخرة' : 'صيانة قريبة',
          '$kind${m['due_date'] != null ? ' — الموعد ${m['due_date']}' : ''}'
              '${m['hours_left'] != null ? ' — متبقي ${(m['hours_left'] as double).toStringAsFixed(0)} ساعة' : ''}',
          'maint:$generatorId:${m['kind']}:$today');
    }

    // Contracted load over cabinet capacity.
    for (final c in await network.cabinetLoads(generatorId)) {
      final max = c['max_amps'] as int;
      final load = c['contracted_amps'] as int;
      if (max > 0 && load > max) {
        await _add(generatorId, AlertKind.overload, 'high', 'تجاوز سعة الكابينة ${c['code']}',
            'مجموع الأمبيرات المشتركة $load أمبير يتجاوز السعة المحددة $max أمبير (حساب نظري وليس قياساً فعلياً).',
            'overload:${c['id']}:$load');
      }
    }

    // Debts above threshold.
    final debtLimit = await setting('alert.debt_limit', 100000);
    final debtors = await reports.debtors(generatorId, limit: 1000);
    final over = debtors.where((d) => (d['balance'] as int) >= debtLimit).length;
    if (over > 0) {
      await _add(generatorId, AlertKind.debts, 'normal', 'ديون مرتفعة',
          '$over مشترك تجاوز دينه ${formatMoney(debtLimit)}.', 'debts:$generatorId:${periodOf(ctx.now)}:$over');
    }

    // Collector holding money for more than N days.
    final lateDays = await setting('alert.handover_days', 2);
    final custody = await ctx.db.rawQuery('''SELECT c.id, c.full_name, SUM(l.debit - l.credit) AS bal,
        (SELECT MAX(h.handover_date) FROM collector_handovers h WHERE h.collector_id = c.id AND h.generator_id = ?) AS last_h,
        (SELECT MIN(p.pay_date) FROM payments p WHERE p.collector_id = c.id AND p.generator_id = ?) AS first_p
        FROM collectors c JOIN journal_lines l ON l.party_type = 'collector' AND l.party_id = c.id AND l.generator_id = ?
        GROUP BY c.id HAVING bal > 0''', [generatorId, generatorId, generatorId]);
    for (final c in custody) {
      final since = (c['last_h'] ?? c['first_p']) as String?;
      if (since == null) continue;
      final days = parseYmd(today).difference(parseYmd(since)).inDays;
      if (days >= lateDays) {
        await _add(generatorId, AlertKind.collectorLate, 'high', 'تأخر تسليم أموال الجابي',
            '${c['full_name']} لديه ${formatMoney(c['bal'] as int)} بعهدته منذ $days يوم.',
            'late:${c['id']}:$today');
      }
    }

    // Sync stalled: pending items older than 24h.
    final pending = await ctx.db.rawQuery(
        "SELECT MIN(created_at) m, COUNT(*) c FROM sync_queue WHERE status != 'done'");
    final oldest = pending.first['m'] as String?;
    final syncConfigured = (await ctx.db.query('settings', where: "key = 'sync.server_url'")).isNotEmpty;
    if (syncConfigured && oldest != null && ctx.now.difference(DateTime.parse(oldest)).inHours >= 24) {
      await _add(null, AlertKind.syncStalled, 'high', 'توقف المزامنة',
          '${pending.first['c']} عملية لم تُرفع إلى الخادم منذ أكثر من 24 ساعة.', 'sync:$today');
    }

    final unread = await ctx.db.rawQuery(
        'SELECT COUNT(*) c FROM notifications WHERE read = 0 AND (generator_id = ? OR generator_id IS NULL)', [generatorId]);
    return unread.first['c'] as int;
  }

  Future<List<Map<String, Object?>>> list(String? generatorId, {bool unreadOnly = false, int limit = 200}) {
    return ctx.db.query('notifications',
        where: '(generator_id = ? OR generator_id IS NULL) ${unreadOnly ? 'AND read = 0' : ''}',
        whereArgs: [generatorId],
        orderBy: 'created_at DESC',
        limit: limit);
  }

  Future<void> markRead(String id) => ctx.db.update('notifications', {'read': 1}, where: 'id = ?', whereArgs: [id]);

  Future<void> markAllRead(String? generatorId) => ctx.db.update('notifications', {'read': 1},
      where: 'generator_id = ? OR generator_id IS NULL', whereArgs: [generatorId]);
}
