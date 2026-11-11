import 'package:generator_core/generator_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Test fixture data. Completely separate from any customer data: every test
/// uses its own in-memory database that disappears after the test.
class Fixture {
  final GeneratorOS os;
  final FixedClock clock;
  final String generatorId;
  final String areaId;
  final String cabinetId;
  Fixture(this.os, this.clock, this.generatorId, this.areaId, this.cabinetId);
}

const testPassword = 'Owner12345';
const fastHasher = PasswordHasher(iterations: 1000);

Future<Database> openTestDb() async {
  sqfliteFfiInit();
  return openGeneratorDatabase(databaseFactoryFfi, inMemoryDatabasePath);
}

Future<GeneratorOS> newOs(Database db, FixedClock clock, {String deviceId = 'device-test-a', List<int>? pubKey}) async =>
    GeneratorOS(db,
        deviceId: deviceId,
        clock: clock,
        hasher: fastHasher,
        backupKdfIterations: 1000,
        licensePublicKey: pubKey ?? const []);

/// Owner logged in, one generator (3,000 IQD/amp default), one area and one
/// cabinet with a 100 A limit.
Future<Fixture> setup({DateTime? now, int maxGenerators = 10}) async {
  final clock = FixedClock(now ?? DateTime(2026, 3, 15, 10));
  final db = await openTestDb();
  final os = await newOs(db, clock);
  os.network.maxGenerators = () async => maxGenerators;
  await os.auth.createOwner(fullName: 'مالك الاختبار', username: 'owner', password: testPassword);
  await os.auth.login('owner', testPassword);
  final gen = await os.network.createGenerator(name: 'مولدة الاختبار', defaultAmpPrice: 3000);
  final area = await os.network.createArea(gen, 'حي الاختبار');
  final cab = await os.network.createCabinet(gen, 'K1', areaId: area, maxAmps: 100);
  return Fixture(os, clock, gen, area, cab);
}

Future<String> addSubscriber(Fixture f, {String name = 'مشترك تجريبي', int amps = 5, int? price, int openingDebt = 0,
    String type = 'normal'}) {
  return f.os.subscribers.create(
      f.generatorId,
      {
        'full_name': name,
        'phone': '07701234567',
        'amps': amps,
        'amp_price': price ?? 3000,
        'area_id': f.areaId,
        'cabinet_id': f.cabinetId,
        'subscription_type': type,
        'start_date': '2026-01-01',
      },
      openingDebt: openingDebt);
}

/// Asserts the fundamental accounting identity: total debits == total credits.
Future<void> expectBalancedLedger(GeneratorOS os) async {
  final r = await os.ctx.db.rawQuery('SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c FROM journal_lines');
  if (r.first['d'] != r.first['c']) {
    throw StateError('Ledger unbalanced: ${r.first}');
  }
}
