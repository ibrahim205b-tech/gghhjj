import 'package:sqflite_common/sqlite_api.dart';

import '../security/permissions.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'ledger_service.dart';

class SubscriberStatus {
  static const active = 'active';
  static const stopped = 'stopped';
  static const transferred = 'transferred';
  static const labels = {active: 'فعال', stopped: 'متوقف', transferred: 'منقول'};
}

class SubscriptionType {
  static const normal = 'normal';
  static const commercial = 'commercial';
  static const exempt = 'exempt';
  static const labels = {normal: 'منزلي', commercial: 'تجاري', exempt: 'معفى'};
}

class SubscriberFilter {
  final String? query;
  final String? areaId;
  final String? cabinetId;
  final String? lineId;
  final String? status;
  final bool onlyWithDebt;
  final String? collectorId;
  const SubscriberFilter({
    this.query,
    this.areaId,
    this.cabinetId,
    this.lineId,
    this.status,
    this.onlyWithDebt = false,
    this.collectorId,
  });
}

class SubscriberService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final LedgerService ledger;
  SubscriberService(this.ctx, this.store, this.audit, this.ledger);

  static const _editable = {
    'full_name', 'phone', 'phone2', 'meter_no', 'province', 'area_id', 'mahalla', 'alley', 'house',
    'landmark', 'lat', 'lng', 'cabinet_id', 'line_id', 'amps', 'amp_price', 'subscription_type',
    'notes', 'meter_photo', 'account_no',
  };

  Future<String> nextAccountNo(String generatorId, [DatabaseExecutor? ex]) async {
    final r = await (ex ?? ctx.db).rawQuery(
        "SELECT MAX(CAST(account_no AS INTEGER)) m FROM subscribers WHERE generator_id = ? AND account_no GLOB '[0-9]*'",
        [generatorId]);
    final m = (r.first['m'] as int?) ?? 0;
    return (m + 1).toString();
  }

  void _validate(Map<String, Object?> d) {
    final name = (d['full_name'] as String?)?.trim() ?? '';
    if (name.length < 3) throw validation('اسم المشترك مطلوب (3 أحرف على الأقل).');
    final amps = d['amps'];
    if (amps is! int || amps <= 0 || amps > 1000) throw validation('عدد الأمبيرات يجب أن يكون رقماً موجباً.');
    final price = d['amp_price'];
    if (price is! int || price < 0) throw validation('سعر الأمبير غير صحيح.');
    final phone = d['phone'] as String?;
    if (phone != null && phone.isNotEmpty && !RegExp(r'^[0-9+ ]{7,16}$').hasMatch(phone)) {
      throw validation('رقم الهاتف غير صحيح.');
    }
  }

  Future<String> create(String generatorId, Map<String, Object?> data, {int openingDebt = 0}) async {
    ctx.require(Perm.subscribersEdit);
    ctx.requireGenerator(generatorId);
    final d = Map<String, Object?>.from(data)..removeWhere((k, _) => !_editable.contains(k) && k != 'start_date');
    if (!ctx.can(Perm.subscribersEditPrice)) {
      final g = await ctx.db.query('generators', where: 'id = ?', whereArgs: [generatorId]);
      d['amp_price'] = g.first['default_amp_price'];
    }
    _validate(d);
    if (openingDebt < 0) throw validation('الدين الافتتاحي لا يكون سالباً.');
    final id = newId();
    await ctx.db.transaction((t) async {
      final accNo = (d['account_no'] as String?)?.trim().isNotEmpty == true
          ? (d['account_no'] as String).trim()
          : await nextAccountNo(generatorId, t);
      final dup = await t.query('subscribers',
          where: 'generator_id = ? AND account_no = ?', whereArgs: [generatorId, accNo]);
      if (dup.isNotEmpty) throw validation('رقم الاشتراك $accNo مستخدم مسبقاً.');
      await store.insert(t, 'subscribers', {
        ...d,
        'id': id,
        'generator_id': generatorId,
        'account_no': accNo,
        'start_date': d['start_date'] ?? ctx.today,
        'status': SubscriberStatus.active,
        'connected': 1,
        'qr_token': randomToken(12),
        'subscription_type': d['subscription_type'] ?? SubscriptionType.normal,
      });
      await _event(t, id, generatorId, 'created', null, '${d['amps']}A', null);
      if (openingDebt > 0) {
        await ledger.post(t,
            entryId: 'je:open:$id',
            generatorId: generatorId,
            date: ctx.today,
            description: 'رصيد افتتاحي (دين سابق) للمشترك ${d['full_name']}',
            sourceType: 'opening_balance',
            sourceId: id,
            lines: [
              JLine.dr(Acc.receivables, openingDebt, partyType: PartyType.subscriber, partyId: id),
              JLine.cr(Acc.openingBalances, openingDebt),
            ]);
      }
      await audit.log(t, 'subscribers.create', entity: 'subscribers', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<Map<String, Object?>> get(String id) async {
    ctx.require(Perm.subscribersView);
    final r = await ctx.db.rawQuery('''
      SELECT s.*, a.name AS area_name, c.code AS cabinet_code, l.code AS line_code, g.name AS generator_name
      FROM subscribers s LEFT JOIN areas a ON a.id = s.area_id
      LEFT JOIN cabinets c ON c.id = s.cabinet_id LEFT JOIN lines l ON l.id = s.line_id
      JOIN generators g ON g.id = s.generator_id WHERE s.id = ?''', [id]);
    if (r.isEmpty) throw const DomainException('NOT_FOUND', 'المشترك غير موجود.');
    ctx.requireGenerator(r.first['generator_id'] as String);
    return r.first;
  }

  Future<Map<String, Object?>?> findByQrToken(String token) async {
    final r = await ctx.db.query('subscribers', where: 'qr_token = ?', whereArgs: [token]);
    if (r.isEmpty) return null;
    return get(r.first['id'] as String);
  }

  Future<void> update(String id, Map<String, Object?> changes, {String? reason}) async {
    ctx.require(Perm.subscribersEdit);
    final cur = await get(id);
    final c = Map<String, Object?>.from(changes)..removeWhere((k, _) => !_editable.contains(k));
    final priceChange = c.containsKey('amp_price') && c['amp_price'] != cur['amp_price'];
    if (priceChange) ctx.require(Perm.subscribersEditPrice);
    if (c.containsKey('area_id') || c.containsKey('cabinet_id') || c.containsKey('line_id')) {
      final moved = ['area_id', 'cabinet_id', 'line_id'].any((k) => c.containsKey(k) && c[k] != cur[k]);
      if (moved) ctx.require(Perm.subscribersTransfer);
    }
    _validate({...cur, ...c});
    if (c.containsKey('account_no')) {
      final dup = await ctx.db.query('subscribers',
          where: 'generator_id = ? AND account_no = ? AND id != ?',
          whereArgs: [cur['generator_id'], c['account_no'], id]);
      if (dup.isNotEmpty) throw validation('رقم الاشتراك مستخدم مسبقاً.');
    }
    final gen = cur['generator_id'] as String;
    await ctx.db.transaction((t) async {
      await store.update(t, 'subscribers', id, c);
      for (final k in ['amps', 'amp_price', 'area_id', 'cabinet_id', 'line_id', 'subscription_type']) {
        if (c.containsKey(k) && c[k] != cur[k]) {
          await _event(t, id, gen, 'change:$k', cur[k]?.toString(), c[k]?.toString(), reason);
        }
      }
      await audit.log(t, 'subscribers.update', entity: 'subscribers', entityId: id, generatorId: gen,
          details: {'changes': c, if (reason != null) 'reason': reason});
    });
  }

  Future<void> setStatus(String id, String status, {required String reason}) async {
    ctx.require(Perm.subscribersStatus);
    if (!{SubscriberStatus.active, SubscriberStatus.stopped}.contains(status)) {
      throw validation('حالة غير صالحة.');
    }
    final cur = await get(id);
    if (cur['status'] == SubscriberStatus.transferred) throw validation('المشترك منقول لمولدة أخرى.');
    if (cur['status'] == status) return;
    await ctx.db.transaction((t) async {
      await store.update(t, 'subscribers', id, {'status': status, 'connected': status == SubscriberStatus.active ? 1 : 0});
      await _event(t, id, cur['generator_id'] as String, 'status', cur['status'] as String, status, reason);
      await audit.log(t, 'subscribers.status', entity: 'subscribers', entityId: id,
          generatorId: cur['generator_id'] as String, details: {'status': status, 'reason': reason});
    });
  }

  /// Physical disconnect / reconnect (e.g. for non-payment) without changing
  /// the subscription status.
  Future<void> setConnected(String id, bool connected, {required String reason}) async {
    ctx.require(Perm.subscribersStatus);
    final cur = await get(id);
    await ctx.db.transaction((t) async {
      await store.update(t, 'subscribers', id, {'connected': connected ? 1 : 0});
      await _event(t, id, cur['generator_id'] as String, connected ? 'reconnect' : 'disconnect', null, null, reason);
      await audit.log(t, connected ? 'subscribers.reconnect' : 'subscribers.disconnect',
          entity: 'subscribers', entityId: id, generatorId: cur['generator_id'] as String);
    });
  }

  /// Moves a subscriber to another generator. Accounts of generators are never
  /// mixed: the old record keeps its full financial history (and any debt
  /// remains owed to the old generator); a new record is opened in the target
  /// generator and both are linked through subscriber events.
  Future<String> transferToGenerator(String id, String targetGeneratorId,
      {required String reason, String? areaId, String? cabinetId, String? lineId, int? ampPrice}) async {
    ctx.require(Perm.subscribersTransfer);
    ctx.requireGenerator(targetGeneratorId);
    final cur = await get(id);
    if (cur['generator_id'] == targetGeneratorId) throw validation('المشترك موجود أصلاً في هذه المولدة.');
    if (cur['status'] == SubscriberStatus.transferred) throw validation('تم نقل المشترك مسبقاً.');
    final newIdValue = newId();
    await ctx.db.transaction((t) async {
      final accNo = await nextAccountNo(targetGeneratorId, t);
      final g = await t.query('generators', where: 'id = ?', whereArgs: [targetGeneratorId]);
      final copy = Map<String, Object?>.from(cur)
        ..removeWhere((k, _) => !_editable.contains(k))
        ..['area_id'] = areaId
        ..['cabinet_id'] = cabinetId
        ..['line_id'] = lineId
        ..['amp_price'] = ampPrice ?? g.first['default_amp_price']
        ..['account_no'] = accNo;
      await store.insert(t, 'subscribers', {
        ...copy,
        'id': newIdValue,
        'generator_id': targetGeneratorId,
        'start_date': ctx.today,
        'status': SubscriberStatus.active,
        'connected': 1,
        'qr_token': randomToken(12),
      });
      await store.update(t, 'subscribers', id, {'status': SubscriberStatus.transferred, 'connected': 0});
      await _event(t, id, cur['generator_id'] as String, 'transfer_out', cur['generator_id'] as String,
          '$targetGeneratorId|$newIdValue', reason);
      await _event(t, newIdValue, targetGeneratorId, 'transfer_in', '${cur['generator_id']}|$id',
          targetGeneratorId, reason);
      await audit.log(t, 'subscribers.transfer_generator', entity: 'subscribers', entityId: id,
          generatorId: cur['generator_id'] as String, details: {'to': targetGeneratorId, 'new_id': newIdValue});
    });
    return newIdValue;
  }

  Future<void> _event(DatabaseExecutor t, String subscriberId, String generatorId, String kind, String? from,
      String? to, String? reason) {
    return store.insert(t, 'subscriber_events', {
      'id': newId(),
      'subscriber_id': subscriberId,
      'generator_id': generatorId,
      'at': ctx.nowIso,
      'kind': kind,
      'from_value': from,
      'to_value': to,
      'reason': reason,
      'user_id': ctx.userId,
    });
  }

  Future<List<Map<String, Object?>>> history(String id) async {
    await get(id);
    return ctx.db.rawQuery('''SELECT e.*, u.full_name AS user_name FROM subscriber_events e
        LEFT JOIN users u ON u.id = e.user_id WHERE e.subscriber_id = ? ORDER BY e.at DESC''', [id]);
  }

  /// Subscribers visible to a collector: those in the areas/cabinets assigned
  /// to him. Returns null when the collector has no restrictions.
  Future<String?> _collectorScopeSql(String collectorId, List<Object?> args) async {
    final asg = await ctx.db.query('collector_assignments',
        where: 'collector_id = ? AND active = 1', whereArgs: [collectorId]);
    if (asg.isEmpty) return '0'; // no assignment -> no subscribers
    final parts = <String>[];
    for (final a in asg) {
      if (a['cabinet_id'] != null) {
        parts.add('s.cabinet_id = ?');
        args.add(a['cabinet_id']);
      } else if (a['area_id'] != null) {
        parts.add('s.area_id = ?');
        args.add(a['area_id']);
      } else {
        parts.add('s.generator_id = ?');
        args.add(a['generator_id']);
      }
    }
    return '(${parts.join(' OR ')})';
  }

  /// Search with balance (debt) computed from the ledger.
  Future<List<Map<String, Object?>>> search(String generatorId, SubscriberFilter f,
      {int limit = 100, int offset = 0}) async {
    ctx.require(Perm.subscribersView);
    ctx.requireGenerator(generatorId);
    final where = <String>['s.generator_id = ?'];
    final args = <Object?>[generatorId];
    final collectorId = ctx.session?.isCollector == true ? ctx.session?.collectorId ?? '-' : f.collectorId;
    if (collectorId != null) {
      final scopeArgs = <Object?>[];
      final scope = await _collectorScopeSql(collectorId, scopeArgs);
      where.add(scope!);
      args.addAll(scopeArgs);
    }
    final q = f.query?.trim();
    if (q != null && q.isNotEmpty) {
      where.add('(s.full_name LIKE ? OR s.phone LIKE ? OR s.phone2 LIKE ? OR s.meter_no LIKE ? OR s.account_no = ? '
          'OR a.name LIKE ? OR c.code = ?)');
      final like = '%$q%';
      args.addAll([like, like, like, like, q, like, q]);
    }
    if (f.areaId != null) {
      where.add('s.area_id = ?');
      args.add(f.areaId);
    }
    if (f.cabinetId != null) {
      where.add('s.cabinet_id = ?');
      args.add(f.cabinetId);
    }
    if (f.lineId != null) {
      where.add('s.line_id = ?');
      args.add(f.lineId);
    }
    if (f.status != null) {
      where.add('s.status = ?');
      args.add(f.status);
    } else {
      where.add("s.status != 'transferred'");
    }
    final arAccount = LedgerService.accountId(generatorId, Acc.receivables);
    final having = f.onlyWithDebt ? 'HAVING balance > 0' : '';
    return ctx.db.rawQuery('''
      SELECT s.id, s.account_no, s.full_name, s.phone, s.meter_no, s.amps, s.amp_price, s.status, s.connected,
        s.subscription_type, a.name AS area_name, c.code AS cabinet_code,
        COALESCE((SELECT SUM(debit - credit) FROM journal_lines jl WHERE jl.account_id = ?
          AND jl.party_type = 'subscriber' AND jl.party_id = s.id), 0) AS balance
      FROM subscribers s LEFT JOIN areas a ON a.id = s.area_id LEFT JOIN cabinets c ON c.id = s.cabinet_id
      WHERE ${where.join(' AND ')} $having
      ORDER BY CAST(s.account_no AS INTEGER), s.full_name LIMIT ? OFFSET ?''',
        [arAccount, ...args, limit, offset]);
  }

  /// Ensures a collector may act on this subscriber.
  Future<void> requireCollectorScope(String subscriberId) async {
    final s = ctx.session;
    if (s == null || !s.isCollector) return;
    if (s.collectorId == null) throw const PermissionDenied('collector.unlinked');
    final args = <Object?>[];
    final scope = await _collectorScopeSql(s.collectorId!, args);
    final r = await ctx.db.rawQuery('SELECT s.id FROM subscribers s WHERE s.id = ? AND $scope', [subscriberId, ...args]);
    if (r.isEmpty) {
      throw const DomainException('NOT_ASSIGNED', 'هذا المشترك غير مخصص لك.');
    }
  }

  Future<int> balance(String subscriberId) async {
    final s = await get(subscriberId);
    return ledger.balance(s['generator_id'] as String, Acc.receivables,
        partyType: PartyType.subscriber, partyId: subscriberId);
  }

  Future<Map<String, int>> counts(String generatorId) async {
    final r = await ctx.db.rawQuery('''SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active,
        SUM(CASE WHEN status = 'stopped' THEN 1 ELSE 0 END) AS stopped,
        COALESCE(SUM(CASE WHEN status = 'active' THEN amps ELSE 0 END), 0) AS amps
      FROM subscribers WHERE generator_id = ? AND status != 'transferred' ''', [generatorId]);
    final row = r.first;
    final debtors = await ctx.db.rawQuery('''SELECT COUNT(*) c FROM (
        SELECT party_id, SUM(debit - credit) b FROM journal_lines WHERE account_id = ? AND party_type = 'subscriber'
        GROUP BY party_id HAVING b > 0)''', [LedgerService.accountId(generatorId, Acc.receivables)]);
    return {
      'total': (row['total'] as int?) ?? 0,
      'active': (row['active'] as int?) ?? 0,
      'stopped': (row['stopped'] as int?) ?? 0,
      'amps': (row['amps'] as int?) ?? 0,
      'debtors': (debtors.first['c'] as int?) ?? 0,
    };
  }
}
