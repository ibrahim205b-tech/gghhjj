import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:generator_core/generator_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('collectors & cash box', () {
    test('collector custody, handover and reconciliation', () async {
      final f = await setup();
      final s1 = await addSubscriber(f, name: 'مشترك أول');
      final s2 = await addSubscriber(f, name: 'مشترك ثاني');
      final col = await f.os.collection.createCollector(fullName: 'جابي الاختبار', commissionPercent: 5);
      await f.os.collection.recordPayment(subscriberId: s1, amount: 15000, collectorId: col);
      await f.os.collection.recordPayment(subscriberId: s2, amount: 10000, collectorId: col);
      expect(await f.os.collection.custodyBalance(f.generatorId, col), 25000);

      await f.os.collection.handover(generatorId: f.generatorId, collectorId: col, amount: 20000);
      expect(await f.os.collection.custodyBalance(f.generatorId, col), 5000);
      expect(() => f.os.collection.handover(generatorId: f.generatorId, collectorId: col, amount: 6000),
          throwsA(isA<DomainException>()), reason: 'cannot hand over more than custody');

      final perf = (await f.os.collection.collectorPerformance(f.generatorId, DateRange.month(f.clock.current))).single;
      expect(perf['collected'], 25000);
      expect(perf['handed_over'], 20000);
      expect(perf['custody'], 5000);
      expect(perf['commission'], 1250);
      await expectBalancedLedger(f.os);
    });

    test('daily close: expected = opening + receipts − disbursements, difference posted', () async {
      final f = await setup();
      final box = NetworkService.mainCashbox(f.generatorId);
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.capitalIn, amount: 100000,
          date: '2026-03-14');
      final s = await addSubscriber(f);
      await f.os.collection.recordPayment(subscriberId: s, amount: 30000);
      await f.os.finance.recordExpense(generatorId: f.generatorId, category: ExpenseCategory.transport, amount: 8000);
      final rec = await f.os.finance.reconcile(box, '2026-03-15');
      expect(rec.opening, 100000);
      expect(rec.receipts, 30000);
      expect(rec.disbursements, 8000);
      expect(rec.expected, 122000);

      expect(() => f.os.finance.closeDay(box, counted: 121000), throwsA(isA<DomainException>()),
          reason: 'a difference requires an explanation');
      final c = await f.os.finance.closeDay(box, counted: 121000, notes: 'نقص ورقة ألف');
      expect(c['difference'], -1000);
      expect(await f.os.finance.cashboxBalance(box), 121000, reason: 'book now equals counted cash');
      final pnl = await f.os.reports.pnl(f.generatorId, DateRange.month(f.clock.current));
      expect(pnl.expenses, 9000, reason: 'transport 8000 + cash short 1000');
      expect(() => f.os.finance.closeDay(box, counted: 121000), throwsA(isA<DomainException>()));
      final alerts = await f.os.alerts.list(f.generatorId);
      expect(alerts.any((a) => a['kind'] == 'cash_difference'), isTrue);
      await expectBalancedLedger(f.os);
    });

    test('cash out operations cannot exceed the cash box balance', () async {
      final f = await setup();
      expect(
          () => f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.ownerWithdrawal, amount: 1000),
          throwsA(isA<DomainException>()));
    });

    test('expense on credit goes to supplier payable; supplier payment settles it', () async {
      final f = await setup();
      final sup = await f.os.finance.createSupplier(f.generatorId, 'محل قطع الغيار', kind: 'parts');
      await f.os.finance.recordExpense(generatorId: f.generatorId, category: ExpenseCategory.maintenance,
          amount: 50000, payMethod: PayMethod.credit, supplierId: sup);
      expect((await f.os.finance.listSuppliers(f.generatorId)).single['owed'], 50000);
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.capitalIn, amount: 50000);
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.supplierPayment, amount: 30000,
          supplierId: sup);
      expect((await f.os.finance.listSuppliers(f.generatorId)).single['owed'], 20000);
    });

    test('expense reversal keeps the original and nets to zero', () async {
      final f = await setup();
      final id = await f.os.finance.recordExpense(
          generatorId: f.generatorId, category: ExpenseCategory.rent, amount: 9000, payMethod: PayMethod.credit,
          supplierId: await f.os.finance.createSupplier(f.generatorId, 'المؤجر'));
      await f.os.finance.reverseEntry('je:exp:$id', reason: 'تسجيل مكرر');
      final pnl = await f.os.reports.pnl(f.generatorId, DateRange.month(f.clock.current));
      expect(pnl.expenses, 0);
      final list = await f.os.finance.listExpenses(f.generatorId, DateRange.month(f.clock.current));
      expect(list.single['reversed'], 1);
    });
  });

  group('fuel', () {
    test('purchase, weighted-average consumption cost and stock', () async {
      final f = await setup();
      final sup = await f.os.finance.createSupplier(f.generatorId, 'محطة الكاز');
      await f.os.fuel.purchase(generatorId: f.generatorId, quantityMl: litersToMl(1000), pricePerLiter: 800,
          supplierId: sup, payMethod: PayMethod.credit);
      await f.os.fuel.purchase(generatorId: f.generatorId, quantityMl: litersToMl(1000), pricePerLiter: 1000,
          supplierId: sup, payMethod: PayMethod.credit);
      var st = await f.os.fuel.stock(f.generatorId);
      expect(st.bookMl, 2000000);
      expect(st.value, 1800000);
      expect(st.avgCostPerLiter, 900);

      await f.os.fuel.consume(generatorId: f.generatorId, quantityMl: litersToMl(500), runHours: 10);
      st = await f.os.fuel.stock(f.generatorId);
      expect(st.bookMl, 1500000);
      expect(st.value, 1350000, reason: '500 L × 900 = 450,000 expensed');
      final stats = await f.os.fuel.stats(f.generatorId, DateRange.day(f.clock.current), runHoursOverride: 10);
      expect(stats.consumedMl, 500000);
      expect(stats.cost, 450000);
      expect(stats.litersPerHour, 50);
      expect(stats.costPerHour, 45000);
      expect((await f.os.finance.listSuppliers(f.generatorId)).single['owed'], 1800000);

      expect(() => f.os.fuel.consume(generatorId: f.generatorId, quantityMl: litersToMl(2000)),
          throwsA(isA<DomainException>()), reason: 'cannot consume more than book stock');
      await expectBalancedLedger(f.os);
    });

    test('consuming the full stock leaves no rounding residue', () async {
      final f = await setup();
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.capitalIn, amount: 1000000);
      await f.os.fuel.purchase(generatorId: f.generatorId, quantityMl: 333000, pricePerLiter: 997);
      await f.os.fuel.consume(generatorId: f.generatorId, quantityMl: 111000);
      await f.os.fuel.consume(generatorId: f.generatorId, quantityMl: 222000);
      final st = await f.os.fuel.stock(f.generatorId);
      expect(st.bookMl, 0);
      expect(st.value, 0);
    });

    test('flags abnormal consumption days', () async {
      final f = await setup();
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.capitalIn, amount: 50000000);
      await f.os.fuel.purchase(generatorId: f.generatorId, quantityMl: litersToMl(10000), pricePerLiter: 900,
          date: '2026-03-01');
      for (var d = 1; d <= 10; d++) {
        await f.os.fuel.consume(generatorId: f.generatorId, quantityMl: litersToMl(d == 7 ? 600 : 200),
            date: '2026-03-${d.toString().padLeft(2, '0')}', runHours: 10);
      }
      final st = await f.os.fuel.stats(f.generatorId, const DateRange('2026-03-01', '2026-03-10'));
      expect(st.anomalies.map((a) => a['day']), contains('2026-03-07'));
      expect(st.forecastNext7DaysMl, (st.avgDailyMl * 7).round());
    });
  });

  group('operations', () {
    test('run log hours, maintenance due and fault cost', () async {
      final f = await setup();
      await f.os.operations.logRun(f.generatorId, DateTime(2026, 3, 15, 0), DateTime(2026, 3, 15, 8));
      await f.os.operations.startRun(f.generatorId);
      f.clock.advance(const Duration(hours: 2));
      await f.os.operations.stopRun(f.generatorId, reason: 'عودة الوطنية');
      expect(await f.os.operations.runHours(f.generatorId, DateRange.day(f.clock.current)), 10);

      await f.os.operations.createPlan(f.generatorId, 'oil', intervalDays: 10, lastDoneDate: '2026-03-07');
      final due = await f.os.operations.upcomingMaintenance(f.generatorId, withinDays: 3);
      expect(due.single['kind'], 'oil');
      expect(due.single['days_left'], 2);

      final fault = await f.os.operations.reportFault(
          generatorId: f.generatorId, title: 'تسريب زيت', severity: FaultSeverity.high);
      expect((await f.os.operations.faults(f.generatorId, openOnly: true)).length, 1);
      final sup = await f.os.finance.createSupplier(f.generatorId, 'فني');
      await f.os.operations.resolveFault(fault, repairCost: 25000, payMethod: PayMethod.credit, supplierId: sup);
      expect((await f.os.operations.faults(f.generatorId, openOnly: true)), isEmpty);
      final pnl = await f.os.reports.pnl(f.generatorId, DateRange.month(f.clock.current));
      expect(pnl.expenses, 25000);
    });

    test('contracted cabinet load and overload alert (theoretical, labelled)', () async {
      final f = await setup();
      for (var i = 0; i < 3; i++) {
        await addSubscriber(f, name: 'مشترك رقم $i', amps: 40);
      }
      final load = (await f.os.network.cabinetLoads(f.generatorId)).single;
      expect(load['contracted_amps'], 120);
      await f.os.alerts.runChecks(f.generatorId);
      final alerts = await f.os.alerts.list(f.generatorId);
      final ov = alerts.firstWhere((a) => a['kind'] == AlertKind.overload);
      expect(ov['body'], contains('نظري'));
    });
  });

  group('security', () {
    test('collector sees only assigned subscribers and cannot touch sensitive data', () async {
      final f = await setup();
      final area2 = await f.os.network.createArea(f.generatorId, 'منطقة أخرى');
      final mine = await addSubscriber(f, name: 'ضمن منطقتي');
      final other = await f.os.subscribers.create(
          f.generatorId, {'full_name': 'خارج منطقتي', 'amps': 5, 'amp_price': 3000, 'area_id': area2});
      await f.os.billing.generateMonth(f.generatorId, '2026-03');
      final uid = await f.os.auth.createUser(
          fullName: 'جابي', username: 'collector1', password: 'Collect123', roleId: roleCollector,
          generatorIds: [f.generatorId]);
      final colId = await f.os.collection.createCollector(fullName: 'جابي المنطقة', userId: uid);
      await f.os.collection.assign(colId, f.generatorId, areaId: f.areaId);
      final p = await f.os.collection.recordPayment(subscriberId: mine, amount: 1000);
      await f.os.auth.logout();

      await f.os.auth.login('collector1', 'Collect123');
      final visible = await f.os.subscribers.search(f.generatorId, const SubscriberFilter());
      expect(visible.map((s) => s['id']), [mine]);
      final pay = await f.os.collection.recordPayment(subscriberId: mine, amount: 5000, collectorId: 'someone-else');
      expect(pay['collector_id'], colId, reason: 'forced into his own custody');
      expect(() => f.os.collection.recordPayment(subscriberId: other, amount: 5000),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'NOT_ASSIGNED')));
      expect(() => f.os.reports.pnl(f.generatorId, DateRange.month(f.clock.current)), throwsA(isA<PermissionDenied>()));
      expect(() => f.os.subscribers.update(mine, {'amp_price': 1}), throwsA(isA<PermissionDenied>()));
      expect(() => f.os.collection.reversePayment(p['id'] as String, reason: 'حذف'), throwsA(isA<PermissionDenied>()));
      expect(() => f.os.billing.generateMonth(f.generatorId, '2026-04'), throwsA(isA<PermissionDenied>()));
      expect(() => f.os.finance.cashboxBalance(NetworkService.mainCashbox(f.generatorId)),
          throwsA(isA<PermissionDenied>()));
      final perf = await f.os.collection.collectorPerformance(f.generatorId, DateRange.month(f.clock.current));
      expect(perf.map((c) => c['id']), [colId], reason: 'sees only his own account');
      final answer = await f.os.assistant.ask(f.generatorId, 'شكد ربحي هذا الشهر');
      expect(answer.intent, 'denied');
    });

    test('owner has every permission and can customise roles', () async {
      final f = await setup();
      for (final p in Perm.all) {
        expect(f.os.ctx.can(p), isTrue, reason: p);
      }
      await f.os.auth.setRolePermission(roleCollector, Perm.complaintsManage, true);
      expect(await f.os.auth.permissionsOf(roleCollector), contains(Perm.complaintsManage));
      expect(() => f.os.auth.setRolePermission(roleOwner, Perm.aiUse, false), throwsA(isA<DomainException>()));
    });

    test('passwords are hashed; lockout after repeated failures', () async {
      final f = await setup();
      final u = (await f.os.ctx.db.query('users')).single;
      expect(u['password_hash'], isNot(contains(testPassword)));
      expect(u['password_hash'] as String, startsWith('pbkdf2-sha256'));
      await f.os.auth.logout();
      for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
        await expectLater(f.os.auth.login('owner', 'wrong-pass1'), throwsA(isA<DomainException>()));
      }
      await expectLater(f.os.auth.login('owner', testPassword),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'LOCKED')));
      f.clock.advance(const Duration(minutes: 11));
      await f.os.auth.login('owner', testPassword);
      final notes = await f.os.ctx.db.query('notifications', where: "kind = 'security'");
      expect(notes, isNotEmpty);
    });

    test('revoked session is detected; audit log records operations', () async {
      final f = await setup();
      expect(await f.os.auth.sessionValid(), isTrue);
      await f.os.auth.revokeSession(f.os.ctx.session!.sessionId);
      expect(await f.os.auth.sessionValid(), isFalse);
      final logs = await f.os.audit.list();
      expect(logs.map((l) => l['action']), containsAll(['system.setup', 'generators.create', 'sessions.revoke']));
      expect(logs.every((l) => l['device_id'] == 'device-test-a'), isTrue);
    });

    test('licence limit blocks extra generators but never locks data', () async {
      final f = await setup(maxGenerators: 1);
      expect(() => f.os.network.createGenerator(name: 'ثانية'),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'LICENSE_LIMIT')));
      await addSubscriber(f); // local functions keep working
    });

    test('Ed25519 perpetual licence verification', () async {
      final kp = await Ed25519().newKeyPair();
      final pub = (await kp.extractPublicKey()).bytes;
      final db = await openTestDb();
      final os = await newOs(db, FixedClock(DateTime(2026, 3, 1)), pubKey: pub);
      final payload = utf8.encode(jsonEncode({
        'license_id': 'L-1', 'customer': 'عميل تجريبي', 'max_generators': 3, 'device_ids': ['device-test-a'],
        'issued_at': '2026-03-01', 'services': {'cloud_sync': '2027-03-01'},
      }));
      final sig = await Ed25519().sign(payload, keyPair: kp);
      final key = '${base64Url.encode(payload)}.${base64Url.encode(sig.bytes)}';
      final lic = await os.license.activate(key);
      expect(lic.maxGenerators, 3);
      expect(await os.license.maxGenerators(), 3);
      expect(lic.serviceActive('cloud_sync', '2026-06-01'), isTrue);
      final tampered = '${base64Url.encode(utf8.encode(utf8.decode(payload).replaceFirst('3', '9')))}.'
          '${base64Url.encode(sig.bytes)}';
      expect(() => os.license.verify(tampered), throwsA(isA<DomainException>()));
      final other = await newOs(db, FixedClock(DateTime(2026, 3, 1)), deviceId: 'device-other', pubKey: pub);
      expect(() => other.license.verify(key),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'LICENSE_DEVICE')));
    });
  });

  group('backup', () {
    test('encrypted backup restores into a fresh database with identical balances', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      await f.os.billing.issueInvoice(s, '2026-03');
      await f.os.collection.recordPayment(subscriberId: s, amount: 4000);
      final bytes = await f.os.backup.createBackup('backup-pass-1');
      expect(utf8.decode(bytes), isNot(contains('مشترك تجريبي')), reason: 'content is encrypted');

      await expectLater(BackupService.decrypt(bytes, 'wrong-password'),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'BAD_PASSWORD')));
      final snap = await BackupService.decrypt(bytes, 'backup-pass-1');
      final fresh = await openTestDb();
      final counts = await BackupService.restoreInto(fresh, snap);
      expect(counts['subscribers'], 1);
      final os2 = await newOs(fresh, f.clock);
      await os2.auth.login('owner', testPassword);
      expect(await os2.subscribers.balance(s), 11000);
      await expectBalancedLedger(os2);
      await expectLater(BackupService.restoreInto(fresh, snap), throwsA(isA<DomainException>()),
          reason: 'restore only into an empty database');
    });
  });

  group('reports & assistant', () {
    test('dashboard, P&L, series, CSV and Arabic/Iraqi questions use real data', () async {
      final f = await setup();
      final s1 = await addSubscriber(f, name: 'حسن علي', amps: 10, price: 3000);
      await addSubscriber(f, name: 'كريم جاسم', amps: 5, price: 3000);
      await f.os.billing.generateMonth(f.generatorId, '2026-03');
      final col = await f.os.collection.createCollector(fullName: 'أبو محمد');
      await f.os.collection.recordPayment(subscriberId: s1, amount: 30000, collectorId: col);
      await f.os.finance.cashOperation(generatorId: f.generatorId, kind: CashOp.capitalIn, amount: 2000000);
      await f.os.fuel.purchase(generatorId: f.generatorId, quantityMl: litersToMl(1000), pricePerLiter: 1000);
      await f.os.fuel.consume(generatorId: f.generatorId, quantityMl: litersToMl(20));

      final d = await f.os.reports.dashboard(f.generatorId);
      expect(d.collectionsToday, 30000);
      expect(d.month.revenue, 45000);
      expect(d.month.expenses, 20000);
      expect(d.month.profit, 25000);
      expect(d.totalDebt, 15000);
      expect(d.subscriberCounts['active'], 2);
      expect(d.subscriberCounts['debtors'], 1);
      expect(d.subscriberCounts['amps'], 15);
      expect(d.fuelBookMl, 980000);

      final series = await f.os.reports.series(f.generatorId, Granularity.month, count: 3);
      expect(series.last.revenue, 45000);
      expect(series.first.revenue, 0);

      final csv = toCsv(['الاسم', 'المبلغ'], [
        ['حسن, علي', 30000]
      ]);
      expect(csv, startsWith('﻿'));
      expect(csv, contains('"حسن, علي",30000'));

      var a = await f.os.assistant.ask(f.generatorId, 'شكد ربحي هذا الشهر؟');
      expect(a.intent, 'profit');
      expect(a.text, contains('25,000'));
      a = await f.os.assistant.ask(f.generatorId, 'شكد ديون المشتركين');
      expect(a.intent, 'debts');
      expect(a.text, contains('15,000'));
      expect(a.text, contains('كريم جاسم'));
      a = await f.os.assistant.ask(f.generatorId, 'منو أكثر جابي حصّل؟');
      expect(a.intent, 'top_collector');
      expect(a.text, contains('أبو محمد'));
      a = await f.os.assistant.ask(f.generatorId, 'شكد صرفنا گاز');
      expect(a.intent, 'fuel_spent');
      expect(a.text, contains('20 لتر'));
      a = await f.os.assistant.ask(f.generatorId, 'شنو أكثر منطقة بيها ديون');
      expect(a.intent, 'debt_area');
      expect(a.text, contains('حي الاختبار'));
      a = await f.os.assistant.ask(f.generatorId, 'قارنلي أرباح هذا الشهر بالشهر السابق');
      expect(a.intent, 'compare');
      a = await f.os.assistant.ask(f.generatorId, 'شكد أحتاج كاز للأسبوع القادم');
      expect(a.intent, 'fuel_need');
      a = await f.os.assistant.ask(f.generatorId, 'شنو المصاريف اللي زادت');
      expect(a.intent, 'expense_increase');
      expect(a.text, contains('الوقود'));
      a = await f.os.assistant.ask(f.generatorId, 'مرحبا');
      expect(a.intent, 'help');
    });
  });
}
