import '../security/permissions.dart';
import '../util/dates.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'ledger_service.dart';
import 'network_service.dart';

class ExpenseCategory {
  static const maintenance = 'maintenance';
  static const salaries = 'salaries';
  static const commissions = 'commissions';
  static const oilFilters = 'oil_filters';
  static const rent = 'rent';
  static const transport = 'transport';
  static const other = 'other';

  static const labels = {
    maintenance: 'صيانة وقطع غيار',
    salaries: 'رواتب وأجور',
    commissions: 'عمولات الجباة',
    oilFilters: 'زيوت وفلاتر',
    rent: 'إيجار',
    transport: 'نقل',
    other: 'أخرى',
  };

  static const accounts = {
    maintenance: Acc.maintenance,
    salaries: Acc.salaries,
    commissions: Acc.commissions,
    oilFilters: Acc.oilFilters,
    rent: Acc.rent,
    transport: Acc.transport,
    other: Acc.otherExpense,
  };
}

class PayMethod {
  static const cash = 'cash';
  static const credit = 'credit'; // on account (owed to supplier)
  static const labels = {cash: 'نقداً من الصندوق', credit: 'بالآجل (دين للمجهز)'};
}

/// Cash-box movement kinds that are not tied to subscribers.
class CashOp {
  static const capitalIn = 'capital_in';
  static const ownerWithdrawal = 'owner_withdrawal';
  static const supplierPayment = 'supplier_payment';
  static const employeeAdvance = 'employee_advance';
  static const advanceRepayment = 'advance_repayment';
  static const otherIncome = 'other_income';
  static const transfer = 'transfer';

  static const labels = {
    capitalIn: 'إيداع رأس مال',
    ownerWithdrawal: 'سحب المالك',
    supplierPayment: 'تسديد مجهز',
    employeeAdvance: 'سلفة موظف',
    advanceRepayment: 'استرداد سلفة',
    otherIncome: 'إيراد آخر',
    transfer: 'تحويل بين صناديق',
  };
}

/// Result of a cash reconciliation.
class CashReconciliation {
  final int opening;
  final int receipts;
  final int disbursements;
  final int expected;
  const CashReconciliation(this.opening, this.receipts, this.disbursements, this.expected);
}

class FinanceService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final LedgerService ledger;
  final NetworkService network;
  FinanceService(this.ctx, this.store, this.audit, this.ledger, this.network);

  // -------------------------------------------------------------- cashbox

  Future<int> cashboxBalance(String cashboxId, {String? asOf}) async {
    ctx.require(Perm.financeView);
    final box = await ctx.db.query('cashboxes', where: 'id = ?', whereArgs: [cashboxId]);
    if (box.isEmpty) throw const DomainException('NOT_FOUND', 'الصندوق غير موجود.');
    final gen = box.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    return ledger.balance(gen, await network.cashboxCode(cashboxId), to: asOf);
  }

  /// Expected = opening balance + receipts − disbursements for [date].
  Future<CashReconciliation> reconcile(String cashboxId, String date) async {
    ctx.require(Perm.cashboxManage);
    final box = await ctx.db.query('cashboxes', where: 'id = ?', whereArgs: [cashboxId]);
    if (box.isEmpty) throw const DomainException('NOT_FOUND', 'الصندوق غير موجود.');
    final gen = box.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    final accId = box.first['account_id'] as String;
    final prev = ymd(parseYmd(date).subtract(const Duration(days: 1)));
    final opening = await ledger.balance(gen, accId.split(':').last, to: prev);
    final r = await ctx.db.rawQuery('''SELECT COALESCE(SUM(debit),0) d, COALESCE(SUM(credit),0) c
        FROM journal_lines WHERE account_id = ? AND entry_date = ?''', [accId, date]);
    final receipts = r.first['d'] as int;
    final out = r.first['c'] as int;
    return CashReconciliation(opening, receipts, out, opening + receipts - out);
  }

  /// Closes the day for a cash box comparing counted cash to the book. Any
  /// difference is posted to cash-over / cash-short accounts so the book
  /// matches reality, while the difference stays visible in reports.
  Future<Map<String, Object?>> closeDay(String cashboxId, {required int counted, String? date, String? notes}) async {
    ctx.require(Perm.cashboxManage);
    if (counted < 0) throw validation('المبلغ المعدود لا يكون سالباً.');
    final d = date ?? ctx.today;
    final rec = await reconcile(cashboxId, d);
    final box = (await ctx.db.query('cashboxes', where: 'id = ?', whereArgs: [cashboxId])).first;
    final gen = box['generator_id'] as String;
    final code = (box['account_id'] as String).split(':').last;
    final dup = await ctx.db.query('cash_closings', where: 'cashbox_id = ? AND close_date = ?', whereArgs: [cashboxId, d]);
    if (dup.isNotEmpty) throw validation('تم إغلاق هذا الصندوق لهذا اليوم مسبقاً.');
    final diff = counted - rec.expected;
    if (diff != 0 && (notes == null || notes.trim().isEmpty)) {
      throw validation('يوجد فرق في الصندوق؛ يجب كتابة ملاحظة توضح السبب.');
    }
    final id = 'close:$cashboxId:$d';
    final row = {
      'id': id, 'generator_id': gen, 'cashbox_id': cashboxId, 'close_date': d, 'expected': rec.expected,
      'counted': counted, 'difference': diff, 'notes': notes, 'created_at': ctx.nowIso, 'created_by': ctx.userId,
    };
    await ctx.db.transaction((t) async {
      await store.insert(t, 'cash_closings', row);
      if (diff != 0) {
        await ledger.post(t,
            entryId: 'je:$id',
            generatorId: gen,
            date: d,
            description: diff > 0 ? 'فائض صندوق عند الإغلاق اليومي' : 'عجز صندوق عند الإغلاق اليومي',
            sourceType: 'cash_close',
            sourceId: id,
            lines: diff > 0
                ? [JLine.dr(code, diff), JLine.cr(Acc.cashOver, diff)]
                : [JLine.dr(Acc.cashShort, -diff), JLine.cr(code, -diff)]);
        await t.insert('notifications', {
          'id': newId(), 'generator_id': gen, 'kind': 'cash_difference', 'severity': 'high',
          'title': 'اختلاف في الصندوق',
          'body': 'فرق ${diff > 0 ? 'فائض' : 'عجز'} بمقدار ${diff.abs()} د.ع عند إغلاق $d. ${notes ?? ''}',
          'created_at': ctx.nowIso, 'dedupe_key': 'cashdiff:$id',
        });
      }
      await audit.log(t, 'cash.close_day', entity: 'cash_closings', entityId: id, generatorId: gen,
          details: {'expected': rec.expected, 'counted': counted, 'difference': diff});
    });
    return row;
  }

  Future<List<Map<String, Object?>>> closings(String generatorId, {int limit = 60}) {
    ctx.require(Perm.financeView);
    return ctx.db.rawQuery('''SELECT cc.*, cb.name AS cashbox_name FROM cash_closings cc
        JOIN cashboxes cb ON cb.id = cc.cashbox_id WHERE cc.generator_id = ?
        ORDER BY cc.close_date DESC LIMIT ?''', [generatorId, limit]);
  }

  Future<List<Map<String, Object?>>> cashboxMovements(String cashboxId, DateRange range) async {
    ctx.require(Perm.financeView);
    final box = await ctx.db.query('cashboxes', where: 'id = ?', whereArgs: [cashboxId]);
    if (box.isEmpty) throw const DomainException('NOT_FOUND', 'الصندوق غير موجود.');
    ctx.requireGenerator(box.first['generator_id'] as String);
    return ctx.db.rawQuery('''SELECT l.entry_date, l.debit, l.credit, e.description, e.source_type, e.id AS entry_id,
        e.reverses_id, (SELECT 1 FROM journal_entries r WHERE r.reverses_id = e.id) AS reversed
        FROM journal_lines l JOIN journal_entries e ON e.id = l.entry_id
        WHERE l.account_id = ? AND l.entry_date BETWEEN ? AND ? ORDER BY l.entry_date DESC, e.created_at DESC''',
        [box.first['account_id'], range.from, range.to]);
  }

  /// Non-subscriber cash movements: capital, owner withdrawals, supplier
  /// payments, employee advances, other income, transfers between boxes.
  Future<String> cashOperation({
    required String generatorId,
    required String kind,
    required int amount,
    String? cashboxId,
    String? targetCashboxId,
    String? supplierId,
    String? employeeId,
    String? description,
    String? date,
  }) async {
    ctx.require(Perm.cashboxManage);
    ctx.requireGenerator(generatorId);
    if (amount <= 0) throw validation('المبلغ يجب أن يكون أكبر من صفر.');
    final box = cashboxId ?? NetworkService.mainCashbox(generatorId);
    final id = newId();
    final d = date ?? ctx.today;
    await ctx.db.transaction((t) async {
      final cash = await network.cashboxCode(box, t);
      final lines = switch (kind) {
        CashOp.capitalIn => [JLine.dr(cash, amount), JLine.cr(Acc.capital, amount)],
        CashOp.ownerWithdrawal => [JLine.dr(Acc.ownerDrawings, amount), JLine.cr(cash, amount)],
        CashOp.otherIncome => [JLine.dr(cash, amount), JLine.cr(Acc.otherRevenue, amount)],
        CashOp.supplierPayment => () {
            if (supplierId == null) throw validation('اختر المجهز.');
            return [
              JLine.dr(Acc.payables, amount, partyType: PartyType.supplier, partyId: supplierId),
              JLine.cr(cash, amount),
            ];
          }(),
        CashOp.employeeAdvance => () {
            if (employeeId == null) throw validation('اختر الموظف.');
            return [
              JLine.dr(Acc.employeeAdvances, amount, partyType: PartyType.employee, partyId: employeeId),
              JLine.cr(cash, amount),
            ];
          }(),
        CashOp.advanceRepayment => () {
            if (employeeId == null) throw validation('اختر الموظف.');
            return [
              JLine.dr(cash, amount),
              JLine.cr(Acc.employeeAdvances, amount, partyType: PartyType.employee, partyId: employeeId),
            ];
          }(),
        CashOp.transfer => () {
            if (targetCashboxId == null || targetCashboxId == box) throw validation('اختر صندوقاً آخر للتحويل.');
            return <JLine>[];
          }(),
        _ => throw validation('نوع عملية غير معروف.'),
      };
      final effective = kind == CashOp.transfer
          ? [JLine.dr(await network.cashboxCode(targetCashboxId!, t), amount), JLine.cr(cash, amount)]
          : lines;
      if (kind != CashOp.capitalIn && kind != CashOp.otherIncome && kind != CashOp.advanceRepayment) {
        final bal = await ledger.balance(generatorId, cash, ex: t);
        if (amount > bal) {
          throw validation('رصيد الصندوق ($bal د.ع) لا يكفي لهذه العملية.');
        }
      }
      await ledger.post(t,
          entryId: 'je:cash:$id',
          generatorId: generatorId,
          date: d,
          description: '${CashOp.labels[kind]}${description == null || description.isEmpty ? '' : ' — $description'}',
          sourceType: 'cash_op:$kind',
          sourceId: id,
          lines: effective);
      await audit.log(t, 'cash.$kind', entity: 'journal_entries', entityId: 'je:cash:$id', generatorId: generatorId,
          details: {'amount': amount});
    });
    return 'je:cash:$id';
  }

  /// Cancels a manual entry (cash operation / expense) with a reversing entry.
  Future<void> reverseEntry(String entryId, {required String reason}) async {
    ctx.require(Perm.paymentsReverse);
    if (reason.trim().length < 3) throw validation('يجب ذكر سبب الإلغاء.');
    final e = await ctx.db.query('journal_entries', where: 'id = ?', whereArgs: [entryId]);
    if (e.isEmpty) throw const DomainException('NOT_FOUND', 'القيد غير موجود.');
    final src = e.first['source_type'] as String;
    if (src == 'payment') {
      throw validation('لإلغاء دفعة مشترك استخدم إلغاء الدفعة من سجل المشترك.');
    }
    if (src == 'reversal') throw validation('لا يمكن عكس قيد عكسي.');
    final gen = e.first['generator_id'] as String;
    ctx.requireGenerator(gen);
    await ctx.db.transaction((t) async {
      await ledger.reverse(t, entryId, reason: reason);
      await audit.log(t, 'ledger.reverse', entity: 'journal_entries', entityId: entryId, generatorId: gen,
          details: {'reason': reason});
    });
  }

  // ------------------------------------------------------------- expenses

  Future<String> recordExpense({
    required String generatorId,
    required String category,
    required int amount,
    String payMethod = PayMethod.cash,
    String? cashboxId,
    String? supplierId,
    String? employeeId,
    String? description,
    String? reference,
    String? date,
    bool checkPermission = true,
  }) async {
    if (checkPermission) ctx.require(Perm.expensesManage);
    ctx.requireGenerator(generatorId);
    if (amount <= 0) throw validation('المبلغ يجب أن يكون أكبر من صفر.');
    final acc = ExpenseCategory.accounts[category];
    if (acc == null) throw validation('تصنيف المصروف غير معروف.');
    if (payMethod == PayMethod.credit && supplierId == null) {
      throw validation('المصروف الآجل يجب أن يرتبط بمجهز.');
    }
    final id = newId();
    final d = date ?? ctx.today;
    final box = payMethod == PayMethod.cash ? (cashboxId ?? NetworkService.mainCashbox(generatorId)) : null;
    await ctx.db.transaction((t) async {
      await store.insert(t, 'expenses', {
        'id': id, 'generator_id': generatorId, 'category': category, 'amount': amount, 'expense_date': d,
        'pay_method': payMethod, 'cashbox_id': box, 'supplier_id': supplierId, 'employee_id': employeeId,
        'description': description, 'reference': reference, 'created_at': ctx.nowIso, 'created_by': ctx.userId,
      });
      await ledger.post(t,
          entryId: 'je:exp:$id',
          generatorId: generatorId,
          date: d,
          description: '${ExpenseCategory.labels[category]}${description == null || description.isEmpty ? '' : ' — $description'}',
          sourceType: 'expense',
          sourceId: id,
          lines: [
            JLine.dr(acc, amount,
                partyType: employeeId != null ? PartyType.employee : null, partyId: employeeId),
            if (payMethod == PayMethod.cash)
              JLine.cr(await network.cashboxCode(box!, t), amount)
            else
              JLine.cr(Acc.payables, amount, partyType: PartyType.supplier, partyId: supplierId),
          ]);
      await audit.log(t, 'expenses.create', entity: 'expenses', entityId: id, generatorId: generatorId,
          details: {'amount': amount, 'category': category});
    });
    return id;
  }

  Future<List<Map<String, Object?>>> listExpenses(String generatorId, DateRange range) {
    ctx.require(Perm.expensesManage);
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT x.*, s.name AS supplier_name, e.full_name AS employee_name,
        (SELECT 1 FROM journal_entries r WHERE r.reverses_id = 'je:exp:' || x.id) AS reversed
        FROM expenses x LEFT JOIN suppliers s ON s.id = x.supplier_id LEFT JOIN employees e ON e.id = x.employee_id
        WHERE x.generator_id = ? AND x.expense_date BETWEEN ? AND ? ORDER BY x.expense_date DESC, x.created_at DESC''',
        [generatorId, range.from, range.to]);
  }

  // ------------------------------------------------------------ suppliers

  Future<String> createSupplier(String generatorId, String name, {String? phone, String kind = 'fuel', String? notes}) async {
    if (!ctx.can(Perm.fuelManage) && !ctx.can(Perm.expensesManage)) throw const PermissionDenied(Perm.expensesManage);
    ctx.requireGenerator(generatorId);
    if (name.trim().length < 2) throw validation('اسم المجهز مطلوب.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'suppliers',
          {'id': id, 'generator_id': generatorId, 'name': name.trim(), 'phone': phone, 'kind': kind, 'notes': notes});
      await audit.log(t, 'suppliers.create', entity: 'suppliers', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  /// Suppliers with the amount still owed to each (credit balance of payables).
  Future<List<Map<String, Object?>>> listSuppliers(String generatorId) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT s.*, COALESCE((SELECT SUM(credit - debit) FROM journal_lines jl
        WHERE jl.account_id = ? AND jl.party_type = 'supplier' AND jl.party_id = s.id), 0) AS owed
        FROM suppliers s WHERE s.generator_id = ? AND s.active = 1 ORDER BY s.name''',
        [LedgerService.accountId(generatorId, Acc.payables), generatorId]);
  }

  // ------------------------------------------------------------ employees

  Future<String> createEmployee(String generatorId, String fullName,
      {String? phone, String? job, int monthlySalary = 0, String? userId}) async {
    ctx.require(Perm.usersManage);
    ctx.requireGenerator(generatorId);
    if (fullName.trim().length < 3) throw validation('اسم الموظف مطلوب.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'employees', {
        'id': id, 'generator_id': generatorId, 'full_name': fullName.trim(), 'phone': phone, 'job': job,
        'monthly_salary': monthlySalary, 'user_id': userId,
      });
      await audit.log(t, 'employees.create', entity: 'employees', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<List<Map<String, Object?>>> listEmployees(String generatorId) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT e.*, COALESCE((SELECT SUM(debit - credit) FROM journal_lines jl
        WHERE jl.account_id = ? AND jl.party_type = 'employee' AND jl.party_id = e.id), 0) AS advances
        FROM employees e WHERE e.generator_id = ? AND e.active = 1 ORDER BY e.full_name''',
        [LedgerService.accountId(generatorId, Acc.employeeAdvances), generatorId]);
  }
}
