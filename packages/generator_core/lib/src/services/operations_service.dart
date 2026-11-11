import '../security/permissions.dart';
import '../util/dates.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'finance_service.dart';

class FaultSeverity {
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static const critical = 'critical';
  static const labels = {low: 'منخفضة', medium: 'متوسطة', high: 'عالية', critical: 'حرجة'};
}

class MaintenanceKind {
  static const labels = {
    'periodic': 'صيانة دورية',
    'oil': 'تبديل الزيت',
    'oil_filter': 'فلتر زيت',
    'fuel_filter': 'فلتر وقود',
    'air_filter': 'فلتر هواء',
    'battery': 'البطاريات',
    'coolant': 'ماء التبريد',
    'belts': 'السيور',
    'other': 'أخرى',
  };
}

/// Generator run log, maintenance plans/records, and faults.
class OperationsService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final FinanceService finance;
  OperationsService(this.ctx, this.store, this.audit, this.finance);

  // ------------------------------------------------------------------ runs

  Future<Map<String, Object?>?> openRun(String generatorId) async {
    final r = await ctx.db.query('generator_runs',
        where: 'generator_id = ? AND stopped_at IS NULL', whereArgs: [generatorId], orderBy: 'started_at DESC', limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<String> startRun(String generatorId, {bool gridOutage = false, String? notes, DateTime? at}) async {
    ctx.require(Perm.operationsManage);
    ctx.requireGenerator(generatorId);
    if (await openRun(generatorId) != null) throw validation('المولدة قيد التشغيل حالياً. أطفئها أولاً.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'generator_runs', {
        'id': id, 'generator_id': generatorId, 'started_at': (at ?? ctx.now).toIso8601String(),
        'grid_outage': gridOutage ? 1 : 0, 'notes': notes,
      });
      await audit.log(t, 'runs.start', entity: 'generator_runs', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<void> stopRun(String generatorId, {String? reason, DateTime? at}) async {
    ctx.require(Perm.operationsManage);
    final run = await openRun(generatorId);
    if (run == null) throw validation('لا يوجد تشغيل مفتوح لهذه المولدة.');
    final stop = at ?? ctx.now;
    if (stop.isBefore(DateTime.parse(run['started_at'] as String))) {
      throw validation('وقت الإطفاء قبل وقت التشغيل.');
    }
    await ctx.db.transaction((t) async {
      await store.update(t, 'generator_runs', run['id'] as String,
          {'stopped_at': stop.toIso8601String(), 'stop_reason': reason});
      await audit.log(t, 'runs.stop', entity: 'generator_runs', entityId: run['id'] as String, generatorId: generatorId);
    });
  }

  /// Manually logged run (e.g. entered after the fact).
  Future<String> logRun(String generatorId, DateTime start, DateTime stop, {String? reason, bool gridOutage = false}) async {
    ctx.require(Perm.operationsManage);
    ctx.requireGenerator(generatorId);
    if (!stop.isAfter(start)) throw validation('وقت الإطفاء يجب أن يكون بعد وقت التشغيل.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'generator_runs', {
        'id': id, 'generator_id': generatorId, 'started_at': start.toIso8601String(),
        'stopped_at': stop.toIso8601String(), 'stop_reason': reason, 'grid_outage': gridOutage ? 1 : 0,
      });
      await audit.log(t, 'runs.log', entity: 'generator_runs', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<List<Map<String, Object?>>> runs(String generatorId, DateRange range) {
    ctx.requireGenerator(generatorId);
    return ctx.db.query('generator_runs',
        where: 'generator_id = ? AND started_at >= ? AND started_at <= ?',
        whereArgs: [generatorId, range.from, '${range.to}T23:59:59'],
        orderBy: 'started_at DESC');
  }

  /// Total running hours in the range (open run counted until now).
  Future<double> runHours(String generatorId, DateRange range) async {
    final rows = await runs(generatorId, range);
    var minutes = 0;
    for (final r in rows) {
      final s = DateTime.parse(r['started_at'] as String);
      final e = r['stopped_at'] == null ? ctx.now : DateTime.parse(r['stopped_at'] as String);
      minutes += e.difference(s).inMinutes;
    }
    return minutes / 60;
  }

  /// Lifetime engine hours from the run log.
  Future<double> totalHours(String generatorId) => runHours(generatorId, const DateRange('0000-01-01', '9999-12-31'));

  // ----------------------------------------------------------- maintenance

  Future<String> createPlan(String generatorId, String kind, {int? intervalDays, int? intervalHours, String? lastDoneDate}) async {
    ctx.require(Perm.maintenanceManage);
    ctx.requireGenerator(generatorId);
    if ((intervalDays ?? 0) <= 0 && (intervalHours ?? 0) <= 0) {
      throw validation('حدد فترة الصيانة بالأيام أو بساعات التشغيل.');
    }
    final hours = await totalHours(generatorId);
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'maintenance_plans', {
        'id': id, 'generator_id': generatorId, 'kind': kind, 'interval_days': intervalDays,
        'interval_hours': intervalHours, 'last_done_date': lastDoneDate ?? ctx.today,
        'last_done_hours_x100': (hours * 100).round(),
      });
      await audit.log(t, 'maintenance.plan', entity: 'maintenance_plans', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  /// Records a maintenance job; its cost is posted as a maintenance expense
  /// and matching plans are reset.
  Future<String> recordMaintenance({
    required String generatorId,
    required String kind,
    String? technician,
    String? parts,
    int partsCost = 0,
    int laborCost = 0,
    String? nextDueDate,
    String? notes,
    String? date,
    String payMethod = PayMethod.cash,
    String? supplierId,
  }) async {
    ctx.require(Perm.maintenanceManage);
    ctx.requireGenerator(generatorId);
    if (partsCost < 0 || laborCost < 0) throw validation('التكلفة لا تكون سالبة.');
    final d = date ?? ctx.today;
    String? expenseId;
    final total = partsCost + laborCost;
    if (total > 0) {
      expenseId = await finance.recordExpense(
        generatorId: generatorId,
        category: kind == 'oil' || kind.endsWith('filter') ? ExpenseCategory.oilFilters : ExpenseCategory.maintenance,
        amount: total,
        payMethod: payMethod,
        supplierId: supplierId,
        description: '${MaintenanceKind.labels[kind] ?? kind}${technician != null ? ' — $technician' : ''}',
        date: d,
        checkPermission: false, // covered by maintenance.manage
      );
    }
    final hours = await totalHours(generatorId);
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'maintenance_records', {
        'id': id, 'generator_id': generatorId, 'kind': kind, 'done_date': d, 'technician': technician,
        'parts': parts, 'parts_cost': partsCost, 'labor_cost': laborCost, 'next_due_date': nextDueDate,
        'notes': notes, 'expense_id': expenseId,
      });
      final plans = await t.query('maintenance_plans',
          where: 'generator_id = ? AND kind = ? AND active = 1', whereArgs: [generatorId, kind]);
      for (final p in plans) {
        await store.update(t, 'maintenance_plans', p['id'] as String,
            {'last_done_date': d, 'last_done_hours_x100': (hours * 100).round()});
      }
      await audit.log(t, 'maintenance.record', entity: 'maintenance_records', entityId: id, generatorId: generatorId,
          details: {'cost': total});
    });
    return id;
  }

  Future<List<Map<String, Object?>>> maintenanceRecords(String generatorId, {int limit = 100}) {
    ctx.requireGenerator(generatorId);
    return ctx.db.query('maintenance_records',
        where: 'generator_id = ?', whereArgs: [generatorId], orderBy: 'done_date DESC', limit: limit);
  }

  /// Upcoming/overdue maintenance from plans (by days and by engine hours) and
  /// explicit next-due dates on records.
  Future<List<Map<String, Object?>>> upcomingMaintenance(String generatorId, {int withinDays = 14}) async {
    ctx.requireGenerator(generatorId);
    final hours = await totalHours(generatorId);
    final out = <Map<String, Object?>>[];
    final plans = await ctx.db.query('maintenance_plans', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId]);
    for (final p in plans) {
      String? dueDate;
      double? hoursLeft;
      if ((p['interval_days'] as int? ?? 0) > 0 && p['last_done_date'] != null) {
        dueDate = ymd(parseYmd(p['last_done_date'] as String).add(Duration(days: p['interval_days'] as int)));
      }
      if ((p['interval_hours'] as int? ?? 0) > 0) {
        final last = (p['last_done_hours_x100'] as int? ?? 0) / 100;
        hoursLeft = last + (p['interval_hours'] as int) - hours;
      }
      final daysLeft = dueDate == null ? null : parseYmd(dueDate).difference(parseYmd(ctx.today)).inDays;
      final soon = (daysLeft != null && daysLeft <= withinDays) || (hoursLeft != null && hoursLeft <= 24);
      if (soon) {
        out.add({
          'plan_id': p['id'], 'kind': p['kind'], 'due_date': dueDate, 'days_left': daysLeft,
          'hours_left': hoursLeft, 'overdue': (daysLeft != null && daysLeft < 0) || (hoursLeft != null && hoursLeft < 0),
        });
      }
    }
    final all = await ctx.db.query('maintenance_records',
        where: 'generator_id = ?', whereArgs: [generatorId], orderBy: 'done_date DESC');
    final latestByKind = <String, Map<String, Object?>>{};
    for (final r in all) {
      latestByKind.putIfAbsent(r['kind'] as String, () => r);
    }
    final horizon = ymd(ctx.now.add(Duration(days: withinDays)));
    final recs = latestByKind.values
        .where((r) => r['next_due_date'] != null && (r['next_due_date'] as String).compareTo(horizon) <= 0);
    for (final r in recs) {
      if (out.any((o) => o['kind'] == r['kind'])) continue;
      final daysLeft = parseYmd(r['next_due_date'] as String).difference(parseYmd(ctx.today)).inDays;
      out.add({'kind': r['kind'], 'due_date': r['next_due_date'], 'days_left': daysLeft, 'overdue': daysLeft < 0});
    }
    return out;
  }

  Future<List<Map<String, Object?>>> plans(String generatorId) =>
      ctx.db.query('maintenance_plans', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId]);

  // ---------------------------------------------------------------- faults

  Future<String> reportFault({
    required String generatorId,
    required String title,
    String? description,
    String severity = FaultSeverity.medium,
    DateTime? occurredAt,
    String? technician,
    String? attachments,
  }) async {
    ctx.require(Perm.maintenanceManage);
    ctx.requireGenerator(generatorId);
    if (title.trim().length < 3) throw validation('عنوان العطل مطلوب.');
    if (!FaultSeverity.labels.containsKey(severity)) throw validation('مستوى خطورة غير صحيح.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'fault_records', {
        'id': id, 'generator_id': generatorId, 'title': title.trim(), 'description': description,
        'severity': severity, 'occurred_at': (occurredAt ?? ctx.now).toIso8601String(),
        'technician': technician, 'attachments': attachments, 'status': 'open',
      });
      await audit.log(t, 'faults.report', entity: 'fault_records', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<void> resolveFault(String faultId, {int repairCost = 0, String? parts, String? technician,
      String payMethod = PayMethod.cash, String? supplierId}) async {
    ctx.require(Perm.maintenanceManage);
    final f = await ctx.db.query('fault_records', where: 'id = ?', whereArgs: [faultId]);
    if (f.isEmpty) throw const DomainException('NOT_FOUND', 'العطل غير موجود.');
    if (f.first['status'] == 'fixed') throw validation('تم إصلاح هذا العطل مسبقاً.');
    final gen = f.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    String? expenseId;
    if (repairCost > 0) {
      expenseId = await finance.recordExpense(
          generatorId: gen,
          category: ExpenseCategory.maintenance,
          amount: repairCost,
          payMethod: payMethod,
          supplierId: supplierId,
          description: 'إصلاح عطل: ${f.first['title']}',
          checkPermission: false);
    }
    await ctx.db.transaction((t) async {
      await store.update(t, 'fault_records', faultId, {
        'status': 'fixed', 'fixed_at': ctx.nowIso, 'repair_cost': repairCost, 'parts': parts,
        'technician': technician ?? f.first['technician'], 'expense_id': expenseId,
      });
      await audit.log(t, 'faults.resolve', entity: 'fault_records', entityId: faultId, generatorId: gen,
          details: {'cost': repairCost});
    });
  }

  Future<List<Map<String, Object?>>> faults(String generatorId, {bool openOnly = false}) {
    ctx.requireGenerator(generatorId);
    return ctx.db.query('fault_records',
        where: 'generator_id = ? ${openOnly ? "AND status = 'open'" : ''}',
        whereArgs: [generatorId],
        orderBy: 'occurred_at DESC');
  }
}

/// Complaints / subscriber service desk.
class ComplaintService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  ComplaintService(this.ctx, this.store, this.audit);

  static const categories = {
    'outage': 'انقطاع التيار',
    'voltage': 'ضعف الفولتية',
    'billing': 'اعتراض على فاتورة',
    'collector': 'شكوى على الجابي',
    'maintenance': 'طلب صيانة',
    'amps_change': 'طلب تغيير الأمبير',
    'other': 'أخرى',
  };
  static const statuses = {'open': 'مفتوحة', 'in_progress': 'قيد المعالجة', 'resolved': 'محلولة'};
  static const priorities = {'low': 'منخفضة', 'normal': 'عادية', 'high': 'عالية', 'urgent': 'عاجلة'};

  Future<String> create({
    required String generatorId,
    required String category,
    required String title,
    String? body,
    String? subscriberId,
    String priority = 'normal',
    String? assignee,
    String? attachments,
  }) async {
    ctx.require(Perm.complaintsManage);
    ctx.requireGenerator(generatorId);
    if (!categories.containsKey(category)) throw validation('تصنيف غير معروف.');
    if (!priorities.containsKey(priority)) throw validation('أولوية غير معروفة.');
    if (title.trim().length < 3) throw validation('عنوان الشكوى مطلوب.');
    final id = newId();
    final ticket = 'C${ctx.now.year % 100}${ctx.now.month.toString().padLeft(2, '0')}-${randomToken(5)}';
    await ctx.db.transaction((t) async {
      await store.insert(t, 'complaints', {
        'id': id, 'generator_id': generatorId, 'ticket_no': ticket, 'subscriber_id': subscriberId,
        'category': category, 'priority': priority, 'title': title.trim(), 'body': body, 'assignee': assignee,
        'status': 'open', 'opened_at': ctx.nowIso, 'attachments': attachments,
      });
      await t.insert('notifications', {
        'id': newId(), 'generator_id': generatorId, 'kind': 'complaint', 'severity': priority == 'urgent' ? 'high' : 'normal',
        'title': 'شكوى جديدة $ticket', 'body': title.trim(), 'created_at': ctx.nowIso, 'dedupe_key': 'complaint:$id',
      });
      await audit.log(t, 'complaints.create', entity: 'complaints', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<void> reply(String complaintId, String body) async {
    ctx.require(Perm.complaintsManage);
    if (body.trim().isEmpty) throw validation('نص الرد فارغ.');
    await ctx.db.transaction((t) async {
      await store.insert(t, 'complaint_replies',
          {'id': newId(), 'complaint_id': complaintId, 'at': ctx.nowIso, 'user_id': ctx.userId, 'body': body.trim()});
      final c = await t.query('complaints', where: 'id = ?', whereArgs: [complaintId]);
      if (c.isNotEmpty && c.first['status'] == 'open') {
        await store.update(t, 'complaints', complaintId, {'status': 'in_progress'});
      }
    });
  }

  Future<void> setStatus(String complaintId, String status, {String? assignee}) async {
    ctx.require(Perm.complaintsManage);
    if (!statuses.containsKey(status)) throw validation('حالة غير معروفة.');
    await ctx.db.transaction((t) async {
      await store.update(t, 'complaints', complaintId, {
        'status': status,
        if (assignee != null) 'assignee': assignee,
        if (status == 'resolved') 'resolved_at': ctx.nowIso,
      });
      await audit.log(t, 'complaints.status', entity: 'complaints', entityId: complaintId, details: {'status': status});
    });
  }

  Future<void> archive(String complaintId) async {
    ctx.require(Perm.complaintsManage);
    await ctx.db.transaction((t) => store.update(t, 'complaints', complaintId, {'archived': 1}));
  }

  Future<List<Map<String, Object?>>> list(String generatorId, {bool archived = false, String? status}) {
    ctx.require(Perm.complaintsManage);
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT c.*, s.full_name AS subscriber_name, a.name AS area_name FROM complaints c
        LEFT JOIN subscribers s ON s.id = c.subscriber_id LEFT JOIN areas a ON a.id = s.area_id
        WHERE c.generator_id = ? AND c.archived = ? ${status != null ? 'AND c.status = ?' : ''}
        ORDER BY c.opened_at DESC''', [generatorId, archived ? 1 : 0, if (status != null) status]);
  }

  Future<List<Map<String, Object?>>> replies(String complaintId) => ctx.db.rawQuery('''SELECT r.*, u.full_name
      FROM complaint_replies r LEFT JOIN users u ON u.id = r.user_id WHERE r.complaint_id = ? ORDER BY r.at''',
      [complaintId]);

  Future<List<Map<String, Object?>>> byArea(String generatorId) => ctx.db.rawQuery('''
      SELECT COALESCE(a.name, 'غير محدد') AS area, COUNT(*) AS count,
        SUM(CASE WHEN c.status != 'resolved' THEN 1 ELSE 0 END) AS open
      FROM complaints c LEFT JOIN subscribers s ON s.id = c.subscriber_id LEFT JOIN areas a ON a.id = s.area_id
      WHERE c.generator_id = ? GROUP BY a.id ORDER BY count DESC''', [generatorId]);
}
