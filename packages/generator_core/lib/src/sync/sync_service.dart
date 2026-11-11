import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite_common/sqlite_api.dart';

import '../db/schema.dart';
import '../util/errors.dart';
import '../services/context.dart';

class SyncResult {
  final int pushed;
  final int pulled;
  final int conflicts;
  final String? error;
  const SyncResult({this.pushed = 0, this.pulled = 0, this.conflicts = 0, this.error});
  bool get ok => error == null;
}

class SyncConfig {
  final String serverUrl;
  final String deviceToken;
  const SyncConfig(this.serverUrl, this.deviceToken);
}

/// Offline-first synchronisation with the Generator OS server.
///
/// * Every local write is in `sync_queue` (outbox) with a unique
///   idempotency key; the server stores keys and ignores replays, so retries
///   never duplicate a payment.
/// * Append-only financial tables merge as a set union. A record with the
///   same id but different content is rejected by the server and logged as a
///   conflict; it never overwrites a valid record from another device.
/// * Mutable master data uses last-writer-wins by **server arrival order**
///   (a server sequence number), never by the phone's clock.
class SyncService {
  final CoreContext ctx;
  final http.Client client;
  bool _running = false;

  SyncService(this.ctx, {http.Client? client}) : client = client ?? http.Client();

  static const batchSize = 200;

  Future<SyncConfig?> config() async {
    final rows = await ctx.db.query('settings', where: "key IN ('sync.server_url','sync.device_token')");
    final m = {for (final r in rows) r['key']: r['value'] as String?};
    final url = m['sync.server_url'], token = m['sync.device_token'];
    if (url == null || url.isEmpty || token == null || token.isEmpty) return null;
    return SyncConfig(url, token);
  }

  Future<void> _setSetting(String key, String? value) => ctx.db.insert(
      'settings', {'key': key, 'value': value, 'updated_at': ctx.nowIso},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Uri _u(String base, String path) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');

  /// Pairs this device with a tenant on the server and stores the token.
  Future<void> pair({required String serverUrl, required String tenantCode, required String pairingSecret,
      String deviceName = 'Android'}) async {
    final res = await client.post(_u(serverUrl, '/api/v1/pair'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'tenant_code': tenantCode, 'pairing_secret': pairingSecret,
          'device_id': ctx.deviceId, 'device_name': deviceName,
        }));
    if (res.statusCode != 200) {
      throw DomainException('PAIR_FAILED', 'فشل ربط الجهاز بالخادم (${res.statusCode}): ${_err(res.body)}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await _setSetting('sync.server_url', serverUrl);
    await _setSetting('sync.device_token', body['device_token'] as String);
    await _setSetting('sync.cursor', '0');
  }

  Future<void> unpair() async {
    await ctx.db.delete('settings', where: "key IN ('sync.server_url','sync.device_token','sync.cursor')");
  }

  String _err(String body) {
    try {
      return (jsonDecode(body) as Map)['error']?.toString() ?? body;
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  Future<int> pendingCount() async =>
      (await ctx.db.rawQuery("SELECT COUNT(*) c FROM sync_queue WHERE status = 'pending'")).first['c'] as int;

  Future<String?> lastSuccess() async {
    final r = await ctx.db.rawQuery('SELECT MAX(at) m FROM sync_log WHERE ok = 1');
    return r.first['m'] as String?;
  }

  Future<List<Map<String, Object?>>> log({int limit = 50}) =>
      ctx.db.query('sync_log', orderBy: 'id DESC', limit: limit);

  Future<List<Map<String, Object?>>> conflicts({int limit = 100}) =>
      ctx.db.query('sync_conflicts', orderBy: 'id DESC', limit: limit);

  Future<void> _log(String dir, bool ok, int count, String? msg) => ctx.db.insert('sync_log',
      {'at': ctx.nowIso, 'direction': dir, 'ok': ok ? 1 : 0, 'count': count, 'message': msg});

  /// Push then pull. Safe to call repeatedly (manual button or timer).
  Future<SyncResult> syncNow() async {
    if (_running) return const SyncResult(error: 'المزامنة قيد التنفيذ حالياً.');
    final cfg = await config();
    if (cfg == null) return const SyncResult(error: 'لم يتم ربط الجهاز بخادم مزامنة.');
    _running = true;
    var pushed = 0, pulled = 0, conflicts = 0;
    try {
      // ------------------------------------------------------------ push
      while (true) {
        final batch = await ctx.db.query('sync_queue',
            where: "status = 'pending'", orderBy: 'seq', limit: batchSize);
        if (batch.isEmpty) break;
        final http.Response res;
        try {
          res = await client
              .post(_u(cfg.serverUrl, '/api/v1/sync/push'),
                  headers: {'content-type': 'application/json', 'authorization': 'Bearer ${cfg.deviceToken}'},
                  body: jsonEncode({
                    'device_id': ctx.deviceId,
                    'changes': [
                      for (final b in batch)
                        {
                          'key': b['idempotency_key'],
                          'table': b['table_name'],
                          'id': b['row_id'],
                          'payload': jsonDecode(b['payload'] as String),
                        }
                    ],
                  }))
              .timeout(const Duration(seconds: 60));
        } catch (e) {
          await _markAttempt(batch, 'تعذر الاتصال بالخادم: $e');
          rethrow;
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          await _markAttempt(batch, 'رفض الخادم الجهاز (${res.statusCode})');
          throw DomainException('SYNC_UNAUTHORIZED', 'تم رفض الجهاز من الخادم: ${_err(res.body)}');
        }
        if (res.statusCode != 200) {
          await _markAttempt(batch, 'HTTP ${res.statusCode}: ${_err(res.body)}');
          throw DomainException('SYNC_FAILED', 'فشل رفع البيانات (${res.statusCode}).');
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final accepted = (body['accepted'] as List).cast<String>().toSet();
        final serverConflicts = (body['conflicts'] as List? ?? []).cast<Map<String, dynamic>>();
        await ctx.db.transaction((t) async {
          for (final c in serverConflicts) {
            conflicts++;
            final local = batch.firstWhere((b) => b['idempotency_key'] == c['key'], orElse: () => const {});
            await t.insert('sync_conflicts', {
              'at': ctx.nowIso, 'table_name': c['table'], 'row_id': c['id'],
              'local_payload': local['payload'], 'remote_payload': jsonEncode(c['server_payload']),
              'resolution': c['resolution'] ?? 'server_kept_existing',
            });
            if (c['server_payload'] is Map && immutableTables.contains(c['table'])) {
              await _adoptCanonical(t, c['table'] as String, Map<String, Object?>.from(c['server_payload'] as Map));
            }
            accepted.add(c['key'] as String);
          }
          for (final k in accepted) {
            await t.update('sync_queue', {'status': 'done', 'last_error': null},
                where: 'idempotency_key = ?', whereArgs: [k]);
          }
        });
        pushed += accepted.length;
        if (accepted.isEmpty) break; // avoid infinite loop on unexpected server reply
      }
      await _log('push', true, pushed, null);

      // ------------------------------------------------------------ pull
      while (true) {
        final cursorRow = await ctx.db.query('settings', where: "key = 'sync.cursor'");
        final cursor = cursorRow.isEmpty ? 0 : int.tryParse(cursorRow.first['value'] as String? ?? '0') ?? 0;
        final res = await client
            .post(_u(cfg.serverUrl, '/api/v1/sync/pull'),
                headers: {'content-type': 'application/json', 'authorization': 'Bearer ${cfg.deviceToken}'},
                body: jsonEncode({'device_id': ctx.deviceId, 'cursor': cursor, 'limit': 500}))
            .timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) {
          throw DomainException('SYNC_FAILED', 'فشل تنزيل البيانات (${res.statusCode}): ${_err(res.body)}');
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final changes = (body['changes'] as List).cast<Map<String, dynamic>>();
        final next = body['cursor'] as int;
        final applied = await applyRemote(changes);
        pulled += applied.$1;
        conflicts += applied.$2;
        await _setSetting('sync.cursor', '$next');
        if (body['has_more'] != true || changes.isEmpty) break;
      }
      await _log('pull', true, pulled, null);
      return SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts);
    } catch (e) {
      final msg = e is DomainException ? e.message : e.toString();
      await _log('sync', false, pushed + pulled, msg);
      return SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts, error: msg);
    } finally {
      _running = false;
    }
  }

  Future<void> _markAttempt(List<Map<String, Object?>> batch, String error) async {
    await ctx.db.transaction((t) async {
      for (final b in batch) {
        await t.rawUpdate('UPDATE sync_queue SET attempts = attempts + 1, last_error = ? WHERE seq = ?',
            [error, b['seq']]);
      }
    });
  }

  /// Replaces the local copy of an append-only row with the server's
  /// canonical copy of the same document (same deterministic id). Used only
  /// when two devices produced the same document offline.
  Future<void> _adoptCanonical(DatabaseExecutor t, String table, Map<String, Object?> serverRow) async {
    final cols = await _cols(t, table);
    final row = Map<String, Object?>.from(serverRow)..removeWhere((k, _) => !cols.contains(k));
    final id = row.remove('id');
    if (id == null || row.isEmpty) return;
    await t.insert('local_meta', {'key': 'sync_override', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await t.update(table, row, where: 'id = ?', whereArgs: [id]);
    } finally {
      await t.delete('local_meta', where: "key = 'sync_override'");
    }
  }

  final _columns = <String, Set<String>>{};
  Future<Set<String>> _cols(DatabaseExecutor ex, String table) async {
    return _columns[table] ??=
        (await ex.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).toSet();
  }

  /// Applies rows received from the server without re-queuing them.
  /// Returns (applied, conflicts).
  Future<(int, int)> applyRemote(List<Map<String, dynamic>> changes) async {
    var applied = 0, conflicts = 0;
    await ctx.db.transaction((t) async {
      for (final c in changes) {
        final table = c['table'] as String;
        if (!mutableTables.contains(table) && !immutableTables.contains(table)) continue;
        final cols = await _cols(t, table);
        final payload = Map<String, Object?>.from(c['payload'] as Map)..removeWhere((k, _) => !cols.contains(k));
        final id = payload['id'] as String?;
        if (id == null) continue;
        try {
          if (immutableTables.contains(table)) {
            final n = await t.insert(table, payload, conflictAlgorithm: ConflictAlgorithm.ignore);
            if (n > 0) applied++;
          } else {
            final existing = await t.query(table, columns: ['id'], where: 'id = ?', whereArgs: [id]);
            if (existing.isEmpty) {
              await t.insert(table, payload);
            } else {
              await t.update(table, payload..remove('id'), where: 'id = ?', whereArgs: [id]);
            }
            applied++;
          }
        } on DatabaseException catch (e) {
          // Two devices created the same subscriber number offline: keep both
          // subscribers and make the number unique; record for review.
          if (table == 'subscribers' && e.isUniqueConstraintError()) {
            final fixed = Map<String, Object?>.from(payload)
              ..['account_no'] = '${payload['account_no']}-${id.substring(0, 4)}';
            try {
              await t.insert(table, fixed);
              applied++;
            } on DatabaseException catch (_) {}
          }
          conflicts++;
          await t.insert('sync_conflicts', {
            'at': ctx.nowIso, 'table_name': table, 'row_id': id, 'local_payload': null,
            'remote_payload': jsonEncode(c['payload']), 'resolution': 'apply_failed: ${e.toString().split('\n').first}',
          });
        }
      }
    });
    return (applied, conflicts);
  }
}
