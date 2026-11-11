import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:generator_core/generator_core.dart';
import 'package:generator_os_server/server.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as s3;
import 'package:test/test.dart';

const adminToken = 'test-admin-token-0123456789';
const ownerPass = 'Owner12345';

Future<GeneratorOS> device(String id, FixedClock clock) async {
  sqfliteFfiInit();
  final db = await openGeneratorDatabase(databaseFactoryFfi, inMemoryDatabasePath);
  return GeneratorOS(db, deviceId: id, clock: clock, hasher: const PasswordHasher(iterations: 1000));
}

void main() {
  late HttpServer http_;
  late String base;
  late Map<String, dynamic> tenant;
  final clock = FixedClock(DateTime(2026, 3, 10, 9));

  setUp(() async {
    final server = GeneratorOsServer(s3.sqlite3.openInMemory(), const ServerConfig(adminToken: adminToken));
    http_ = await io.serve(server.handler, InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${http_.port}';
    final res = await http.post(Uri.parse('$base/admin/tenants'),
        headers: {'authorization': 'Bearer $adminToken'}, body: jsonEncode({'name': 'مولدات الاختبار'}));
    expect(res.statusCode, 200);
    tenant = jsonDecode(res.body) as Map<String, dynamic>;
  });

  tearDown(() => http_.close(force: true));

  Future<void> pair(GeneratorOS os) => os.sync.pair(
      serverUrl: base, tenantCode: tenant['tenant_code'] as String, pairingSecret: tenant['pairing_secret'] as String);

  Future<int> count(GeneratorOS os, String table) async =>
      (await os.ctx.db.rawQuery('SELECT COUNT(*) c FROM $table')).first['c'] as int;

  test('admin API requires the admin token; pairing requires the secret', () async {
    final r = await http.get(Uri.parse('$base/admin/tenants'));
    expect(r.statusCode, 401);
    final a = await device('device-aaaaaaaa', clock);
    await expectLater(
        a.sync.pair(serverUrl: base, tenantCode: tenant['tenant_code'] as String, pairingSecret: 'wrong'),
        throwsA(isA<DomainException>()));
    final unauth = await http.post(Uri.parse('$base/api/v1/sync/pull'), body: '{}');
    expect(unauth.statusCode, 401);
  });

  test('two devices: offline payments merge without duplicates; balances converge', () async {
    final a = await device('device-aaaaaaaa', clock);
    await a.auth.createOwner(fullName: 'المالك', username: 'owner', password: ownerPass);
    await a.auth.login('owner', ownerPass);
    final gen = await a.network.createGenerator(name: 'مولدة الحي', defaultAmpPrice: 3000);
    final sub = await a.subscribers.create(gen, {'full_name': 'مشترك المزامنة', 'amps': 10, 'amp_price': 3000});
    await a.billing.generateMonth(gen, '2026-03');
    await pair(a);
    var r = await a.sync.syncNow();
    expect(r.ok, isTrue, reason: r.error);
    expect(r.pushed, greaterThan(10));

    // Device B starts empty, pairs and receives everything (incl. the owner account).
    final b = await device('device-bbbbbbbb', clock);
    await pair(b);
    r = await b.sync.syncNow();
    expect(r.ok, isTrue, reason: r.error);
    await b.auth.login('owner', ownerPass);
    expect(await b.subscribers.balance(sub), 30000);

    // Both devices go "offline" and each records a payment.
    await a.collection.recordPayment(subscriberId: sub, amount: 10000);
    await b.collection.recordPayment(subscriberId: sub, amount: 5000);
    expect(await a.subscribers.balance(sub), 20000);
    expect(await b.subscribers.balance(sub), 25000);

    // Back online.
    expect((await a.sync.syncNow()).ok, isTrue);
    expect((await b.sync.syncNow()).ok, isTrue);
    expect((await a.sync.syncNow()).ok, isTrue);
    expect(await a.subscribers.balance(sub), 15000);
    expect(await b.subscribers.balance(sub), 15000);
    expect(await count(a, 'payments'), 2);
    expect(await count(b, 'payments'), 2);

    // Replaying already-sent changes (e.g. lost response) must not duplicate.
    await a.ctx.db.update('sync_queue', {'status': 'pending'});
    r = await a.sync.syncNow();
    expect(r.ok, isTrue);
    await b.sync.syncNow();
    expect(await count(b, 'payments'), 2);
    expect(await b.subscribers.balance(sub), 15000);

    final ab = await a.ctx.db.rawQuery('SELECT SUM(debit) d, SUM(credit) c FROM journal_lines');
    final bb = await b.ctx.db.rawQuery('SELECT SUM(debit) d, SUM(credit) c FROM journal_lines');
    expect(ab.first, bb.first);
    expect(ab.first['d'], ab.first['c']);
    expect(await a.sync.lastSuccess(), isNotNull);
  });

  test('network failure keeps changes queued and retries later', () async {
    final a = await device('device-aaaaaaaa', clock);
    await a.auth.createOwner(fullName: 'المالك', username: 'owner', password: ownerPass);
    await a.auth.login('owner', ownerPass);
    await pair(a);
    final gen = await a.network.createGenerator(name: 'مولدة');
    await a.ctx.db.update('settings', {'value': 'http://127.0.0.1:1'}, where: "key = 'sync.server_url'");
    final fail = await a.sync.syncNow();
    expect(fail.ok, isFalse);
    expect(await a.sync.pendingCount(), greaterThan(0));
    final q = await a.ctx.db.query('sync_queue', where: "status = 'pending'", limit: 1);
    expect(q.first['attempts'], 1);
    expect(q.first['last_error'], isNotNull);
    final logs = await a.sync.log();
    expect(logs.first['ok'], 0);

    await a.ctx.db.update('settings', {'value': base}, where: "key = 'sync.server_url'");
    final ok = await a.sync.syncNow();
    expect(ok.ok, isTrue, reason: ok.error);
    expect(await a.sync.pendingCount(), 0);
    expect(gen, isNotEmpty);
  });

  test('same month billed offline on two devices yields one invoice per subscriber', () async {
    final a = await device('device-aaaaaaaa', clock);
    await a.auth.createOwner(fullName: 'المالك', username: 'owner', password: ownerPass);
    await a.auth.login('owner', ownerPass);
    final gen = await a.network.createGenerator(name: 'مولدة', defaultAmpPrice: 2000);
    final sub = await a.subscribers.create(gen, {'full_name': 'مشترك أول', 'amps': 4, 'amp_price': 2000});
    await pair(a);
    await a.sync.syncNow();
    final b = await device('device-bbbbbbbb', clock);
    await pair(b);
    await b.sync.syncNow();
    await b.auth.login('owner', ownerPass);

    // Both bill March while offline.
    await a.billing.generateMonth(gen, '2026-03');
    clock.advance(const Duration(minutes: 5));
    await b.billing.generateMonth(gen, '2026-03');
    expect((await a.sync.syncNow()).ok, isTrue);
    final rb = await b.sync.syncNow();
    expect(rb.ok, isTrue);
    await a.sync.syncNow();

    expect(await count(a, 'invoices'), 1);
    expect(await count(b, 'invoices'), 1);
    expect(await a.subscribers.balance(sub), 8000);
    expect(await b.subscribers.balance(sub), 8000, reason: 'no double charge');
  });

  test('concurrent edits of master data converge by server arrival order', () async {
    final a = await device('device-aaaaaaaa', clock);
    await a.auth.createOwner(fullName: 'المالك', username: 'owner', password: ownerPass);
    await a.auth.login('owner', ownerPass);
    final gen = await a.network.createGenerator(name: 'مولدة');
    final sub = await a.subscribers.create(gen, {'full_name': 'الاسم الأصلي', 'amps': 4, 'amp_price': 2000});
    await pair(a);
    await a.sync.syncNow();
    final b = await device('device-bbbbbbbb', clock);
    await pair(b);
    await b.sync.syncNow();
    await b.auth.login('owner', ownerPass);

    await a.subscribers.update(sub, {'phone': '07700000001'});
    await b.subscribers.update(sub, {'phone': '07700000002'});
    await a.sync.syncNow(); // A arrives first
    await b.sync.syncNow(); // B arrives last -> wins
    await a.sync.syncNow();
    expect((await a.subscribers.get(sub))['phone'], '07700000002');
    expect((await b.subscribers.get(sub))['phone'], '07700000002');

    final st = await http.get(Uri.parse('$base/admin/devices'), headers: {'authorization': 'Bearer $adminToken'});
    final devices = (jsonDecode(st.body) as List).cast<Map>();
    expect(devices.length, 2);

    // Revoking device B on the server blocks its sync.
    final devB = devices.firstWhere((d) => d['device_id'] == 'device-bbbbbbbb');
    await http.post(Uri.parse('$base/admin/devices/${devB['id']}/revoke'), headers: {'authorization': 'Bearer $adminToken'});
    await b.subscribers.update(sub, {'notes': 'بعد الإبطال'});
    final res = await b.sync.syncNow();
    expect(res.ok, isFalse);
  });

  test('server-issued licence verifies on the device', () async {
    final seed = List<int>.generate(32, (i) => i + 1);
    final pub = await (await cg.Ed25519().newKeyPairFromSeed(seed)).extractPublicKey();
    final key = await signLicense({
      'license_id': 'L-x', 'customer': 'عميل', 'max_generators': 2, 'device_ids': ['device-aaaaaaaa'],
      'issued_at': '2026-03-10', 'services': {},
    }, seed);
    sqfliteFfiInit();
    final db = await openGeneratorDatabase(databaseFactoryFfi, inMemoryDatabasePath);
    final os = GeneratorOS(db, deviceId: 'device-aaaaaaaa', clock: clock, licensePublicKey: pub.bytes);
    final lic = await os.license.activate(key);
    expect(lic.maxGenerators, 2);
  });
}
