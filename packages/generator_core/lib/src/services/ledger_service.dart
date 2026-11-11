import 'package:sqflite_common/sqlite_api.dart';

import '../util/errors.dart';
import 'context.dart';

/// Account types of the chart of accounts.
class AccountType {
  static const asset = 'asset';
  static const liability = 'liability';
  static const equity = 'equity';
  static const revenue = 'revenue';
  static const expense = 'expense';
}

/// Fixed account codes used by the posting rules.
class Acc {
  static const mainCash = '1101';
  static const collectorCustody = '1150';
  static const receivables = '1200';
  static const fuelInventory = '1300';
  static const employeeAdvances = '1400';
  static const payables = '2100';
  static const salariesPayable = '2200';
  static const capital = '3100';
  static const ownerDrawings = '3200';
  static const openingBalances = '3300';
  static const subscriptionRevenue = '4100';
  static const discounts = '4150';
  static const otherRevenue = '4200';
  static const cashOver = '4900';
  static const fuelExpense = '5100';
  static const maintenance = '5200';
  static const salaries = '5300';
  static const commissions = '5310';
  static const oilFilters = '5400';
  static const rent = '5500';
  static const transport = '5600';
  static const otherExpense = '5800';
  static const cashShort = '5900';
}

/// Chart of accounts tailored to private generator businesses.
const defaultChart = <(String, String, String)>[
  (Acc.mainCash, 'الصندوق الرئيسي', AccountType.asset),
  (Acc.collectorCustody, 'عهدة الجباة', AccountType.asset),
  (Acc.receivables, 'ذمم المشتركين', AccountType.asset),
  (Acc.fuelInventory, 'مخزون الوقود (الكاز)', AccountType.asset),
  (Acc.employeeAdvances, 'سلف الموظفين', AccountType.asset),
  (Acc.payables, 'ذمم المجهزين', AccountType.liability),
  (Acc.salariesPayable, 'رواتب ومستحقات الموظفين', AccountType.liability),
  (Acc.capital, 'رأس المال', AccountType.equity),
  (Acc.ownerDrawings, 'مسحوبات المالك', AccountType.equity),
  (Acc.openingBalances, 'الأرصدة الافتتاحية', AccountType.equity),
  (Acc.subscriptionRevenue, 'إيرادات الاشتراكات', AccountType.revenue),
  (Acc.discounts, 'خصومات وإعفاءات ممنوحة', AccountType.revenue),
  (Acc.otherRevenue, 'إيرادات أخرى', AccountType.revenue),
  (Acc.cashOver, 'فائض الصندوق', AccountType.revenue),
  (Acc.fuelExpense, 'كلفة الوقود المستهلك', AccountType.expense),
  (Acc.maintenance, 'الصيانة وقطع الغيار', AccountType.expense),
  (Acc.salaries, 'الرواتب والأجور', AccountType.expense),
  (Acc.commissions, 'عمولات الجباة', AccountType.expense),
  (Acc.oilFilters, 'الزيوت والفلاتر', AccountType.expense),
  (Acc.rent, 'الإيجارات', AccountType.expense),
  (Acc.transport, 'النقل', AccountType.expense),
  (Acc.otherExpense, 'مصاريف أخرى', AccountType.expense),
  (Acc.cashShort, 'عجز الصندوق', AccountType.expense),
];

class PartyType {
  static const subscriber = 'subscriber';
  static const collector = 'collector';
  static const supplier = 'supplier';
  static const employee = 'employee';
}

/// One line of a journal entry. Provide either [debit] or [credit].
class JLine {
  final String accountCode;
  final int debit;
  final int credit;
  final String? partyType;
  final String? partyId;
  final String? memo;
  const JLine.dr(this.accountCode, this.debit, {this.partyType, this.partyId, this.memo}) : credit = 0;
  const JLine.cr(this.accountCode, this.credit, {this.partyType, this.partyId, this.memo}) : debit = 0;
}

/// Double-entry general ledger. Entries are immutable; corrections are made
/// with [reverse], which posts a mirror entry linked to the original.
class LedgerService {
  final CoreContext ctx;
  final Store store;
  LedgerService(this.ctx, this.store);

  static String accountId(String generatorId, String code) => 'acc:$generatorId:$code';

  Future<void> createChart(DatabaseExecutor ex, String generatorId) async {
    for (final (code, name, type) in defaultChart) {
      final id = accountId(generatorId, code);
      final exists = await ex.query('accounts', columns: ['id'], where: 'id = ?', whereArgs: [id]);
      if (exists.isNotEmpty) continue;
      await store.insert(ex, 'accounts', {
        'id': id,
        'generator_id': generatorId,
        'code': code,
        'name': name,
        'type': type,
        'created_at': ctx.nowIso,
      });
    }
  }

  Future<void> ensureAccount(DatabaseExecutor ex, String generatorId, String code, String name, String type) async {
    final id = accountId(generatorId, code);
    final exists = await ex.query('accounts', columns: ['id'], where: 'id = ?', whereArgs: [id]);
    if (exists.isNotEmpty) return;
    await store.insert(ex, 'accounts', {
      'id': id, 'generator_id': generatorId, 'code': code, 'name': name, 'type': type,
      'created_at': ctx.nowIso,
    });
  }

  /// Posts a balanced entry. [entryId] should be deterministic from the
  /// source document (e.g. `je:pay:<paymentId>`) so the same business event
  /// can never be posted twice.
  Future<String> post(
    DatabaseExecutor ex, {
    required String entryId,
    required String generatorId,
    required String date,
    required String description,
    required String sourceType,
    String? sourceId,
    String? reversesId,
    required List<JLine> lines,
  }) async {
    if (lines.length < 2) throw validation('القيد يجب أن يحتوي سطرين على الأقل.');
    var dr = 0, cr = 0;
    for (final l in lines) {
      if (l.debit < 0 || l.credit < 0) throw validation('لا يسمح بمبالغ سالبة في القيد.');
      if (l.debit > 0 && l.credit > 0) throw validation('السطر لا يكون مديناً ودائناً معاً.');
      dr += l.debit;
      cr += l.credit;
    }
    if (dr != cr) throw DomainException('UNBALANCED', 'القيد غير متوازن: مدين $dr ≠ دائن $cr');
    if (dr == 0) throw validation('لا يمكن تسجيل قيد بقيمة صفر.');

    final existing = await ex.query('journal_entries', columns: ['id'], where: 'id = ?', whereArgs: [entryId]);
    if (existing.isNotEmpty) {
      throw const DomainException('DUPLICATE_ENTRY', 'هذه العملية مسجلة مسبقاً.');
    }

    await store.insert(ex, 'journal_entries', {
      'id': entryId,
      'generator_id': generatorId,
      'entry_date': date,
      'description': description,
      'source_type': sourceType,
      'source_id': sourceId,
      'reverses_id': reversesId,
      'created_at': ctx.nowIso,
      'created_by': ctx.userId,
      'device_id': ctx.deviceId,
    });
    var i = 0;
    for (final l in lines) {
      i++;
      final accId = accountId(generatorId, l.accountCode);
      final acc = await ex.query('accounts', columns: ['id'], where: 'id = ?', whereArgs: [accId]);
      if (acc.isEmpty) throw DomainException('NO_ACCOUNT', 'الحساب ${l.accountCode} غير موجود.');
      await store.insert(ex, 'journal_lines', {
        'id': '$entryId:$i',
        'entry_id': entryId,
        'generator_id': generatorId,
        'account_id': accId,
        'debit': l.debit,
        'credit': l.credit,
        'party_type': l.partyType,
        'party_id': l.partyId,
        'entry_date': date,
        'memo': l.memo,
      });
    }
    return entryId;
  }

  /// Posts the mirror of [entryId]. Only one reversal per entry is possible.
  Future<String> reverse(DatabaseExecutor ex, String entryId, {required String reason, String? date}) async {
    final e = await ex.query('journal_entries', where: 'id = ?', whereArgs: [entryId]);
    if (e.isEmpty) throw const DomainException('NOT_FOUND', 'القيد غير موجود.');
    final already = await ex.query('journal_entries', columns: ['id'], where: 'reverses_id = ?', whereArgs: [entryId]);
    if (already.isNotEmpty) throw const DomainException('ALREADY_REVERSED', 'تم عكس هذا القيد مسبقاً.');
    final lines = await ex.rawQuery(
      '''SELECT l.*, a.code FROM journal_lines l JOIN accounts a ON a.id = l.account_id
         WHERE l.entry_id = ? ORDER BY l.id''', [entryId]);
    final entry = e.first;
    return post(
      ex,
      entryId: 'je:rev:$entryId',
      generatorId: entry['generator_id'] as String,
      date: date ?? ctx.today,
      description: 'عكس قيد: ${entry['description']} — $reason',
      sourceType: 'reversal',
      sourceId: entryId,
      reversesId: entryId,
      lines: [
        for (final l in lines)
          (l['debit'] as int) > 0
              ? JLine.cr(l['code'] as String, l['debit'] as int,
                  partyType: l['party_type'] as String?, partyId: l['party_id'] as String?)
              : JLine.dr(l['code'] as String, l['credit'] as int,
                  partyType: l['party_type'] as String?, partyId: l['party_id'] as String?),
      ],
    );
  }

  /// Debit-minus-credit balance of an account (optionally per party / dates).
  Future<int> balance(String generatorId, String code,
      {String? partyType, String? partyId, String? from, String? to, DatabaseExecutor? ex}) async {
    final where = <String>['account_id = ?'];
    final args = <Object?>[accountId(generatorId, code)];
    if (partyType != null) {
      where.add('party_type = ?');
      args.add(partyType);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    if (from != null) {
      where.add('entry_date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('entry_date <= ?');
      args.add(to);
    }
    final r = await (ex ?? ctx.db).rawQuery(
        'SELECT COALESCE(SUM(debit - credit), 0) AS b FROM journal_lines WHERE ${where.join(' AND ')}', args);
    return (r.first['b'] as int?) ?? 0;
  }

  /// Sum (debit - credit) over all accounts of [type] in a date range.
  Future<int> typeBalance(String? generatorId, String type, {String? from, String? to}) async {
    final where = <String>['a.type = ?'];
    final args = <Object?>[type];
    if (generatorId != null) {
      where.add('l.generator_id = ?');
      args.add(generatorId);
    }
    if (from != null) {
      where.add('l.entry_date >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('l.entry_date <= ?');
      args.add(to);
    }
    final r = await ctx.db.rawQuery(
        '''SELECT COALESCE(SUM(l.debit - l.credit), 0) AS b FROM journal_lines l
           JOIN accounts a ON a.id = l.account_id WHERE ${where.join(' AND ')}''', args);
    return (r.first['b'] as int?) ?? 0;
  }

  /// Trial balance: every account with its debit/credit totals.
  Future<List<Map<String, Object?>>> trialBalance(String generatorId, {String? from, String? to}) {
    return ctx.db.rawQuery('''
      SELECT a.code, a.name, a.type,
        COALESCE(SUM(l.debit),0) AS debit, COALESCE(SUM(l.credit),0) AS credit
      FROM accounts a LEFT JOIN journal_lines l ON l.account_id = a.id
        AND l.entry_date >= ? AND l.entry_date <= ?
      WHERE a.generator_id = ? GROUP BY a.id ORDER BY a.code''',
        [from ?? '0000-00-00', to ?? '9999-12-31', generatorId]);
  }

  Future<List<Map<String, Object?>>> accountStatement(String generatorId, String code,
      {String? partyType, String? partyId, int limit = 500}) {
    return ctx.db.rawQuery('''
      SELECT l.*, e.description, e.source_type, e.source_id, e.reverses_id
      FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
      WHERE l.account_id = ? ${partyType != null ? 'AND l.party_type = ?' : ''}
        ${partyId != null ? 'AND l.party_id = ?' : ''}
      ORDER BY l.entry_date, e.created_at LIMIT ?''',
        [accountId(generatorId, code), if (partyType != null) partyType, if (partyId != null) partyId, limit]);
  }
}
