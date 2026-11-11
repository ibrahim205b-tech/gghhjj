import 'package:sqflite_common/sqlite_api.dart';

import '../security/permissions.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'ledger_service.dart';

/// Generators, branches, areas, cabinets, lines and cash boxes.
class NetworkService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final LedgerService ledger;

  /// Returns the number of generators the active licence allows.
  Future<int> Function() maxGenerators;

  NetworkService(this.ctx, this.store, this.audit, this.ledger, {Future<int> Function()? maxGenerators})
      : maxGenerators = maxGenerators ?? (() async => 1 << 30);

  // ------------------------------------------------------------- generators

  Future<List<Map<String, Object?>>> listGenerators({bool includeInactive = false}) async {
    final rows = await ctx.db.query('generators',
        where: includeInactive ? null : 'active = 1', orderBy: 'created_at');
    return rows.where((g) => ctx.canAccessGenerator(g['id'] as String)).toList();
  }

  Future<Map<String, Object?>> getGenerator(String id) async {
    ctx.requireGenerator(id);
    final r = await ctx.db.query('generators', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw const DomainException('NOT_FOUND', 'المولدة غير موجودة.');
    return r.first;
  }

  Future<String> createGenerator({
    required String name,
    String? code,
    int? capacityKva,
    String? province,
    String? address,
    int defaultAmpPrice = 0,
    int fuelLowThresholdLiters = 200,
  }) async {
    ctx.require(Perm.generatorsManage);
    if (name.trim().isEmpty) throw validation('اسم المولدة مطلوب.');
    final count = (await ctx.db.rawQuery('SELECT COUNT(*) c FROM generators WHERE active = 1')).first['c'] as int;
    final max = await maxGenerators();
    if (count >= max) {
      throw DomainException('LICENSE_LIMIT',
          'الترخيص الحالي يسمح بـ $max مولدة. لإضافة مولدات أخرى فعّل ترخيصاً متعدد المولدات. بياناتك الحالية تبقى متاحة بالكامل.');
    }
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'generators', {
        'id': id,
        'name': name.trim(),
        'code': code,
        'capacity_kva': capacityKva,
        'province': province,
        'address': address,
        'default_amp_price': defaultAmpPrice,
        'fuel_low_threshold_ml': fuelLowThresholdLiters * 1000,
      });
      await ledger.createChart(t, id);
      await store.insert(t, 'cashboxes', {
        'id': 'cb:$id:main',
        'generator_id': id,
        'name': 'الصندوق الرئيسي',
        'account_id': LedgerService.accountId(id, Acc.mainCash),
      });
      final s = ctx.session;
      if (s != null && !s.allGenerators) {
        await store.insert(t, 'user_generators', {'id': '${s.userId}:$id', 'user_id': s.userId, 'generator_id': id});
      }
      await audit.log(t, 'generators.create', entity: 'generators', entityId: id, generatorId: id);
    });
    final s = ctx.session;
    if (s != null && !s.allGenerators) s.generatorIds.add(id);
    return id;
  }

  Future<void> updateGenerator(String id, Map<String, Object?> changes) async {
    ctx.require(Perm.generatorsManage);
    ctx.requireGenerator(id);
    const allowed = {'name', 'code', 'capacity_kva', 'province', 'address', 'default_amp_price',
      'fuel_low_threshold_ml', 'notes', 'active'};
    final c = Map.of(changes)..removeWhere((k, _) => !allowed.contains(k));
    await ctx.db.transaction((t) async {
      await store.update(t, 'generators', id, c);
      await audit.log(t, 'generators.update', entity: 'generators', entityId: id, generatorId: id, details: c);
    });
  }

  // ---------------------------------------------------------------- generic

  Future<String> _create(String table, String generatorId, Map<String, Object?> row, String perm) async {
    ctx.require(perm);
    ctx.requireGenerator(generatorId);
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, table, {'id': id, 'generator_id': generatorId, ...row});
      await audit.log(t, '$table.create', entity: table, entityId: id, generatorId: generatorId, details: row);
    });
    return id;
  }

  Future<void> _update(String table, String id, Map<String, Object?> changes, String perm) async {
    ctx.require(perm);
    final r = await ctx.db.query(table, where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw const DomainException('NOT_FOUND', 'السجل غير موجود.');
    ctx.requireGenerator(r.first['generator_id'] as String);
    await ctx.db.transaction((t) async {
      await store.update(t, table, id, changes);
      await audit.log(t, '$table.update', entity: table, entityId: id,
          generatorId: r.first['generator_id'] as String, details: changes);
    });
  }

  Future<String> createBranch(String generatorId, String name) =>
      _create('branches', generatorId, {'name': name.trim()}, Perm.generatorsManage);

  Future<List<Map<String, Object?>>> listBranches(String generatorId) =>
      ctx.db.query('branches', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId], orderBy: 'name');

  Future<String> createArea(String generatorId, String name, {String? province, String? district}) {
    if (name.trim().isEmpty) throw validation('اسم المنطقة مطلوب.');
    return _create('areas', generatorId, {'name': name.trim(), 'province': province, 'district': district},
        Perm.networkManage);
  }

  Future<void> updateArea(String id, Map<String, Object?> changes) =>
      _update('areas', id, changes, Perm.networkManage);

  Future<List<Map<String, Object?>>> listAreas(String generatorId) =>
      ctx.db.query('areas', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId], orderBy: 'name');

  Future<String> createCabinet(String generatorId, String code, {String? areaId, String? location, int maxAmps = 0}) {
    if (code.trim().isEmpty) throw validation('رقم الكابينة مطلوب.');
    if (maxAmps < 0) throw validation('سعة الكابينة غير صحيحة.');
    return _create('cabinets', generatorId,
        {'code': code.trim(), 'area_id': areaId, 'location': location, 'max_amps': maxAmps}, Perm.networkManage);
  }

  Future<void> updateCabinet(String id, Map<String, Object?> changes) =>
      _update('cabinets', id, changes, Perm.networkManage);

  Future<List<Map<String, Object?>>> listCabinets(String generatorId, {String? areaId}) => ctx.db.query('cabinets',
      where: 'generator_id = ? AND active = 1 ${areaId != null ? 'AND area_id = ?' : ''}',
      whereArgs: [generatorId, if (areaId != null) areaId],
      orderBy: 'code');

  Future<String> createLine(String generatorId, String code, {String? cabinetId, int maxAmps = 0}) {
    if (code.trim().isEmpty) throw validation('رقم الخط مطلوب.');
    return _create('lines', generatorId, {'code': code.trim(), 'cabinet_id': cabinetId, 'max_amps': maxAmps},
        Perm.networkManage);
  }

  Future<void> updateLine(String id, Map<String, Object?> changes) => _update('lines', id, changes, Perm.networkManage);

  Future<List<Map<String, Object?>>> listLines(String generatorId, {String? cabinetId}) => ctx.db.query('lines',
      where: 'generator_id = ? AND active = 1 ${cabinetId != null ? 'AND cabinet_id = ?' : ''}',
      whereArgs: [generatorId, if (cabinetId != null) cabinetId],
      orderBy: 'code');

  /// Contracted (theoretical) load per cabinet = sum of subscribed amps of
  /// connected active subscribers. This is NOT a measured electrical load.
  Future<List<Map<String, Object?>>> cabinetLoads(String generatorId) {
    return ctx.db.rawQuery('''
      SELECT c.id, c.code, c.max_amps, a.name AS area_name,
        COALESCE(SUM(CASE WHEN s.status = 'active' AND s.connected = 1 THEN s.amps END), 0) AS contracted_amps,
        COUNT(s.id) AS subscribers
      FROM cabinets c LEFT JOIN areas a ON a.id = c.area_id
      LEFT JOIN subscribers s ON s.cabinet_id = c.id
      WHERE c.generator_id = ? AND c.active = 1 GROUP BY c.id ORDER BY c.code''', [generatorId]);
  }

  Future<List<Map<String, Object?>>> lineLoads(String generatorId) {
    return ctx.db.rawQuery('''
      SELECT l.id, l.code, l.max_amps, c.code AS cabinet_code,
        COALESCE(SUM(CASE WHEN s.status = 'active' AND s.connected = 1 THEN s.amps END), 0) AS contracted_amps,
        COUNT(s.id) AS subscribers
      FROM lines l LEFT JOIN cabinets c ON c.id = l.cabinet_id
      LEFT JOIN subscribers s ON s.line_id = l.id
      WHERE l.generator_id = ? AND l.active = 1 GROUP BY l.id ORDER BY l.code''', [generatorId]);
  }

  // -------------------------------------------------------------- cashboxes

  Future<List<Map<String, Object?>>> listCashboxes(String generatorId) =>
      ctx.db.query('cashboxes', where: 'generator_id = ? AND active = 1', whereArgs: [generatorId], orderBy: 'created_at');

  Future<String> createCashbox(String generatorId, String name) async {
    ctx.require(Perm.cashboxManage);
    ctx.requireGenerator(generatorId);
    final existing = await ctx.db.query('cashboxes', where: 'generator_id = ?', whereArgs: [generatorId]);
    final n = existing.length + 1;
    if (n > 48) throw validation('تم الوصول للحد الأقصى من الصناديق.');
    final code = (1100 + n).toString();
    final id = newId();
    await ctx.db.transaction((DatabaseExecutor t) async {
      await ledger.ensureAccount(t, generatorId, code, 'صندوق: ${name.trim()}', AccountType.asset);
      await store.insert(t, 'cashboxes', {
        'id': id, 'generator_id': generatorId, 'name': name.trim(),
        'account_id': LedgerService.accountId(generatorId, code),
      });
      await audit.log(t, 'cashboxes.create', entity: 'cashboxes', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  /// Account code of a cash box (e.g. '1101').
  Future<String> cashboxCode(String cashboxId, [DatabaseExecutor? ex]) async {
    final r = await (ex ?? ctx.db).query('cashboxes', where: 'id = ?', whereArgs: [cashboxId]);
    if (r.isEmpty) throw const DomainException('NOT_FOUND', 'الصندوق غير موجود.');
    return (r.first['account_id'] as String).split(':').last;
  }

  static String mainCashbox(String generatorId) => 'cb:$generatorId:main';
}
