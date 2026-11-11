import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../security/permissions.dart';
import '../util/dates.dart';
import '../util/errors.dart';
import '../util/ids.dart';
import 'context.dart';
import 'finance_service.dart';
import 'ledger_service.dart';
import 'network_service.dart';

/// Where a fuel figure came from. A typed figure is never presented as a
/// sensor measurement.
class FuelSource {
  static const manual = 'manual';
  static const sensor = 'sensor';
  static const labels = {manual: 'إدخال يدوي', sensor: 'قراءة حساس'};
}

class FuelStock {
  /// Book quantity: purchases − recorded consumption (millilitres).
  final int bookMl;
  /// Book value of the stock (dinars) from the ledger.
  final int value;
  /// Last physical measurement, if any.
  final int? lastDipMl;
  final String? lastDipAt;
  final String? lastDipSource;
  const FuelStock(this.bookMl, this.value, this.lastDipMl, this.lastDipAt, this.lastDipSource);

  /// Weighted average cost per litre.
  int get avgCostPerLiter => bookMl <= 0 ? 0 : (value * 1000 / bookMl).round();
}

class FuelStats {
  final int consumedMl;
  final int days;
  final double avgDailyMl;
  final int cost;
  final double runHours;
  final double? litersPerHour;
  final int? costPerHour;
  final int forecastNext7DaysMl;
  final List<Map<String, Object?>> anomalies;
  const FuelStats({
    required this.consumedMl,
    required this.days,
    required this.avgDailyMl,
    required this.cost,
    required this.runHours,
    required this.litersPerHour,
    required this.costPerHour,
    required this.forecastNext7DaysMl,
    required this.anomalies,
  });
}

class FuelService {
  final CoreContext ctx;
  final Store store;
  final AuditService audit;
  final LedgerService ledger;
  final NetworkService network;
  FuelService(this.ctx, this.store, this.audit, this.ledger, this.network);

  Future<int> _bookMl(DatabaseExecutor ex, String generatorId) async {
    final p = await ex.rawQuery(
        'SELECT COALESCE(SUM(quantity_ml),0) q FROM fuel_purchases WHERE generator_id = ?', [generatorId]);
    final c = await ex.rawQuery(
        'SELECT COALESCE(SUM(quantity_ml),0) q FROM fuel_consumptions WHERE generator_id = ?', [generatorId]);
    return (p.first['q'] as int) - (c.first['q'] as int);
  }

  Future<FuelStock> stock(String generatorId) async {
    ctx.requireGenerator(generatorId);
    final book = await _bookMl(ctx.db, generatorId);
    final value = await ledger.balance(generatorId, Acc.fuelInventory);
    final dip = await ctx.db.query('fuel_dips',
        where: 'generator_id = ?', whereArgs: [generatorId], orderBy: 'measured_at DESC', limit: 1);
    return FuelStock(book, value, dip.isEmpty ? null : dip.first['quantity_ml'] as int,
        dip.isEmpty ? null : dip.first['measured_at'] as String,
        dip.isEmpty ? null : dip.first['source'] as String);
  }

  Future<String> purchase({
    required String generatorId,
    required int quantityMl,
    required int pricePerLiter,
    String? supplierId,
    String payMethod = PayMethod.cash,
    String? cashboxId,
    String? invoiceNo,
    String? notes,
    String? date,
  }) async {
    ctx.require(Perm.fuelManage);
    ctx.requireGenerator(generatorId);
    if (quantityMl <= 0) throw validation('الكمية يجب أن تكون أكبر من صفر.');
    if (pricePerLiter <= 0) throw validation('سعر اللتر غير صحيح.');
    if (payMethod == PayMethod.credit && supplierId == null) throw validation('الشراء بالآجل يتطلب تحديد المجهز.');
    final total = (quantityMl * pricePerLiter / 1000).round();
    final id = newId();
    final d = date ?? ctx.today;
    final box = payMethod == PayMethod.cash ? (cashboxId ?? NetworkService.mainCashbox(generatorId)) : null;
    await ctx.db.transaction((t) async {
      await store.insert(t, 'fuel_purchases', {
        'id': id, 'generator_id': generatorId, 'supplier_id': supplierId, 'purchase_date': d,
        'quantity_ml': quantityMl, 'price_per_liter': pricePerLiter, 'total': total, 'pay_method': payMethod,
        'cashbox_id': box, 'invoice_no': invoiceNo, 'notes': notes, 'created_at': ctx.nowIso,
        'created_by': ctx.userId,
      });
      await ledger.post(t,
          entryId: 'je:fuelp:$id',
          generatorId: generatorId,
          date: d,
          description: 'شراء كاز ${quantityMl ~/ 1000} لتر × $pricePerLiter${invoiceNo != null ? ' (فاتورة $invoiceNo)' : ''}',
          sourceType: 'fuel_purchase',
          sourceId: id,
          lines: [
            JLine.dr(Acc.fuelInventory, total),
            if (payMethod == PayMethod.cash)
              JLine.cr(await network.cashboxCode(box!, t), total)
            else
              JLine.cr(Acc.payables, total, partyType: PartyType.supplier, partyId: supplierId),
          ]);
      await audit.log(t, 'fuel.purchase', entity: 'fuel_purchases', entityId: id, generatorId: generatorId,
          details: {'ml': quantityMl, 'total': total});
    });
    return id;
  }

  /// Records consumption valued at the weighted-average cost of the stock.
  Future<String> consume({
    required String generatorId,
    required int quantityMl,
    double? runHours,
    String source = FuelSource.manual,
    String? notes,
    String? date,
  }) async {
    ctx.require(Perm.fuelManage);
    ctx.requireGenerator(generatorId);
    if (quantityMl <= 0) throw validation('الكمية يجب أن تكون أكبر من صفر.');
    if (!FuelSource.labels.containsKey(source)) throw validation('مصدر القراءة غير معروف.');
    final id = newId();
    final d = date ?? ctx.today;
    await ctx.db.transaction((t) async {
      final book = await _bookMl(t, generatorId);
      if (quantityMl > book) {
        throw validation('الكمية المستهلكة (${quantityMl / 1000} لتر) أكبر من المخزون المسجل (${book / 1000} لتر). '
            'سجّل عملية الشراء أولاً.');
      }
      final value = await ledger.balance(generatorId, Acc.fuelInventory, ex: t);
      // Consuming the whole book stock takes the whole remaining value so no
      // rounding residue is left in the inventory account.
      final cost = quantityMl == book ? value : (value * quantityMl / book).round();
      await store.insert(t, 'fuel_consumptions', {
        'id': id, 'generator_id': generatorId, 'consumption_date': d, 'quantity_ml': quantityMl, 'cost': cost,
        'run_hours_x100': runHours == null ? null : (runHours * 100).round(), 'source': source, 'notes': notes,
        'created_at': ctx.nowIso, 'created_by': ctx.userId,
      });
      if (cost > 0) {
        await ledger.post(t,
            entryId: 'je:fuelc:$id',
            generatorId: generatorId,
            date: d,
            description: 'استهلاك كاز ${quantityMl / 1000} لتر (${FuelSource.labels[source]})',
            sourceType: 'fuel_consumption',
            sourceId: id,
            lines: [JLine.dr(Acc.fuelExpense, cost), JLine.cr(Acc.fuelInventory, cost)]);
      }
      await audit.log(t, 'fuel.consume', entity: 'fuel_consumptions', entityId: id, generatorId: generatorId,
          details: {'ml': quantityMl, 'cost': cost, 'source': source});
    });
    return id;
  }

  /// Physical tank measurement (dip stick / gauge / sensor).
  Future<String> recordDip(String generatorId, int quantityMl, {String source = FuelSource.manual, String? notes}) async {
    ctx.require(Perm.fuelManage);
    ctx.requireGenerator(generatorId);
    if (quantityMl < 0) throw validation('الكمية غير صحيحة.');
    final id = newId();
    await ctx.db.transaction((t) async {
      await store.insert(t, 'fuel_dips', {
        'id': id, 'generator_id': generatorId, 'measured_at': ctx.nowIso, 'quantity_ml': quantityMl,
        'source': source, 'notes': notes, 'created_at': ctx.nowIso, 'created_by': ctx.userId,
      });
      await audit.log(t, 'fuel.dip', entity: 'fuel_dips', entityId: id, generatorId: generatorId);
    });
    return id;
  }

  Future<List<Map<String, Object?>>> purchases(String generatorId, DateRange range) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT p.*, s.name AS supplier_name FROM fuel_purchases p
        LEFT JOIN suppliers s ON s.id = p.supplier_id
        WHERE p.generator_id = ? AND p.purchase_date BETWEEN ? AND ? ORDER BY p.purchase_date DESC, p.created_at DESC''',
        [generatorId, range.from, range.to]);
  }

  Future<List<Map<String, Object?>>> consumptions(String generatorId, DateRange range) {
    ctx.requireGenerator(generatorId);
    return ctx.db.rawQuery('''SELECT * FROM fuel_consumptions WHERE generator_id = ?
        AND consumption_date BETWEEN ? AND ? ORDER BY consumption_date DESC, created_at DESC''',
        [generatorId, range.from, range.to]);
  }

  Future<List<Map<String, Object?>>> dailyConsumption(String generatorId, DateRange range) =>
      ctx.db.rawQuery('''SELECT consumption_date AS day, SUM(quantity_ml) AS ml, SUM(cost) AS cost,
          SUM(run_hours_x100) AS hours_x100 FROM fuel_consumptions
          WHERE generator_id = ? AND consumption_date BETWEEN ? AND ? GROUP BY consumption_date ORDER BY day''',
          [generatorId, range.from, range.to]);

  /// Consumption statistics with anomaly detection: a day is flagged when
  /// its consumption exceeds mean + 2·σ of the range (with at least 5 days of
  /// data), or when litres-per-hour is 30% above the period median.
  Future<FuelStats> stats(String generatorId, DateRange range, {double? runHoursOverride}) async {
    ctx.requireGenerator(generatorId);
    final days = await dailyConsumption(generatorId, range);
    final totalMl = days.fold<int>(0, (a, r) => a + (r['ml'] as int));
    final cost = days.fold<int>(0, (a, r) => a + (r['cost'] as int));
    final spanDays = parseYmd(range.to).difference(parseYmd(range.from)).inDays + 1;
    final runHours = runHoursOverride ?? await _runHours(generatorId, range);
    final anomalies = <Map<String, Object?>>[];
    if (days.length >= 5) {
      final vals = days.map((r) => (r['ml'] as int).toDouble()).toList();
      final mean = vals.reduce((a, b) => a + b) / vals.length;
      final sd = sqrt(vals.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / vals.length);
      for (final r in days) {
        final v = (r['ml'] as int).toDouble();
        if (sd > 0 && v > mean + 2 * sd) {
          anomalies.add({'day': r['day'], 'ml': r['ml'], 'reason': 'استهلاك أعلى بكثير من المعدل'});
        }
      }
      final rates = days
          .where((r) => (r['hours_x100'] as int? ?? 0) > 0)
          .map((r) => (r['ml'] as int) / ((r['hours_x100'] as int) / 100))
          .toList()
        ..sort();
      if (rates.length >= 5) {
        final median = rates[rates.length ~/ 2];
        for (final r in days) {
          final h = r['hours_x100'] as int? ?? 0;
          if (h <= 0) continue;
          final rate = (r['ml'] as int) / (h / 100);
          if (rate > median * 1.3 && !anomalies.any((a) => a['day'] == r['day'])) {
            anomalies.add({'day': r['day'], 'ml': r['ml'], 'reason': 'استهلاك لكل ساعة أعلى من المعتاد بأكثر من 30%'});
          }
        }
      }
    }
    final avgDaily = spanDays <= 0 ? 0.0 : totalMl / spanDays;
    return FuelStats(
      consumedMl: totalMl,
      days: spanDays,
      avgDailyMl: avgDaily,
      cost: cost,
      runHours: runHours,
      litersPerHour: runHours > 0 ? totalMl / 1000 / runHours : null,
      costPerHour: runHours > 0 ? (cost / runHours).round() : null,
      forecastNext7DaysMl: (avgDaily * 7).round(),
      anomalies: anomalies,
    );
  }

  Future<double> _runHours(String generatorId, DateRange range) async {
    final rows = await ctx.db.query('generator_runs',
        where: 'generator_id = ? AND started_at >= ? AND started_at <= ?',
        whereArgs: [generatorId, range.from, '${range.to}T23:59:59']);
    var minutes = 0;
    for (final r in rows) {
      final s = DateTime.parse(r['started_at'] as String);
      final e = r['stopped_at'] == null ? ctx.now : DateTime.parse(r['stopped_at'] as String);
      minutes += e.difference(s).inMinutes;
    }
    return minutes / 60;
  }
}
