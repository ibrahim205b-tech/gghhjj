import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../db/schema.dart';
import '../security/permissions.dart';
import '../util/errors.dart';
import 'context.dart';

/// Encrypted full backup (AES-256-GCM; key = PBKDF2-HMAC-SHA256(password)).
///
/// Restore never modifies the live database in place: it fills a *fresh*
/// database file which the app then swaps in. This keeps the append-only
/// guarantees intact and makes a failed restore harmless.
class BackupService {
  final CoreContext ctx;
  final AuditService audit;
  final int kdfIterations;
  BackupService(this.ctx, this.audit, {this.kdfIterations = 100000});

  static const format = 'generator-os-backup';
  static const _excluded = {'sessions', 'sync_queue', 'sync_log', 'android_metadata', 'sqlite_sequence'};

  static Future<List<String>> _tables(DatabaseExecutor db) async {
    final r = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY rowid");
    return r.map((e) => e['name'] as String).where((t) => !_excluded.contains(t)).toList();
  }

  Future<Map<String, Object?>> _snapshot() async {
    final tables = <String, Object?>{};
    for (final t in await _tables(ctx.db)) {
      var rows = await ctx.db.query(t);
      if (t == 'settings') {
        rows = rows.where((r) => r['key'] != 'sync.device_token').toList();
      }
      tables[t] = rows;
    }
    return {
      'format': format,
      'schema': latestSchemaVersion,
      'created_at': ctx.nowIso,
      'device_id': ctx.deviceId,
      'tables': tables,
    };
  }

  Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  /// Produces the encrypted backup bytes.
  Future<List<int>> createBackup(String password) async {
    ctx.require(Perm.backupManage);
    if (password.length < 8) throw validation('كلمة مرور النسخة الاحتياطية 8 أحرف على الأقل.');
    final plain = utf8.encode(jsonEncode(await _snapshot()));
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final algo = AesGcm.with256bits();
    final box = await algo.encrypt(plain, secretKey: await _key(password, salt, kdfIterations));
    await ctx.db.transaction((t) => audit.log(t, 'backup.create'));
    await ctx.db.insert('settings', {'key': 'backup.last_at', 'value': ctx.nowIso, 'updated_at': ctx.nowIso},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return utf8.encode(jsonEncode({
      'format': format,
      'v': 1,
      'kdf': {'alg': 'pbkdf2-sha256', 'iterations': kdfIterations, 'salt': base64Encode(salt)},
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    }));
  }

  /// Decrypts and validates a backup file; throws a clear error on a wrong
  /// password or a tampered file.
  static Future<Map<String, dynamic>> decrypt(List<int> bytes, String password) async {
    final Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const DomainException('BAD_BACKUP', 'الملف ليس نسخة احتياطية صالحة.');
    }
    if (env['format'] != format) throw const DomainException('BAD_BACKUP', 'الملف ليس نسخة احتياطية لـ Generator OS.');
    final kdf = env['kdf'] as Map<String, dynamic>;
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: kdf['iterations'] as int, bits: 256)
        .deriveKeyFromPassword(password: password, nonce: base64Decode(kdf['salt'] as String));
    try {
      final plain = await AesGcm.with256bits().decrypt(
          SecretBox(base64Decode(env['cipher'] as String),
              nonce: base64Decode(env['nonce'] as String), mac: Mac(base64Decode(env['mac'] as String))),
          secretKey: key);
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const DomainException('BAD_PASSWORD', 'كلمة المرور غير صحيحة أو أن الملف تالف.');
    }
  }

  /// Fills an empty, migrated database with the backup content.
  static Future<Map<String, int>> restoreInto(Database fresh, Map<String, dynamic> snapshot) async {
    final schema = snapshot['schema'] as int;
    if (schema > latestSchemaVersion) {
      throw const DomainException('NEWER_BACKUP', 'النسخة الاحتياطية من إصدار أحدث من التطبيق. حدّث التطبيق أولاً.');
    }
    final existing = await fresh.rawQuery('SELECT COUNT(*) c FROM users');
    if ((existing.first['c'] as int) > 0) {
      throw const DomainException('NOT_EMPTY', 'الاستعادة تتم إلى قاعدة بيانات فارغة فقط.');
    }
    final tables = (snapshot['tables'] as Map<String, dynamic>);
    final counts = <String, int>{};
    await fresh.execute('PRAGMA foreign_keys = OFF');
    try {
      await fresh.transaction((t) async {
        for (final name in await _tables(t)) {
          final rows = (tables[name] as List?) ?? const [];
          final cols = (await t.rawQuery('PRAGMA table_info($name)')).map((r) => r['name'] as String).toSet();
          for (final r in rows) {
            final row = Map<String, Object?>.from(r as Map)..removeWhere((k, _) => !cols.contains(k));
            await t.insert(name, row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          counts[name] = rows.length;
        }
      });
      final fk = await fresh.rawQuery('PRAGMA foreign_key_check');
      if (fk.isNotEmpty) {
        throw DomainException('BAD_BACKUP', 'النسخة الاحتياطية تحتوي على ${fk.length} سجلات غير مترابطة.');
      }
    } finally {
      await fresh.execute('PRAGMA foreign_keys = ON');
    }
    return counts;
  }
}
