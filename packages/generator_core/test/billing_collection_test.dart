import 'package:generator_core/generator_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('organisation & subscribers', () {
    test('creates generator with chart of accounts and main cash box', () async {
      final f = await setup();
      final accounts = await f.os.ctx.db.query('accounts', where: 'generator_id = ?', whereArgs: [f.generatorId]);
      expect(accounts.length, defaultChart.length);
      final boxes = await f.os.network.listCashboxes(f.generatorId);
      expect(boxes.single['id'], NetworkService.mainCashbox(f.generatorId));
      expect((await f.os.network.listAreas(f.generatorId)).single['name'], 'حي الاختبار');
      expect((await f.os.network.listCabinets(f.generatorId)).single['code'], 'K1');
    });

    test('adds subscriber with sequential account number and searchable fields', () async {
      final f = await setup();
      final a = await addSubscriber(f, name: 'علي حسين');
      final b = await addSubscriber(f, name: 'زينب كاظم');
      expect((await f.os.subscribers.get(a))['account_no'], '1');
      expect((await f.os.subscribers.get(b))['account_no'], '2');
      final res = await f.os.subscribers.search(f.generatorId, const SubscriberFilter(query: 'زينب'));
      expect(res.single['id'], b);
      final byCab = await f.os.subscribers.search(f.generatorId, const SubscriberFilter(query: 'K1'));
      expect(byCab.length, 2);
    });

    test('rejects invalid subscriber data with Arabic message', () async {
      final f = await setup();
      expect(
          () => f.os.subscribers.create(f.generatorId, {'full_name': 'ab', 'amps': 5, 'amp_price': 1000}),
          throwsA(isA<DomainException>().having((e) => e.message, 'message', contains('اسم'))));
      expect(() => f.os.subscribers.create(f.generatorId, {'full_name': 'اسم صحيح', 'amps': 0, 'amp_price': 1000}),
          throwsA(isA<DomainException>()));
    });

    test('transfer to another generator keeps the old financial record', () async {
      final f = await setup();
      final s = await addSubscriber(f, openingDebt: 7000);
      final g2 = await f.os.network.createGenerator(name: 'مولدة ثانية', defaultAmpPrice: 4000);
      final newSub = await f.os.subscribers.transferToGenerator(s, g2, reason: 'انتقل للسكن');
      final old = await f.os.subscribers.get(s);
      expect(old['status'], SubscriberStatus.transferred);
      expect(await f.os.subscribers.balance(s), 7000, reason: 'debt stays with generator 1');
      expect(await f.os.subscribers.balance(newSub), 0);
      expect((await f.os.subscribers.get(newSub))['amp_price'], 4000);
      final hist = await f.os.subscribers.history(s);
      expect(hist.any((e) => e['kind'] == 'transfer_out'), isTrue);
    });
  });

  group('billing', () {
    test('monthly generation computes amps × price and is idempotent', () async {
      final f = await setup();
      final s1 = await addSubscriber(f, amps: 5, price: 3000);
      await addSubscriber(f, amps: 10, price: 2500);
      final r1 = await f.os.billing.generateMonth(f.generatorId, '2026-03');
      expect(r1.created, 2);
      final r2 = await f.os.billing.generateMonth(f.generatorId, '2026-03');
      expect(r2.created, 0);
      expect(r2.skippedExisting, 2);
      final inv = await f.os.billing.getInvoice(BillingService.invoiceId(s1, '2026-03'));
      expect(inv['gross'], 15000);
      expect(await f.os.subscribers.balance(s1), 15000);
      await expectBalancedLedger(f.os);
    });

    test('second invoice for same subscriber and month is refused', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      await f.os.billing.issueInvoice(s, '2026-03');
      expect(() => f.os.billing.issueInvoice(s, '2026-03'),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'DUPLICATE_INVOICE')));
    });

    test('exempt subscribers get a fully discounted invoice', () async {
      final f = await setup();
      final s = await addSubscriber(f, type: SubscriptionType.exempt);
      await f.os.billing.generateMonth(f.generatorId, '2026-03');
      final inv = (await f.os.billing.subscriberInvoices(s)).single;
      expect(inv['net'], 0);
      expect(inv['status'], InvoiceStatus.paid);
      expect(await f.os.subscribers.balance(s), 0);
    });

    test('documented adjustment changes balance and keeps original figures', () async {
      final f = await setup();
      final s = await addSubscriber(f, amps: 5, price: 3000);
      final id = await f.os.billing.issueInvoice(s, '2026-03');
      await f.os.billing.adjustInvoice(id, newNet: 12000, reason: 'انقطاع 6 أيام');
      final inv = await f.os.billing.getInvoice(id);
      expect(inv['gross'], 15000);
      expect(inv['current_net'], 12000);
      expect(await f.os.subscribers.balance(s), 12000);
      expect(() => f.os.billing.adjustInvoice(id, newNet: 10000, reason: ''), throwsA(isA<DomainException>()));
      await expectBalancedLedger(f.os);
    });

    test('closed month refuses new invoices and adjustments', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      final id = await f.os.billing.issueInvoice(s, '2026-03');
      await f.os.billing.closePeriod(f.generatorId, '2026-03');
      expect(() => f.os.billing.adjustInvoice(id, newNet: 1, reason: 'سبب ما'),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'PERIOD_CLOSED')));
      expect(() => f.os.billing.generateMonth(f.generatorId, '2026-03'), throwsA(isA<DomainException>()));
    });
  });

  group('payments', () {
    test('full payment settles the invoice', () async {
      final f = await setup();
      final s = await addSubscriber(f, amps: 5, price: 3000);
      await f.os.billing.issueInvoice(s, '2026-03');
      await f.os.collection.recordPayment(subscriberId: s, amount: 15000);
      expect(await f.os.subscribers.balance(s), 0);
      expect((await f.os.billing.subscriberInvoices(s)).single['status'], InvoiceStatus.paid);
      expect(await f.os.finance.cashboxBalance(NetworkService.mainCashbox(f.generatorId)), 15000);
      await expectBalancedLedger(f.os);
    });

    test('partial payment leaves remaining balance; debt carries to next month', () async {
      final f = await setup();
      final s = await addSubscriber(f, amps: 5, price: 3000);
      await f.os.billing.issueInvoice(s, '2026-03');
      await f.os.collection.recordPayment(subscriberId: s, amount: 10000);
      var invs = await f.os.billing.subscriberInvoices(s);
      expect(invs.single['status'], InvoiceStatus.partial);
      expect(invs.single['unpaid'], 5000);

      f.clock.current = DateTime(2026, 4, 2, 9);
      await f.os.billing.issueInvoice(s, '2026-04');
      final st = await f.os.billing.statement(s, '2026-04');
      expect(st.previousBalance, 5000, reason: 'March remainder carried over');
      expect(st.invoiced, 15000);
      expect(st.closingBalance, 20000);
      expect(st.totalDebt, 20000);

      // Paying 7,000 settles the oldest (March) invoice first.
      await f.os.collection.recordPayment(subscriberId: s, amount: 7000);
      invs = await f.os.billing.subscriberInvoices(s);
      final march = invs.firstWhere((i) => i['period'] == '2026-03');
      final april = invs.firstWhere((i) => i['period'] == '2026-04');
      expect(march['status'], InvoiceStatus.paid);
      expect(april['unpaid'], 13000);
      await expectBalancedLedger(f.os);
    });

    test('same request id never creates a duplicate payment', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      final a = await f.os.collection.recordPayment(subscriberId: s, amount: 5000, requestId: 'req-1');
      final b = await f.os.collection.recordPayment(subscriberId: s, amount: 5000, requestId: 'req-1');
      expect(a['id'], b['id']);
      final count = await f.os.ctx.db.rawQuery('SELECT COUNT(*) c FROM payments');
      expect(count.first['c'], 1);
      expect(await f.os.subscribers.balance(s), -5000);
    });

    test('reversal uses a mirror entry and cannot be repeated', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      await f.os.billing.issueInvoice(s, '2026-03');
      final p = await f.os.collection.recordPayment(subscriberId: s, amount: 15000);
      await f.os.collection.reversePayment(p['id'] as String, reason: 'خطأ في المبلغ');
      expect(await f.os.subscribers.balance(s), 15000);
      expect(() => f.os.collection.reversePayment(p['id'] as String, reason: 'مرة ثانية'),
          throwsA(isA<DomainException>()));
      expect((await f.os.ctx.db.query('payments')).length, 2, reason: 'original kept + reversal record');
      await expectBalancedLedger(f.os);
    });

    test('financial records cannot be deleted or edited at database level', () async {
      final f = await setup();
      final s = await addSubscriber(f);
      final p = await f.os.collection.recordPayment(subscriberId: s, amount: 5000);
      expect(() => f.os.ctx.db.delete('payments', where: 'id = ?', whereArgs: [p['id']]), throwsA(anything));
      expect(() => f.os.ctx.db.update('payments', {'amount': 1}, where: 'id = ?', whereArgs: [p['id']]),
          throwsA(anything));
      expect(() => f.os.ctx.db.delete('journal_lines'), throwsA(anything));
      expect(() => f.os.ctx.db.delete('audit_logs'), throwsA(anything));
    });

    test('unbalanced journal entries are rejected', () async {
      final f = await setup();
      await expectLater(
          f.os.ctx.db.transaction((t) => f.os.ledger.post(t,
              entryId: 'je:x', generatorId: f.generatorId, date: '2026-03-15', description: 'x', sourceType: 'test',
              lines: const [JLine.dr(Acc.mainCash, 100), JLine.cr(Acc.capital, 90)])),
          throwsA(isA<DomainException>().having((e) => e.code, 'code', 'UNBALANCED')));
    });
  });
}
