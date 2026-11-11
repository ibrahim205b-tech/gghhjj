import 'package:sqflite_common/sqlite_api.dart';

import '../security/password.dart';
import '../security/permissions.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';

class AuthService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final PasswordHasher hasher;

  static const maxFailedAttempts = 5;
  static const lockDuration = Duration(minutes: 10);

  AuthService(this.ctx, this.store, this.audit, {this.hasher = const PasswordHasher()});

  Future<bool> isInitialized() async {
    final r = await ctx.db.rawQuery('SELECT COUNT(*) AS c FROM users');
    return ((r.first['c'] as int?) ?? 0) > 0;
  }

  /// Creates the built-in roles if missing (idempotent).
  Future<void> ensureSystemRoles(DatabaseExecutor ex) async {
    for (final role in systemRoles) {
      final exists = await ex.query('roles', where: 'id = ?', whereArgs: [role.id]);
      if (exists.isNotEmpty) continue;
      await store.insert(ex, 'roles', {'id': role.id, 'name': role.name, 'is_system': 1});
      for (final p in role.permissions) {
        await store.insert(ex, 'role_permissions', {
          'id': '${role.id}:$p', 'role_id': role.id, 'permission': p, 'granted': 1,
        });
      }
    }
  }

  static void validatePassword(String password) {
    if (password.length < 8) {
      throw validation('كلمة المرور يجب أن تكون 8 أحرف على الأقل.');
    }
    if (!RegExp(r'\d').hasMatch(password) || !RegExp(r'[A-Za-z؀-ۿ]').hasMatch(password)) {
      throw validation('كلمة المرور يجب أن تحتوي على حروف وأرقام.');
    }
  }

  static String normalizeUsername(String u) => u.trim().toLowerCase();

  /// First-run: creates roles and the owner account. Returns the owner id.
  Future<String> createOwner({
    required String fullName,
    required String username,
    required String password,
    String? phone,
  }) async {
    if (await isInitialized()) {
      throw const DomainException('ALREADY_INITIALIZED', 'تم إعداد النظام مسبقاً.');
    }
    validatePassword(password);
    final hash = await hasher.hash(password);
    final id = newId();
    await ctx.db.transaction((txn) async {
      await ensureSystemRoles(txn);
      await store.insert(txn, 'users', {
        'id': id,
        'username': normalizeUsername(username),
        'full_name': fullName.trim(),
        'phone': phone,
        'role_id': roleOwner,
        'password_hash': hash,
        'all_generators': 1,
      });
      await audit.log(txn, 'system.setup', entity: 'users', entityId: id);
    });
    return id;
  }

  Future<Set<String>> permissionsOf(String roleId, [DatabaseExecutor? ex]) async {
    final rows = await (ex ?? ctx.db)
        .query('role_permissions', where: 'role_id = ? AND granted = 1', whereArgs: [roleId]);
    return rows.map((r) => r['permission'] as String).toSet();
  }

  Future<Session> login(String username, String password) async {
    final uname = normalizeUsername(username);
    final rows = await ctx.db.query('users', where: 'username = ?', whereArgs: [uname]);
    if (rows.isEmpty) {
      await ctx.db.transaction((t) => audit.log(t, 'auth.login_failed', details: {'username': uname}));
      throw const DomainException('BAD_CREDENTIALS', 'اسم المستخدم أو كلمة المرور غير صحيحة.');
    }
    final u = rows.first;
    final userId = u['id'] as String;
    if ((u['active'] as int) != 1) {
      throw const DomainException('USER_DISABLED', 'هذا الحساب موقوف. راجع المالك.');
    }
    final lockedUntil = u['locked_until'] as String?;
    if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(ctx.now)) {
      throw const DomainException('LOCKED', 'تم قفل الحساب مؤقتاً بسبب محاولات دخول فاشلة متكررة. حاول لاحقاً.');
    }
    final dev = await ctx.db.query('devices', where: 'id = ?', whereArgs: [ctx.deviceId]);
    if (dev.isNotEmpty && dev.first['revoked'] == 1) {
      throw const DomainException('DEVICE_REVOKED', 'تم إبطال صلاحية هذا الجهاز.');
    }

    final ok = await hasher.verify(password, u['password_hash'] as String);
    if (!ok) {
      final attempts = (u['failed_attempts'] as int) + 1;
      await ctx.db.transaction((t) async {
        await t.update(
            'users',
            {
              'failed_attempts': attempts,
              'locked_until': attempts >= maxFailedAttempts ? ctx.now.add(lockDuration).toIso8601String() : null,
            },
            where: 'id = ?',
            whereArgs: [userId]);
        await audit.log(t, 'auth.login_failed', entity: 'users', entityId: userId, details: {'attempts': attempts});
        if (attempts >= maxFailedAttempts) {
          await t.insert(
              'notifications',
              {
                'id': newId(),
                'kind': 'security',
                'severity': 'high',
                'title': 'محاولات دخول غير طبيعية',
                'body': 'تم قفل حساب "$uname" مؤقتاً بعد $attempts محاولات فاشلة.',
                'created_at': ctx.nowIso,
                'dedupe_key': 'lock:$userId:${ctx.today}',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
      throw const DomainException('BAD_CREDENTIALS', 'اسم المستخدم أو كلمة المرور غير صحيحة.');
    }

    final perms = await permissionsOf(u['role_id'] as String);
    final gens = await ctx.db.query('user_generators',
        columns: ['generator_id'], where: 'user_id = ? AND active = 1', whereArgs: [userId]);
    final col = await ctx.db.query('collectors', columns: ['id'], where: 'user_id = ? AND active = 1', whereArgs: [userId]);
    final sessionId = newId();
    await ctx.db.transaction((t) async {
      await t.update('users', {'failed_attempts': 0, 'locked_until': null}, where: 'id = ?', whereArgs: [userId]);
      if (dev.isEmpty) {
        await t.insert('devices', {'id': ctx.deviceId, 'first_seen': ctx.nowIso, 'last_seen': ctx.nowIso});
      } else {
        await t.update('devices', {'last_seen': ctx.nowIso}, where: 'id = ?', whereArgs: [ctx.deviceId]);
      }
      await t.insert('sessions', {
        'id': sessionId, 'user_id': userId, 'device_id': ctx.deviceId,
        'created_at': ctx.nowIso, 'last_active': ctx.nowIso,
      });
    });
    final session = Session(
      sessionId: sessionId,
      userId: userId,
      username: uname,
      fullName: u['full_name'] as String,
      roleId: u['role_id'] as String,
      permissions: perms,
      allGenerators: (u['all_generators'] as int) == 1,
      generatorIds: gens.map((g) => g['generator_id'] as String).toSet(),
      collectorId: col.isEmpty ? null : col.first['id'] as String,
    );
    ctx.session = session;
    await ctx.db.transaction((t) => audit.log(t, 'auth.login', entity: 'users', entityId: userId));
    return session;
  }

  /// Validates that the current session was not revoked from another screen.
  Future<bool> sessionValid() async {
    final s = ctx.session;
    if (s == null) return false;
    final r = await ctx.db.query('sessions', where: 'id = ?', whereArgs: [s.sessionId]);
    return r.isNotEmpty && r.first['revoked'] == 0;
  }

  Future<void> logout() async {
    final s = ctx.session;
    if (s == null) return;
    await ctx.db.transaction((t) async {
      await t.update('sessions', {'revoked': 1}, where: 'id = ?', whereArgs: [s.sessionId]);
      await audit.log(t, 'auth.logout', entity: 'users', entityId: s.userId);
    });
    ctx.session = null;
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final s = ctx.session;
    if (s == null) throw const DomainException('NOT_AUTHENTICATED', 'يجب تسجيل الدخول أولاً.');
    final u = (await ctx.db.query('users', where: 'id = ?', whereArgs: [s.userId])).first;
    if (!await hasher.verify(oldPassword, u['password_hash'] as String)) {
      throw const DomainException('BAD_CREDENTIALS', 'كلمة المرور الحالية غير صحيحة.');
    }
    validatePassword(newPassword);
    final hash = await hasher.hash(newPassword);
    await ctx.db.transaction((t) async {
      await store.update(t, 'users', s.userId, {'password_hash': hash});
      await audit.log(t, 'auth.password_changed', entity: 'users', entityId: s.userId);
    });
  }

  // ------------------------------------------------------------ users admin

  Future<List<Map<String, Object?>>> listUsers() {
    ctx.require(Perm.usersManage);
    return ctx.db.rawQuery('''SELECT u.id, u.username, u.full_name, u.phone, u.role_id, u.active,
        u.all_generators, r.name AS role_name FROM users u JOIN roles r ON r.id = u.role_id
        ORDER BY u.created_at''');
  }

  Future<String> createUser({
    required String fullName,
    required String username,
    required String password,
    required String roleId,
    String? phone,
    bool allGenerators = false,
    List<String> generatorIds = const [],
  }) async {
    ctx.require(Perm.usersManage);
    if (roleId == roleOwner && ctx.session?.roleId != roleOwner) {
      throw const PermissionDenied('owner.create');
    }
    validatePassword(password);
    final uname = normalizeUsername(username);
    if (uname.length < 3) throw validation('اسم المستخدم قصير جداً.');
    final dup = await ctx.db.query('users', where: 'username = ?', whereArgs: [uname]);
    if (dup.isNotEmpty) throw validation('اسم المستخدم مستخدم مسبقاً.');
    final hash = await hasher.hash(password);
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'users', {
        'id': id, 'username': uname, 'full_name': fullName.trim(), 'phone': phone,
        'role_id': roleId, 'password_hash': hash, 'all_generators': allGenerators ? 1 : 0,
      });
      for (final g in generatorIds) {
        await store.insert(t, 'user_generators', {'id': '$id:$g', 'user_id': id, 'generator_id': g});
      }
      await audit.log(t, 'users.create', entity: 'users', entityId: id, details: {'role': roleId});
    });
    return id;
  }

  Future<void> setUserActive(String userId, bool active) async {
    ctx.require(Perm.usersManage);
    if (userId == ctx.userId) throw validation('لا يمكنك إيقاف حسابك الحالي.');
    await ctx.db.transaction((t) async {
      await store.update(t, 'users', userId, {'active': active ? 1 : 0});
      if (!active) await t.update('sessions', {'revoked': 1}, where: 'user_id = ?', whereArgs: [userId]);
      await audit.log(t, active ? 'users.activate' : 'users.deactivate', entity: 'users', entityId: userId);
    });
  }

  Future<void> resetPassword(String userId, String newPassword) async {
    ctx.require(Perm.usersManage);
    validatePassword(newPassword);
    final hash = await hasher.hash(newPassword);
    await ctx.db.transaction((t) async {
      await store.update(t, 'users', userId, {'password_hash': hash, 'failed_attempts': 0, 'locked_until': null});
      await t.update('sessions', {'revoked': 1}, where: 'user_id = ?', whereArgs: [userId]);
      await audit.log(t, 'users.reset_password', entity: 'users', entityId: userId);
    });
  }

  Future<void> setUserGenerators(String userId, List<String> generatorIds) async {
    ctx.require(Perm.usersManage);
    await ctx.db.transaction((t) async {
      final existing = await t.query('user_generators', where: 'user_id = ?', whereArgs: [userId]);
      for (final e in existing) {
        final active = generatorIds.contains(e['generator_id']) ? 1 : 0;
        if (e['active'] != active) await store.update(t, 'user_generators', e['id'] as String, {'active': active});
      }
      for (final g in generatorIds) {
        if (existing.any((e) => e['generator_id'] == g)) continue;
        await store.insert(t, 'user_generators', {'id': '$userId:$g', 'user_id': userId, 'generator_id': g});
      }
      await audit.log(t, 'users.generators', entity: 'users', entityId: userId, details: {'generators': generatorIds});
    });
  }

  // ------------------------------------------------------------------ roles

  Future<List<Map<String, Object?>>> listRoles() => ctx.db.query('roles', orderBy: 'created_at');

  Future<void> setRolePermission(String roleId, String permission, bool granted) async {
    ctx.require(Perm.usersManage);
    if (roleId == roleOwner) throw validation('صلاحيات المالك ثابتة ولا يمكن تقليصها.');
    if (!Perm.all.contains(permission)) throw validation('صلاحية غير معروفة.');
    await ctx.db.transaction((t) async {
      final id = '$roleId:$permission';
      final r = await t.query('role_permissions', where: 'id = ?', whereArgs: [id]);
      if (r.isEmpty) {
        await store.insert(t, 'role_permissions',
            {'id': id, 'role_id': roleId, 'permission': permission, 'granted': granted ? 1 : 0});
      } else {
        await store.update(t, 'role_permissions', id, {'granted': granted ? 1 : 0});
      }
      await audit.log(t, 'roles.permission', entity: 'roles', entityId: roleId,
          details: {'permission': permission, 'granted': granted});
    });
  }

  Future<String> createRole(String name, Set<String> permissions) async {
    ctx.require(Perm.usersManage);
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'roles', {'id': id, 'name': name.trim(), 'is_system': 0});
      for (final p in permissions.where(Perm.all.contains)) {
        await store.insert(t, 'role_permissions', {'id': '$id:$p', 'role_id': id, 'permission': p, 'granted': 1});
      }
      await audit.log(t, 'roles.create', entity: 'roles', entityId: id);
    });
    return id;
  }

  // ---------------------------------------------------------------- devices

  Future<List<Map<String, Object?>>> listDevices() {
    ctx.require(Perm.usersManage);
    return ctx.db.query('devices', orderBy: 'last_seen DESC');
  }

  Future<List<Map<String, Object?>>> listSessions() {
    ctx.require(Perm.usersManage);
    return ctx.db.rawQuery('''SELECT s.*, u.full_name FROM sessions s JOIN users u ON u.id = s.user_id
        WHERE s.revoked = 0 ORDER BY s.last_active DESC''');
  }

  Future<void> revokeSession(String sessionId) async {
    ctx.require(Perm.usersManage);
    await ctx.db.transaction((t) async {
      await t.update('sessions', {'revoked': 1}, where: 'id = ?', whereArgs: [sessionId]);
      await audit.log(t, 'sessions.revoke', entity: 'sessions', entityId: sessionId);
    });
  }
}
