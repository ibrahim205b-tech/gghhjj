import 'package:sqflite_common/sqlite_api.dart';

import '../security/permissions.dart';
import '../util/dates.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'ledger_service.dart';
import 'subscriber_service.dart';

class InvoiceStatus {
  static const unpaid = 'unpaid';
  static const partial = 'partial';
  static const paid = 'paid';
  static const labels = {unpaid: 'غير مسددة', partial: 'مسددة جزئياً', paid: 'مسددة'};
}

class GenerateResult {
  final int created;
  final int skippedExisting;
  final int total;
  const GenerateResult(this.created, this.skippedExisting, this.total);
}

/// Monthly statement for a subscriber.
class Statement {
  final String period;
  final int previousBalance;
  final int invoiced;
  final int discounts;
  final int adjustments;
  final int payments;
  final int closingBalance;
  final int totalDebt;
  final List<Map<String, Object?>> movements;
  const Statement({
    required this.period,
    required this.previousBalance,
    required this.invoiced,
    required this.discounts,
    required this.adjustments,
    required this.payments,
    required this.closingBalance,
    required this.totalDebt,
    required this.movements,
  });
}

class BillingService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final LedgerService ledger;
  BillingService(this.ctx, this.store, this.audit, this.ledger);

  static String invoiceId(String subscriberId, String period) => 'inv:$subscriberId:$period';

  Future<bool> isPeriodClosed(String generatorId, String period, [DatabaseExecutor? ex]) async {
    final r = await (ex ?? ctx.db).query('billing_periods',
        where: 'generator_id = ? AND period = ?', whereArgs: [generatorId, period]);
    return r.isNotEmpty && r.first['status'] == 'closed';
  }

  Future<void> _ensureOpen(DatabaseExecutor ex, String generatorId, String period) async {
    if (await isPeriodClosed(generatorId, period, ex)) {
      throw DomainException('PERIOD_CLOSED', 'شهر $period مغلق. لا يمكن إصدار أو تعديل فواتيره.');
    }
    final r = await ex.query('billing_periods', where: 'generator_id = ? AND period = ?', whereArgs: [generatorId, period]);
    if (r.isEmpty) {
      await store.insert(ex, 'billing_periods', {
        'id': 'bp:$generatorId:$period', 'generator_id': generatorId, 'period': period, 'status': 'open',
      });
    }
  }

  Future<void> _issue(DatabaseExecutor t, Map<String, Object?> s, String period,
      {int discount = 0, String? discountReason}) async {
    final subId = s['id'] as String;
    final gen = s['generator_id'] as String;
    final amps = s['amps'] as int;
    final price = s['amp_price'] as int;
    final gross = amps * price;
    var disc = discount;
    var reason = discountReason;
    if (s['subscription_type'] == SubscriptionType.exempt) {
      disc = gross;
      reason = 'إعفاء';
    }
    if (disc < 0 || disc > gross) throw validation('قيمة الخصم غير صحيحة.');
    final id = invoiceId(subId, period);
    final net = gross - disc;
    await store.insert(t, 'invoices', {
      'id': id,
      'generator_id': gen,
      'subscriber_id': subId,
      'period': period,
      'issue_date': ctx.today,
      'amps': amps,
      'amp_price': price,
      'gross': gross,
      'discount': disc,
      'discount_reason': reason,
      'net': net,
      'created_at': ctx.nowIso,
      'created_by': ctx.userId,
    });
    if (gross > 0) {
      await ledger.post(t,
          entryId: 'je:$id',
          generatorId: gen,
          date: ctx.today,
          description: 'فاتورة اشتراك $period — ${s['full_name']} ($amps أمبير × $price)',
          sourceType: 'invoice',
          sourceId: id,
          lines: [
            JLine.dr(Acc.receivables, gross, partyType: PartyType.subscriber, partyId: subId),
            JLine.cr(Acc.subscriptionRevenue, gross),
          ]);
    }
    if (disc > 0) {
      await ledger.post(t,
          entryId: 'je:$id:disc',
          generatorId: gen,
          date: ctx.today,
          description: '${reason ?? 'خصم'} على فاتورة $period — ${s['full_name']}',
          sourceType: 'invoice_discount',
          sourceId: id,
          lines: [
            JLine.dr(Acc.discounts, disc),
            JLine.cr(Acc.receivables, disc, partyType: PartyType.subscriber, partyId: subId),
          ]);
    }
  }

  /// Issues invoices for every active subscriber of the generator that does
  /// not yet have one for [period]. Safe to run repeatedly.
  Future<GenerateResult> generateMonth(String generatorId, String period) async {
    ctx.require(Perm.billingGenerate);
    ctx.requireGenerator(generatorId);
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) throw validation('صيغة الشهر يجب أن تكون YYYY-MM.');
    final (_, lastDay) = periodRange(period);
    var created = 0, skipped = 0;
    late int total;
    await ctx.db.transaction((t) async {
      await _ensureOpen(t, generatorId, period);
      final subs = await t.query('subscribers',
          where: "generator_id = ? AND status = 'active' AND start_date <= ?", whereArgs: [generatorId, lastDay]);
      total = subs.length;
      for (final s in subs) {
        final exists = await t.query('invoices', columns: ['id'], where: 'id = ?',
            whereArgs: [invoiceId(s['id'] as String, period)]);
        if (exists.isNotEmpty) {
          skipped++;
          continue;
        }
        await _issue(t, s, period);
        created++;
      }
      await audit.log(t, 'billing.generate', entity: 'billing_periods', entityId: period, generatorId: generatorId,
          details: {'created': created, 'skipped': skipped});
    });
    return GenerateResult(created, skipped, total);
  }

  /// Issues one invoice (e.g. for a new subscriber mid-month) with an optional
  /// discount.
  Future<String> issueInvoice(String subscriberId, String period, {int discount = 0, String? discountReason}) async {
    ctx.require(Perm.billingGenerate);
    if (discount > 0) ctx.require(Perm.billingAdjust);
    final s = await ctx.db.query('subscribers', where: 'id = ?', whereArgs: [subscriberId]);
    if (s.isEmpty) throw const DomainException('NOT_FOUND', 'المشترك غير موجود.');
    final gen = s.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    final id = invoiceId(subscriberId, period);
    await ctx.db.transaction((t) async {
      await _ensureOpen(t, gen, period);
      final exists = await t.query('invoices', columns: ['id'], where: 'id = ?', whereArgs: [id]);
      if (exists.isNotEmpty) {
        throw const DomainException('DUPLICATE_INVOICE',
            'توجد فاتورة لهذا المشترك عن هذا الشهر. استخدم "تعديل الفاتورة" مع ذكر السبب.');
      }
      await _issue(t, s.first, period, discount: discount, discountReason: discountReason);
      await audit.log(t, 'billing.issue', entity: 'invoices', entityId: id, generatorId: gen);
    });
    return id;
  }

  /// Documented change to an invoice. [newNet] recalculates to a new net
  /// amount; the difference is posted as an adjustment entry. Original
  /// figures remain untouched for audit.
  Future<String> adjustInvoice(String invoiceId, {required int newNet, required String reason}) async {
    ctx.require(Perm.billingAdjust);
    if (reason.trim().length < 3) throw validation('يجب ذكر سبب التعديل.');
    if (newNet < 0) throw validation('المبلغ الجديد لا يكون سالباً.');
    final inv = await getInvoice(invoiceId);
    final gen = inv['generator_id'] as String;
    final current = inv['current_net'] as int;
    final diff = newNet - current;
    if (diff == 0) throw validation('المبلغ الجديد يساوي المبلغ الحالي.');
    final adjId = newId();
    await ctx.db.transaction((t) async {
      await _ensureOpen(t, gen, inv['period'] as String);
      await store.insert(t, 'invoice_adjustments', {
        'id': adjId,
        'invoice_id': invoiceId,
        'generator_id': gen,
        'subscriber_id': inv['subscriber_id'],
        'kind': diff > 0 ? 'increase' : 'decrease',
        'amount': diff,
        'reason': reason.trim(),
        'created_at': ctx.nowIso,
        'created_by': ctx.userId,
      });
      final sub = inv['subscriber_id'] as String;
      await ledger.post(t,
          entryId: 'je:adj:$adjId',
          generatorId: gen,
          date: ctx.today,
          description: 'تعديل فاتورة ${inv['period']}: $reason',
          sourceType: 'invoice_adjustment',
          sourceId: adjId,
          lines: diff > 0
              ? [
                  JLine.dr(Acc.receivables, diff, partyType: PartyType.subscriber, partyId: sub),
                  JLine.cr(Acc.subscriptionRevenue, diff),
                ]
              : [
                  JLine.dr(Acc.discounts, -diff),
                  JLine.cr(Acc.receivables, -diff, partyType: PartyType.subscriber, partyId: sub),
                ]);
      await audit.log(t, 'billing.adjust', entity: 'invoices', entityId: invoiceId, generatorId: gen,
          details: {'from': current, 'to': newNet, 'reason': reason});
    });
    return adjId;
  }

  Future<void> closePeriod(String generatorId, String period) async {
    ctx.require(Perm.billingClosePeriod);
    ctx.requireGenerator(generatorId);
    await ctx.db.transaction((t) async {
      await _ensureOpen(t, generatorId, period);
      await store.update(t, 'billing_periods', 'bp:$generatorId:$period',
          {'status': 'closed', 'closed_at': ctx.nowIso, 'closed_by': ctx.userId});
      await audit.log(t, 'billing.close_period', entity: 'billing_periods', entityId: period, generatorId: generatorId);
    });
  }

  Future<void> reopenPeriod(String generatorId, String period, String reason) async {
    ctx.require(Perm.billingClosePeriod);
    if (ctx.session?.permissions.contains(Perm.backupManage) != true) {
      throw const PermissionDenied('billing.reopen (owner)');
    }
    await ctx.db.transaction((t) async {
      await store.update(t, 'billing_periods', 'bp:$generatorId:$period', {'status': 'open'});
      await audit.log(t, 'billing.reopen_period', entity: 'billing_periods', entityId: period,
          generatorId: generatorId, details: {'reason': reason});
    });
  }

  Future<List<Map<String, Object?>>> periods(String generatorId) =>
      ctx.db.query('billing_periods', where: 'generator_id = ?', whereArgs: [generatorId], orderBy: 'period DESC');

  Future<Map<String, Object?>> getInvoice(String id) async {
    final r = await ctx.db.rawQuery('''
      SELECT i.*, s.full_name, s.account_no, s.phone,
        i.net + COALESCE((SELECT SUM(amount) FROM invoice_adjustments a WHERE a.invoice_id = i.id), 0) AS current_net
      FROM invoices i JOIN subscribers s ON s.id = i.subscriber_id WHERE i.id = ?''', [id]);
    if (r.isEmpty) throw const DomainException('NOT_FOUND', 'الفاتورة غير موجودة.');
    ctx.requireGenerator(r.first['generator_id'] as String);
    return r.first;
  }

  /// Invoices of a subscriber with derived paid/unpaid status. The ledger
  /// balance is attributed to the newest invoices first (equivalent to paying
  /// the oldest invoices first), so status is always consistent with the
  /// accounting records and never depends on a mutable "paid" column.
  Future<List<Map<String, Object?>>> subscriberInvoices(String subscriberId) async {
    final rows = await ctx.db.rawQuery('''
      SELECT i.*, i.net + COALESCE((SELECT SUM(amount) FROM invoice_adjustments a WHERE a.invoice_id = i.id), 0)
        AS current_net FROM invoices i WHERE i.subscriber_id = ? ORDER BY i.period DESC''', [subscriberId]);
    if (rows.isEmpty) return [];
    final gen = rows.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    var remaining = await ledger.balance(gen, Acc.receivables, partyType: PartyType.subscriber, partyId: subscriberId);
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final net = r['current_net'] as int;
      final unpaid = remaining <= 0 ? 0 : (remaining >= net ? net : remaining);
      remaining -= unpaid;
      out.add({
        ...r,
        'unpaid': unpaid,
        'paid': net - unpaid,
        'status': net == 0 || unpaid == 0
            ? InvoiceStatus.paid
            : (unpaid == net ? InvoiceStatus.unpaid : InvoiceStatus.partial),
      });
    }
    return out;
  }

  Future<List<Map<String, Object?>>> periodInvoices(String generatorId, String period) async {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''
      SELECT i.*, s.full_name, s.account_no,
        i.net + COALESCE((SELECT SUM(amount) FROM invoice_adjustments a WHERE a.invoice_id = i.id), 0) AS current_net
      FROM invoices i JOIN subscribers s ON s.id = i.subscriber_id
      WHERE i.generator_id = ? AND i.period = ? ORDER BY CAST(s.account_no AS INTEGER)''', [generatorId, period]);
  }

  Future<Statement> statement(String subscriberId, String period) async {
    final s = await ctx.db.query('subscribers', where: 'id = ?', whereArgs: [subscriberId]);
    if (s.isEmpty) throw const DomainException('NOT_FOUND', 'المشترك غير موجود.');
    final gen = s.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    final (first, last) = periodRange(period);
    final prevDay = ymd(parseYmd(first).subtract(const Duration(days: 1)));
    final ar = LedgerService.accountId(gen, Acc.receivables);
    final previous = await ledger.balance(gen, Acc.receivables,
        partyType: PartyType.subscriber, partyId: subscriberId, to: prevDay);
    final moves = await ctx.db.rawQuery('''
      SELECT l.entry_date, l.debit, l.credit, e.description, e.source_type, e.source_id
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? AND l.party_type = 'subscriber' AND l.party_id = ?
        AND l.entry_date >= ? AND l.entry_date <= ? ORDER BY l.entry_date, e.created_at''',
        [ar, subscriberId, first, last]);
    var invoiced = 0, discounts = 0, adjustments = 0, payments = 0;
    for (final m in moves) {
      final dr = m['debit'] as int, cr = m['credit'] as int;
      switch (m['source_type']) {
        case 'invoice':
          invoiced += dr - cr;
        case 'invoice_discount':
          discounts += cr - dr;
        case 'invoice_adjustment':
        case 'opening_balance':
          adjustments += dr - cr;
        case 'payment':
          payments += cr - dr;
        case 'reversal':
          // A reversed payment increases the debt again; reversed invoices reduce it.
          adjustments += dr - cr;
        default:
          adjustments += dr - cr;
      }
    }
    final closing = previous + invoiced - discounts + adjustments - payments;
    final total = await ledger.balance(gen, Acc.receivables, partyType: PartyType.subscriber, partyId: subscriberId);
    return Statement(
      period: period,
      previousBalance: previous,
      invoiced: invoiced,
      discounts: discounts,
      adjustments: adjustments,
      payments: payments,
      closingBalance: closing,
      totalDebt: total,
      movements: moves,
    );
  }
}
