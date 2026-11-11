import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tables whose rows are append-only on clients. Must match the client
/// schema (packages/generator_core/lib/src/db/schema.dart).
const immutableTables = {
  'accounts', 'journal_entries', 'journal_lines', 'invoices', 'invoice_adjustments', 'payments',
  'collector_handovers', 'expenses', 'fuel_purchases', 'fuel_consumptions', 'fuel_dips', 'cash_closings',
  'subscriber_events', 'complaint_replies', 'audit_logs', 'sensor_readings',
};
const mutableTables = {
  'generators', 'branches', 'areas', 'cabinets', 'lines', 'subscribers', 'users', 'roles', 'role_permissions',
  'user_generators', 'collectors', 'collector_assignments', 'cashboxes', 'suppliers', 'employees',
  'billing_periods', 'maintenance_plans', 'maintenance_records', 'fault_records', 'complaints', 'generator_runs',
  'iot_devices',
};

/// Metadata fields that legitimately differ between two devices producing
/// the same deterministic document.
const _metaFields = {'created_at', 'created_by', 'device_id'};

String _sha(String v) => sha256.convert(utf8.encode(v)).toString();

String _token([int bytes = 32]) {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
}

String canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(canonical).join(',')}]';
  return jsonEncode(v);
}

bool _sameDocument(Map a, Map b) {
  Map strip(Map m) => Map.of(m)..removeWhere((k, _) => _metaFields.contains(k));
  return canonical(strip(a)) == canonical(strip(b));
}

class ServerConfig {
  final String adminToken;
  /// Ed25519 private key seed (32 bytes, base64) used to sign licences.
  /// Optional: licence issuing is disabled without it.
  final String? licenseSeedB64;
  const ServerConfig({required this.adminToken, this.licenseSeedB64});
}

class GeneratorOsServer {
  final Database db;
  final ServerConfig config;

  GeneratorOsServer(this.db, this.config) {
    _migrate();
  }

  void _migrate() {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('''
      CREATE TABLE IF NOT EXISTS tenants(id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
        pairing_hash TEXT NOT NULL, created_at TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
        share_status INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, device_id TEXT NOT NULL,
        name TEXT, token_hash TEXT UNIQUE NOT NULL, revoked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, last_seen TEXT, UNIQUE(tenant_id, device_id));
      CREATE TABLE IF NOT EXISTS changes(seq INTEGER PRIMARY KEY AUTOINCREMENT, tenant_id TEXT NOT NULL,
        table_name TEXT NOT NULL, row_id TEXT NOT NULL, payload TEXT NOT NULL, device_id TEXT NOT NULL,
        received_at TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS idx_changes_tenant ON changes(tenant_id, seq);
      CREATE TABLE IF NOT EXISTS processed_keys(tenant_id TEXT NOT NULL, idem_key TEXT NOT NULL,
        received_at TEXT NOT NULL, PRIMARY KEY(tenant_id, idem_key));
      CREATE TABLE IF NOT EXISTS current_rows(tenant_id TEXT NOT NULL, table_name TEXT NOT NULL, row_id TEXT NOT NULL,
        payload TEXT NOT NULL, last_seq INTEGER NOT NULL, device_id TEXT NOT NULL,
        PRIMARY KEY(tenant_id, table_name, row_id));
      CREATE TABLE IF NOT EXISTS conflicts(id INTEGER PRIMARY KEY AUTOINCREMENT, tenant_id TEXT NOT NULL,
        at TEXT NOT NULL, table_name TEXT NOT NULL, row_id TEXT NOT NULL, device_id TEXT NOT NULL,
        incoming TEXT, existing TEXT, resolution TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS licenses(id TEXT PRIMARY KEY, customer TEXT NOT NULL, payload TEXT NOT NULL,
        license_key TEXT NOT NULL, issued_at TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, notes TEXT);
      CREATE TABLE IF NOT EXISTS releases(version TEXT PRIMARY KEY, notes TEXT, url TEXT, published_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS support_tickets(id INTEGER PRIMARY KEY AUTOINCREMENT, tenant_id TEXT,
        device_id TEXT, subject TEXT NOT NULL, body TEXT, status TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL);
    ''');
  }

  String get _now => DateTime.now().toUtc().toIso8601String();

  Response _json(Object body, [int status = 200]) =>
      Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8'});

  Response _error(int status, String message) => _json({'error': message}, status);

  Future<Map<String, dynamic>> _body(Request r) async {
    final s = await r.readAsString();
    if (s.isEmpty) return {};
    final v = jsonDecode(s);
    if (v is! Map<String, dynamic>) throw const FormatException('JSON object expected');
    return v;
  }

  String? _bearer(Request r) {
    final h = r.headers['authorization'];
    if (h == null || !h.startsWith('Bearer ')) return null;
    return h.substring(7).trim();
  }

  bool _isAdmin(Request r) {
    final t = _bearer(r);
    if (t == null || config.adminToken.length < 16) return false;
    // constant-time comparison
    final a = utf8.encode(t), b = utf8.encode(config.adminToken);
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// Returns (tenantId, deviceId) for a valid, non-revoked device token.
  (String, String)? _device(Request r) {
    final t = _bearer(r);
    if (t == null) return null;
    final rows = db.select('''SELECT d.tenant_id, d.device_id FROM devices d JOIN tenants t ON t.id = d.tenant_id
        WHERE d.token_hash = ? AND d.revoked = 0 AND t.active = 1''', [_sha(t)]);
    if (rows.isEmpty) return null;
    db.execute('UPDATE devices SET last_seen = ? WHERE token_hash = ?', [_now, _sha(t)]);
    return (rows.first['tenant_id'] as String, rows.first['device_id'] as String);
  }

  Handler get handler {
    final app = Router();
    app.get('/health', (Request r) => _json({'ok': true, 'time': _now}));

    // ---------------------------------------------------------- devices
    app.post('/api/v1/pair', (Request r) async {
      final b = await _body(r);
      final code = b['tenant_code'] as String?;
      final secret = b['pairing_secret'] as String?;
      final deviceId = b['device_id'] as String?;
      if (code == null || secret == null || deviceId == null || deviceId.length < 8) {
        return _error(400, 'بيانات الربط ناقصة.');
      }
      final t = db.select('SELECT * FROM tenants WHERE code = ? AND active = 1', [code]);
      if (t.isEmpty || t.first['pairing_hash'] != _sha(secret)) return _error(403, 'رمز الربط غير صحيح.');
      final tenantId = t.first['id'] as String;
      final existing = db.select('SELECT revoked FROM devices WHERE tenant_id = ? AND device_id = ?', [tenantId, deviceId]);
      if (existing.isNotEmpty && existing.first['revoked'] == 1) return _error(403, 'تم إبطال هذا الجهاز.');
      final token = _token();
      db.execute('''INSERT INTO devices(id, tenant_id, device_id, name, token_hash, created_at, last_seen)
          VALUES(?,?,?,?,?,?,?) ON CONFLICT(tenant_id, device_id) DO UPDATE SET token_hash = excluded.token_hash,
          name = excluded.name, last_seen = excluded.last_seen''',
          [_token(12), tenantId, deviceId, b['device_name'], _sha(token), _now, _now]);
      return _json({'device_token': token, 'tenant': t.first['name']});
    });

    // ------------------------------------------------------------- sync
    app.post('/api/v1/sync/push', (Request r) async {
      final dev = _device(r);
      if (dev == null) return _error(401, 'الجهاز غير مصرح.');
      final (tenant, deviceId) = dev;
      final b = await _body(r);
      final changes = (b['changes'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (changes.length > 1000) return _error(413, 'دفعة كبيرة جداً.');
      final accepted = <String>[];
      final conflicts = <Map<String, Object?>>[];
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final c in changes) {
          final key = c['key'] as String?;
          final table = c['table'] as String?;
          final id = c['id'] as String?;
          final payload = c['payload'];
          if (key == null || table == null || id == null || payload is! Map) continue;
          if (!immutableTables.contains(table) && !mutableTables.contains(table)) continue;
          final seen = db.select('SELECT 1 FROM processed_keys WHERE tenant_id = ? AND idem_key = ?', [tenant, key]);
          if (seen.isNotEmpty) {
            accepted.add(key); // replay of an already processed change
            continue;
          }
          db.execute('INSERT INTO processed_keys VALUES(?,?,?)', [tenant, key, _now]);
          final cur = db.select('SELECT payload, device_id FROM current_rows WHERE tenant_id = ? AND table_name = ? AND row_id = ?',
              [tenant, table, id]);
          if (immutableTables.contains(table) && cur.isNotEmpty) {
            final existing = jsonDecode(cur.first['payload'] as String) as Map;
            if (_sameDocument(existing, payload)) {
              accepted.add(key);
            } else {
              db.execute('''INSERT INTO conflicts(tenant_id, at, table_name, row_id, device_id, incoming, existing, resolution)
                  VALUES(?,?,?,?,?,?,?,?)''',
                  [tenant, _now, table, id, deviceId, jsonEncode(payload), cur.first['payload'], 'kept_first']);
              conflicts.add({
                'key': key, 'table': table, 'id': id, 'server_payload': existing, 'resolution': 'server_kept_first',
              });
            }
            continue;
          }
          if (mutableTables.contains(table) && cur.isNotEmpty && cur.first['device_id'] != deviceId) {
            final existing = jsonDecode(cur.first['payload'] as String) as Map;
            final vIn = payload['version'] as int? ?? 0;
            final vCur = existing['version'] as int? ?? 0;
            if (vIn <= vCur && !_sameDocument(existing, payload)) {
              // Concurrent edit from two devices: last arrival wins, logged.
              db.execute('''INSERT INTO conflicts(tenant_id, at, table_name, row_id, device_id, incoming, existing, resolution)
                  VALUES(?,?,?,?,?,?,?,?)''',
                  [tenant, _now, table, id, deviceId, jsonEncode(payload), cur.first['payload'], 'last_arrival_wins']);
            }
          }
          final p = jsonEncode(payload);
          db.execute('INSERT INTO changes(tenant_id, table_name, row_id, payload, device_id, received_at) VALUES(?,?,?,?,?,?)',
              [tenant, table, id, p, deviceId, _now]);
          final seq = db.lastInsertRowId;
          db.execute('''INSERT INTO current_rows VALUES(?,?,?,?,?,?) ON CONFLICT(tenant_id, table_name, row_id)
              DO UPDATE SET payload = excluded.payload, last_seq = excluded.last_seq, device_id = excluded.device_id''',
              [tenant, table, id, p, seq, deviceId]);
          accepted.add(key);
        }
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        return _error(500, 'خطأ في الخادم أثناء الحفظ.');
      }
      return _json({'accepted': accepted, 'conflicts': conflicts});
    });

    app.post('/api/v1/sync/pull', (Request r) async {
      final dev = _device(r);
      if (dev == null) return _error(401, 'الجهاز غير مصرح.');
      final b = await _body(r);
      final cursor = (b['cursor'] as int?) ?? 0;
      final limit = ((b['limit'] as int?) ?? 500).clamp(1, 1000);
      final rows = db.select('''SELECT seq, table_name, row_id, payload FROM changes WHERE tenant_id = ? AND seq > ?
          ORDER BY seq LIMIT ?''', [dev.$1, cursor, limit + 1]);
      final more = rows.length > limit;
      final page = rows.take(limit).toList();
      return _json({
        'changes': [
          for (final row in page)
            {'seq': row['seq'], 'table': row['table_name'], 'id': row['row_id'], 'payload': jsonDecode(row['payload'] as String)}
        ],
        'cursor': page.isEmpty ? cursor : page.last['seq'],
        'has_more': more,
      });
    });

    app.post('/api/v1/support', (Request r) async {
      final dev = _device(r);
      if (dev == null) return _error(401, 'الجهاز غير مصرح.');
      final b = await _body(r);
      final subject = (b['subject'] as String?)?.trim() ?? '';
      if (subject.isEmpty) return _error(400, 'العنوان مطلوب.');
      db.execute('INSERT INTO support_tickets(tenant_id, device_id, subject, body, created_at) VALUES(?,?,?,?,?)',
          [dev.$1, dev.$2, subject, b['body'], _now]);
      return _json({'ok': true, 'id': db.lastInsertRowId});
    });

    app.get('/api/v1/releases/latest', (Request r) {
      final rows = db.select('SELECT * FROM releases ORDER BY published_at DESC LIMIT 1');
      return _json(rows.isEmpty ? {} : Map<String, Object?>.from(rows.first));
    });

    // ------------------------------------------------------------ admin
    // The admin API manages customers, devices, licences and releases. It
    // deliberately has no endpoint that returns customers' financial rows;
    // sync status is aggregate counts only, and only for tenants that opted in.
    final admin = Router();
    admin.post('/tenants', (Request r) async {
      final b = await _body(r);
      final name = (b['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) return _error(400, 'name required');
      final id = _token(9), code = 'T${_token(6).toUpperCase()}', secret = _token(18);
      db.execute('INSERT INTO tenants(id, code, name, pairing_hash, created_at, share_status) VALUES(?,?,?,?,?,?)',
          [id, code, name, _sha(secret), _now, b['share_status'] == true ? 1 : 0]);
      return _json({'id': id, 'tenant_code': code, 'pairing_secret': secret});
    });
    admin.get('/tenants', (Request r) => _json(db
        .select('''SELECT t.id, t.code, t.name, t.active, t.created_at, t.share_status,
            (SELECT COUNT(*) FROM devices d WHERE d.tenant_id = t.id AND d.revoked = 0) AS devices FROM tenants t''')
        .map((e) => Map<String, Object?>.from(e))
        .toList()));
    admin.get('/devices', (Request r) => _json(db
        .select('SELECT id, tenant_id, device_id, name, revoked, created_at, last_seen FROM devices ORDER BY last_seen DESC')
        .map((e) => Map<String, Object?>.from(e))
        .toList()));
    admin.post('/devices/<id>/revoke', (Request r, String id) {
      db.execute('UPDATE devices SET revoked = 1 WHERE id = ?', [id]);
      return _json({'ok': db.updatedRows > 0});
    });
    admin.get('/sync-status', (Request r) => _json(db
        .select('''SELECT t.id, t.name, (SELECT COUNT(*) FROM changes c WHERE c.tenant_id = t.id) AS changes,
            (SELECT MAX(received_at) FROM changes c WHERE c.tenant_id = t.id) AS last_change,
            (SELECT COUNT(*) FROM conflicts x WHERE x.tenant_id = t.id) AS conflicts
            FROM tenants t WHERE t.share_status = 1''')
        .map((e) => Map<String, Object?>.from(e))
        .toList()));
    admin.post('/licenses', (Request r) async {
      final seed = config.licenseSeedB64;
      if (seed == null) return _error(503, 'licence signing key not configured');
      final b = await _body(r);
      final payload = {
        'license_id': 'L-${_token(8)}',
        'customer': b['customer'],
        'edition': b['edition'] ?? 'perpetual',
        'max_generators': b['max_generators'] ?? 1,
        'device_ids': b['device_ids'] ?? <String>[],
        'issued_at': DateTime.now().toUtc().toIso8601String().substring(0, 10),
        'services': b['services'] ?? <String, String>{},
      };
      if (payload['customer'] is! String) return _error(400, 'customer required');
      final key = await signLicense(payload, base64Decode(seed));
      db.execute('INSERT INTO licenses(id, customer, payload, license_key, issued_at, notes) VALUES(?,?,?,?,?,?)',
          [payload['license_id'], payload['customer'], jsonEncode(payload), key, _now, b['notes']]);
      return _json({'license_id': payload['license_id'], 'license_key': key});
    });
    admin.get('/licenses', (Request r) => _json(db
        .select('SELECT id, customer, payload, issued_at, revoked, notes FROM licenses ORDER BY issued_at DESC')
        .map((e) => Map<String, Object?>.from(e))
        .toList()));
    admin.post('/releases', (Request r) async {
      final b = await _body(r);
      db.execute('INSERT OR REPLACE INTO releases VALUES(?,?,?,?)', [b['version'], b['notes'], b['url'], _now]);
      return _json({'ok': true});
    });
    admin.get('/support', (Request r) => _json(db
        .select('SELECT * FROM support_tickets ORDER BY created_at DESC')
        .map((e) => Map<String, Object?>.from(e))
        .toList()));

    app.mount('/admin/', (Request r) {
      if (!_isAdmin(r)) return _error(401, 'unauthorized');
      return admin.call(r);
    });

    return const Pipeline().addMiddleware(_errors()).addHandler(app.call);
  }

  Middleware _errors() => (inner) => (request) async {
        try {
          return await inner(request);
        } on FormatException {
          return _error(400, 'صيغة الطلب غير صحيحة.');
        } on TypeError {
          return _error(400, 'حقول الطلب غير صحيحة.');
        }
      };
}

/// Signs a licence payload: base64url(json) + '.' + base64url(ed25519 sig).
Future<String> signLicense(Map<String, Object?> payload, List<int> seed) async {
  final kp = await cg.Ed25519().newKeyPairFromSeed(seed);
  final bytes = utf8.encode(jsonEncode(payload));
  final sig = await cg.Ed25519().sign(bytes, keyPair: kp);
  return '${base64Url.encode(bytes).replaceAll('=', '')}.${base64Url.encode(sig.bytes).replaceAll('=', '')}';
}
