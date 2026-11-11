import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../db/schema.dart';
import '../security/permissions.dart';
import '../util/clock.dart';
import '../util/dates.dart';
import '../util/errors.dart';
import '../util/ids.dart';

/// The authenticated user of this device session.
class Session {
  final String sessionId;
  final String userId;
  final String username;
  final String fullName;
  final String roleId;
  final Set<String> permissions;
  final bool allGenerators;
  final Set<String> generatorIds;
  final String? collectorId;

  const Session({
    required this.sessionId,
    required this.userId,
    required this.username,
    required this.fullName,
    required this.roleId,
    required this.permissions,
    required this.allGenerators,
    required this.generatorIds,
    this.collectorId,
  });

  bool get isCollector => roleId == roleCollector;
}

/// Shared runtime for all services: database, clock, device and session.
class CoreContext {
  final Database db;
  final Clock clock;
  final String deviceId;
  Session? session;

  CoreContext({required this.db, required this.deviceId, this.clock = const SystemClock()});

  DateTime get now => clock.now();
  String get nowIso => isoTs(now);
  String get today => ymd(now);
  String? get userId => session?.userId;

  bool can(String permission) => session?.permissions.contains(permission) ?? false;

  void require(String permission) {
    if (session == null) {
      throw const DomainException('NOT_AUTHENTICATED', 'يجب تسجيل الدخول أولاً.');
    }
    if (!can(permission)) throw PermissionDenied(permission);
  }

  bool canAccessGenerator(String generatorId) {
    final s = session;
    if (s == null) return false;
    return s.allGenerators || s.generatorIds.contains(generatorId);
  }

  void requireGenerator(String generatorId) {
    if (!canAccessGenerator(generatorId)) {
      throw const DomainException('GENERATOR_FORBIDDEN', 'لا تملك صلاحية الوصول إلى هذه المولدة.');
    }
  }
}

/// Central write path. Every insert/update of a synchronised table also
/// appends an entry to the sync outbox in the same transaction, so a crash can
/// never leave a change that is not queued for upload (or vice-versa).
class Store {
  final CoreContext ctx;
  Store(this.ctx);

  static final _synced = {...mutableTables, ...immutableTables};

  Future<void> insert(DatabaseExecutor ex, String table, Map<String, Object?> row) async {
    final r = Map<String, Object?>.from(row);
    if (mutableTables.contains(table)) {
      r['created_at'] ??= ctx.nowIso;
      r['updated_at'] ??= ctx.nowIso;
      r['version'] ??= 1;
    }
    await ex.insert(table, r, conflictAlgorithm: ConflictAlgorithm.abort);
    await _enqueue(ex, table, r['id'] as String, r);
  }

  /// Updates a mutable row, bumping its version, and queues the full row.
  Future<Map<String, Object?>> update(
      DatabaseExecutor ex, String table, String id, Map<String, Object?> changes) async {
    if (!mutableTables.contains(table)) {
      throw DomainException('IMMUTABLE', 'لا يمكن تعديل سجلات $table بعد حفظها.');
    }
    final current = await ex.query(table, where: 'id = ?', whereArgs: [id]);
    if (current.isEmpty) throw const DomainException('NOT_FOUND', 'السجل غير موجود.');
    final row = Map<String, Object?>.from(current.first)..addAll(changes);
    row['updated_at'] = ctx.nowIso;
    row['version'] = ((current.first['version'] as int?) ?? 1) + 1;
    final upd = Map<String, Object?>.from(changes)
      ..['updated_at'] = row['updated_at']
      ..['version'] = row['version'];
    await ex.update(table, upd, where: 'id = ?', whereArgs: [id]);
    await _enqueue(ex, table, id, row);
    return row;
  }

  Future<void> _enqueue(DatabaseExecutor ex, String table, String id, Map<String, Object?> row) async {
    if (!_synced.contains(table)) return;
    final version = row['version'];
    final key = version == null ? '$table:$id' : '$table:$id:v$version:${newId().substring(0, 8)}';
    await ex.insert(
      'sync_queue',
      {
        'idempotency_key': key,
        'table_name': table,
        'row_id': id,
        'payload': jsonEncode(row),
        'created_at': ctx.nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}

/// Append-only audit trail. Rows cannot be deleted or updated (DB triggers).
class AuditService {
  final CoreContext ctx;
  final Store store;
  AuditService(this.ctx, this.store);

  Future<void> log(DatabaseExecutor ex, String action,
      {String? entity, String? entityId, String? generatorId, Map<String, Object?>? details}) {
    return store.insert(ex, 'audit_logs', {
      'id': newId(),
      'at': ctx.nowIso,
      'user_id': ctx.userId,
      'device_id': ctx.deviceId,
      'generator_id': generatorId,
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details': details == null ? null : jsonEncode(details),
    });
  }

  Future<List<Map<String, Object?>>> list({String? generatorId, int limit = 200, int offset = 0}) {
    ctx.require(Perm.auditView);
    return ctx.db.rawQuery(
      '''SELECT a.*, u.full_name AS user_name FROM audit_logs a
         LEFT JOIN users u ON u.id = a.user_id
         ${generatorId == null ? '' : 'WHERE a.generator_id = ? OR a.generator_id IS NULL'}
         ORDER BY a.at DESC LIMIT ? OFFSET ?''',
      [if (generatorId != null) generatorId, limit, offset],
    );
  }
}
