import '../security/permissions.dart';
import '../services/context.dart';
import '../services/fuel_service.dart';
import '../services/collection_service.dart';
import '../services/operations_service.dart';
import '../services/report_service.dart';
import '../services/subscriber_service.dart';
import '../util/dates.dart';
import '../util/money.dart';

class AssistantFact {
  final String label;
  final String value;
  const AssistantFact(this.label, this.value);
}

class AssistantAnswer {
  final String intent;
  final String text;
  final List<AssistantFact> facts;
  const AssistantAnswer(this.intent, this.text, [this.facts = const []]);
}

/// Optional connector to an external language model, used only to *rephrase*
/// answers computed locally. Keys are entered by the owner on the device and
/// never shipped in the app. Not required for any feature.
abstract class ExternalLanguageModel {
  Future<String> rephrase(String question, AssistantAnswer computed);
}

/// Normalises Arabic text: removes diacritics/tatweel and unifies letter
/// variants so dialect spellings match.
String normalizeArabic(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[ً-ْـ]'), '');
  s = s.replaceAll(RegExp('[أإآٱ]'), 'ا');
  s = s.replaceAll('ى', 'ي').replaceAll('ة', 'ه').replaceAll('ؤ', 'و').replaceAll('ئ', 'ي');
  s = s.replaceAll('گ', 'ك').replaceAll('چ', 'ج').replaceAll('پ', 'ب').replaceAll('ڤ', 'ف');
  s = s.replaceAll(RegExp(r'[؟?!.,،]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

enum _Time { today, yesterday, thisWeek, thisMonth, lastMonth, thisYear }

/// "Generator AI": understands Arabic and Iraqi dialect questions about the
/// business and answers from the real database through [ReportService].
/// Every number is computed by the accounting engine, not by a model.
class GeneratorAssistant {
  final CoreContext ctx;
  final ReportService reports;
  final FuelService fuel;
  final CollectionService collection;
  final OperationsService ops;
  final SubscriberService subscribers;
  GeneratorAssistant(this.ctx, this.reports, this.fuel, this.collection, this.ops, this.subscribers);

  static const examples = [
    'شكد ربحي هذا الشهر؟',
    'شكد ديون المشتركين؟',
    'منو أكثر جابي حصّل؟',
    'شكد صرفنا كاز؟',
    'شنو أكثر منطقة بيها ديون؟',
    'قارنلي أرباح هذا الشهر بالشهر السابق',
    'شنو المصاريف اللي زادت؟',
    'شكد أحتاج كاز للأسبوع القادم؟',
    'شكد جبينا اليوم؟',
    'كم مشترك عدنا؟',
    'اكو شي غير طبيعي؟',
    'توقع ايرادات الشهر الجاي',
  ];

  bool _has(String s, List<String> words) => words.any(s.contains);

  _Time _time(String s, _Time fallback) {
    if (_has(s, ['البارحه', 'امس', 'مبارح'])) return _Time.yesterday;
    if (_has(s, ['اليوم', 'هسه', 'لهسه'])) return _Time.today;
    if (_has(s, ['الاسبوع', 'هالاسبوع', 'اسبوع'])) return _Time.thisWeek;
    if (_has(s, ['الشهر الماضي', 'الشهر الفات', 'الشهر اللي فات', 'الشهر السابق', 'الشهر القبل', 'الشهر الي فات'])) {
      return _Time.lastMonth;
    }
    if (_has(s, ['السنه', 'هالسنه', 'العام'])) return _Time.thisYear;
    if (_has(s, ['الشهر', 'هالشهر'])) return _Time.thisMonth;
    return fallback;
  }

  (DateRange, String) _range(_Time t) {
    final n = ctx.now;
    return switch (t) {
      _Time.today => (DateRange.day(n), 'اليوم'),
      _Time.yesterday => (DateRange.day(n.subtract(const Duration(days: 1))), 'أمس'),
      _Time.thisWeek => (DateRange.lastDays(n, 7), 'آخر 7 أيام'),
      _Time.thisMonth => (DateRange.month(n), 'هذا الشهر'),
      _Time.lastMonth => (DateRange.month(DateTime(n.year, n.month - 1, 1)), 'الشهر الماضي'),
      _Time.thisYear => (DateRange.year(n), 'هذه السنة'),
    };
  }

  Future<AssistantAnswer> ask(String generatorId, String question) async {
    if (!ctx.can(Perm.aiUse)) {
      return const AssistantAnswer('denied', 'ليست لديك صلاحية استخدام المساعد الذكي.');
    }
    ctx.requireGenerator(generatorId);
    final s = normalizeArabic(question);
    if (s.isEmpty) return _help();
    final needsFinance = ctx.can(Perm.financeView);

    // Order matters: more specific intents first.
    if (_has(s, ['قارن', 'مقارنه', 'مقارنة'])) {
      if (!needsFinance) return _noFinance();
      return _compareMonths(generatorId);
    }
    if (_has(s, ['غير طبيعي', 'غريب', 'مشبوه', 'فروقات', 'فرق', 'شذوذ', 'مشاكل'])) {
      return _anomalies(generatorId);
    }
    if (_has(s, ['كاز', 'وقود', 'بنزين', 'ديزل'])) {
      if (_has(s, ['احتاج', 'نحتاج', 'يكفي', 'يلزم', 'القادم', 'الجاي', 'الياي', 'راح'])) return _fuelNeed(generatorId);
      if (_has(s, ['باقي', 'موجود', 'مخزون', 'عدنا', 'متبقي', 'رصيد'])) return _fuelStock(generatorId);
      return _fuelSpent(generatorId, _time(s, _Time.thisMonth));
    }
    if (_has(s, ['توقع', 'تتوقع', 'متوقع'])) {
      if (!needsFinance) return _noFinance();
      return _forecast(generatorId);
    }
    if (_has(s, ['مصاريف', 'مصروفات', 'مصروف', 'صرفيات'])) {
      if (!needsFinance) return _noFinance();
      if (_has(s, ['زاد', 'زادت', 'ارتفع', 'ارتفعت', 'صعد', 'اكثر'])) return _expenseIncrease(generatorId);
      return _expenses(generatorId, _time(s, _Time.thisMonth));
    }
    if (_has(s, ['ربح', 'ارباح', 'فايده', 'فائده', 'صافي', 'مربح'])) {
      if (!needsFinance) return _noFinance();
      return _profit(generatorId, _time(s, _Time.thisMonth));
    }
    if (_has(s, ['جابي', 'جباه', 'جبايه', 'الجباة'])) {
      if (_has(s, ['اكثر', 'احسن', 'افضل', 'منو', 'اعلى'])) return _topCollector(generatorId, _time(s, _Time.thisMonth));
    }
    if (_has(s, ['دين', 'ديون', 'مطلوب', 'متاخر', 'مديون', 'باقي عليهم', 'غير مسدد'])) {
      if (_has(s, ['منطقه', 'مناطق', 'محله', 'حي'])) return _debtByArea(generatorId);
      return _debts(generatorId);
    }
    if (_has(s, ['جبينا', 'حصلنا', 'استلمنا', 'مقبوضات', 'تحصيل', 'جبايه', 'دخل', 'ايراد', 'ايرادات'])) {
      return _collections(generatorId, _time(s, _Time.today));
    }
    if (_has(s, ['مشترك', 'مشتركين', 'زباين', 'زبائن'])) return _subscriberCounts(generatorId);
    if (_has(s, ['ساعات', 'اشتغلت', 'تشغيل', 'شغاله'])) return _runHours(generatorId, _time(s, _Time.thisMonth));
    return _help();
  }

  AssistantAnswer _help() => AssistantAnswer('help',
      'لم أفهم السؤال. أستطيع الإجابة من بيانات النظام عن: الأرباح، الديون، الجباة، الكاز، المصاريف، المشتركين، '
          'ساعات التشغيل، والتوقعات. أمثلة:\n• ${examples.take(6).join('\n• ')}');

  AssistantAnswer _noFinance() =>
      const AssistantAnswer('denied', 'هذه المعلومة مالية ولا تسمح صلاحياتك بعرضها.');

  Future<AssistantAnswer> _profit(String g, _Time t) async {
    final (r, label) = _range(t);
    final p = await reports.pnl(g, r);
    return AssistantAnswer(
        'profit',
        'صافي الربح $label: ${formatMoney(p.profit)}\n'
            'الإيرادات (الفواتير بعد الخصومات): ${formatMoney(p.revenue)} — المصروفات: ${formatMoney(p.expenses)}.',
        [
          AssistantFact('الإيرادات', formatMoney(p.revenue)),
          AssistantFact('المصروفات', formatMoney(p.expenses)),
          AssistantFact('صافي الربح', formatMoney(p.profit)),
        ]);
  }

  Future<AssistantAnswer> _compareMonths(String g) async {
    final (cur, _) = _range(_Time.thisMonth);
    final (prev, _) = _range(_Time.lastMonth);
    final a = await reports.pnl(g, cur), b = await reports.pnl(g, prev);
    final diff = a.profit - b.profit;
    final pct = b.profit == 0 ? null : (diff * 100 / b.profit.abs());
    return AssistantAnswer(
        'compare',
        'ربح هذا الشهر ${formatMoney(a.profit)} مقابل ${formatMoney(b.profit)} الشهر الماضي — '
            '${diff >= 0 ? 'زيادة' : 'انخفاض'} ${formatMoney(diff.abs())}${pct != null ? ' (${pct.abs().toStringAsFixed(1)}%)' : ''}.\n'
            'ملاحظة: الشهر الحالي لم ينتهِ بعد.',
        [
          AssistantFact('إيرادات هذا الشهر', formatMoney(a.revenue)),
          AssistantFact('إيرادات الشهر الماضي', formatMoney(b.revenue)),
          AssistantFact('مصروفات هذا الشهر', formatMoney(a.expenses)),
          AssistantFact('مصروفات الشهر الماضي', formatMoney(b.expenses)),
        ]);
  }

  Future<AssistantAnswer> _debts(String g) async {
    final total = await reports.totalDebt(g);
    final list = await reports.debtors(g, limit: 5);
    final counts = await subscribers.counts(g);
    return AssistantAnswer(
        'debts',
        'إجمالي ديون المشتركين: ${formatMoney(total)} على ${counts['debtors']} مشترك.'
            '${list.isEmpty ? '' : '\nأعلى المديونين:\n${list.map((d) => '• ${d['full_name']}: ${formatMoney(d['balance'] as int)}').join('\n')}'}',
        [AssistantFact('إجمالي الديون', formatMoney(total)), AssistantFact('عدد المديونين', '${counts['debtors']}')]);
  }

  Future<AssistantAnswer> _debtByArea(String g) async {
    final rows = await reports.debtByArea(g);
    if (rows.isEmpty) return const AssistantAnswer('debt_area', 'لا توجد ديون مسجلة حالياً.');
    final top = rows.first;
    return AssistantAnswer(
        'debt_area',
        'أكثر منطقة بيها ديون: ${top['area']} بمبلغ ${formatMoney(top['debt'] as int)} (${top['debtors']} مشترك).\n'
            '${rows.take(5).map((r) => '• ${r['area']}: ${formatMoney(r['debt'] as int)}').join('\n')}',
        [for (final r in rows.take(5)) AssistantFact(r['area'] as String, formatMoney(r['debt'] as int))]);
  }

  Future<AssistantAnswer> _topCollector(String g, _Time t) async {
    final (r, label) = _range(t);
    if (!ctx.can(Perm.collectorsViewAll)) {
      return const AssistantAnswer('denied', 'لا تسمح صلاحياتك بالاطلاع على حسابات الجباة الآخرين.');
    }
    final rows = (await collection.collectorPerformance(g, r)).where((c) => (c['collected'] as int) > 0).toList();
    if (rows.isEmpty) return AssistantAnswer('top_collector', 'لا توجد عمليات جباية مسجلة للجباة $label.');
    final top = rows.first;
    return AssistantAnswer(
        'top_collector',
        'أكثر جابي حصّل $label: ${top['full_name']} بمبلغ ${formatMoney(top['collected'] as int)} (${top['receipts']} وصل).\n'
            '${rows.take(5).map((c) => '• ${c['full_name']}: ${formatMoney(c['collected'] as int)}').join('\n')}',
        [for (final c in rows.take(5)) AssistantFact(c['full_name'] as String, formatMoney(c['collected'] as int))]);
  }

  Future<AssistantAnswer> _collections(String g, _Time t) async {
    final (r, label) = _range(t);
    final v = await reports.collections(g, r);
    return AssistantAnswer('collections', 'مجموع المبالغ المحصلة من المشتركين $label: ${formatMoney(v)}.',
        [AssistantFact('المقبوضات', formatMoney(v))]);
  }

  Future<AssistantAnswer> _fuelSpent(String g, _Time t) async {
    final (r, label) = _range(t);
    final st = await fuel.stats(g, r);
    return AssistantAnswer(
        'fuel_spent',
        'الكاز المستهلك المسجل $label: ${formatLiters(st.consumedMl)} بكلفة ${formatMoney(st.cost)}.'
            '${st.litersPerHour != null ? '\nمعدل الاستهلاك: ${st.litersPerHour!.toStringAsFixed(1)} لتر/ساعة.' : ''}'
            '\n(الأرقام من القيود المسجلة يدوياً أو من الحساسات حسب مصدر كل قيد.)',
        [
          AssistantFact('الكمية', formatLiters(st.consumedMl)),
          AssistantFact('الكلفة', formatMoney(st.cost)),
        ]);
  }

  Future<AssistantAnswer> _fuelStock(String g) async {
    final st = await fuel.stock(g);
    final dip = st.lastDipMl == null
        ? 'لا يوجد قياس فعلي مسجل للخزان.'
        : 'آخر قياس فعلي: ${formatLiters(st.lastDipMl!)} بتاريخ ${st.lastDipAt!.substring(0, 10)}.';
    return AssistantAnswer('fuel_stock', 'المخزون الدفتري للكاز: ${formatLiters(st.bookMl)}. $dip',
        [AssistantFact('المخزون الدفتري', formatLiters(st.bookMl))]);
  }

  Future<AssistantAnswer> _fuelNeed(String g) async {
    final st = await fuel.stats(g, DateRange.lastDays(ctx.now, 30));
    final stock = await fuel.stock(g);
    if (st.consumedMl == 0) {
      return const AssistantAnswer('fuel_need', 'لا توجد بيانات استهلاك كافية خلال آخر 30 يوماً لحساب التوقع.');
    }
    final need = st.forecastNext7DaysMl;
    final buy = need - stock.bookMl;
    return AssistantAnswer(
        'fuel_need',
        'بناءً على متوسط استهلاك آخر 30 يوماً (${formatLiters(st.avgDailyMl.round())} يومياً) تحتاج تقريباً '
            '${formatLiters(need)} للأسبوع القادم. المخزون الدفتري ${formatLiters(stock.bookMl)}'
            '${buy > 0 ? '، أي تحتاج شراء ${formatLiters(buy)} تقريباً.' : '، وهو يكفي.'}\n'
            'هذا تقدير إحصائي يعتمد على الاستهلاك المسجل.',
        [AssistantFact('الاحتياج المتوقع', formatLiters(need)), AssistantFact('المخزون', formatLiters(stock.bookMl))]);
  }

  Future<AssistantAnswer> _expenses(String g, _Time t) async {
    final (r, label) = _range(t);
    final rows = await reports.expensesByAccount(g, r);
    final total = rows.fold<int>(0, (a, e) => a + (e['amount'] as int));
    return AssistantAnswer(
        'expenses',
        'مجموع المصروفات $label: ${formatMoney(total)}'
            '${rows.isEmpty ? '' : '\n${rows.map((e) => '• ${e['name']}: ${formatMoney(e['amount'] as int)}').join('\n')}'}',
        [for (final e in rows) AssistantFact(e['name'] as String, formatMoney(e['amount'] as int))]);
  }

  Future<AssistantAnswer> _expenseIncrease(String g) async {
    final (cur, _) = _range(_Time.thisMonth);
    final (prev, _) = _range(_Time.lastMonth);
    final a = {for (final e in await reports.expensesByAccount(g, cur)) e['name'] as String: e['amount'] as int};
    final b = {for (final e in await reports.expensesByAccount(g, prev)) e['name'] as String: e['amount'] as int};
    final ups = <(String, int, int)>[];
    for (final k in a.keys) {
      final before = b[k] ?? 0;
      if (a[k]! > before) ups.add((k, before, a[k]!));
    }
    ups.sort((x, y) => (y.$3 - y.$2).compareTo(x.$3 - x.$2));
    if (ups.isEmpty) return const AssistantAnswer('expense_increase', 'لم تزد أي فئة مصروفات هذا الشهر مقارنة بالشهر الماضي.');
    return AssistantAnswer(
        'expense_increase',
        'المصاريف اللي زادت هذا الشهر مقارنة بالشهر الماضي:\n'
            '${ups.map((u) => '• ${u.$1}: ${formatMoney(u.$2)} ← ${formatMoney(u.$3)} (+${formatMoney(u.$3 - u.$2)})').join('\n')}',
        [for (final u in ups) AssistantFact(u.$1, '+${formatMoney(u.$3 - u.$2)}')]);
  }

  Future<AssistantAnswer> _subscriberCounts(String g) async {
    final c = await subscribers.counts(g);
    return AssistantAnswer(
        'subscribers',
        'عدد المشتركين ${c['total']}: فعال ${c['active']}، متوقف ${c['stopped']}، غير مسدد ${c['debtors']}. '
            'مجموع الأمبيرات المباعة (الفعالة) ${c['amps']} أمبير.',
        [
          AssistantFact('الكل', '${c['total']}'),
          AssistantFact('فعال', '${c['active']}'),
          AssistantFact('الأمبيرات', '${c['amps']}'),
        ]);
  }

  Future<AssistantAnswer> _runHours(String g, _Time t) async {
    final (r, label) = _range(t);
    final h = await ops.runHours(g, r);
    return AssistantAnswer('run_hours', 'ساعات تشغيل المولدة $label حسب سجل التشغيل: ${h.toStringAsFixed(1)} ساعة.',
        [AssistantFact('ساعات التشغيل', h.toStringAsFixed(1))]);
  }

  /// Revenue forecast: average of the last 3 complete months of invoiced
  /// revenue and of collections.
  Future<AssistantAnswer> _forecast(String g) async {
    final n = ctx.now;
    var rev = 0, col = 0, months = 0;
    for (var i = 1; i <= 3; i++) {
      final r = DateRange.month(DateTime(n.year, n.month - i, 1));
      final p = await reports.pnl(g, r);
      if (p.revenue == 0 && p.expenses == 0) continue;
      rev += p.revenue;
      col += await reports.collections(g, r);
      months++;
    }
    if (months == 0) return const AssistantAnswer('forecast', 'لا توجد أشهر مكتملة كافية لحساب التوقع.');
    return AssistantAnswer(
        'forecast',
        'التوقع للشهر القادم (متوسط آخر $months أشهر مكتملة): إيرادات ${formatMoney(rev ~/ months)}، '
            'تحصيل متوقع ${formatMoney(col ~/ months)}. هذا متوسط إحصائي وليس رقماً مؤكداً.',
        [AssistantFact('إيرادات متوقعة', formatMoney(rev ~/ months)), AssistantFact('تحصيل متوقع', formatMoney(col ~/ months))]);
  }

  /// Unusual expenses (category > 1.5× its 3-month average), fuel anomalies
  /// and cash-box differences.
  Future<AssistantAnswer> _anomalies(String g) async {
    final lines = <String>[];
    if (ctx.can(Perm.financeView)) {
      final n = ctx.now;
      final cur = {
        for (final e in await reports.expensesByAccount(g, DateRange.month(n))) e['name'] as String: e['amount'] as int
      };
      final hist = <String, int>{};
      for (var i = 1; i <= 3; i++) {
        for (final e in await reports.expensesByAccount(g, DateRange.month(DateTime(n.year, n.month - i, 1)))) {
          hist[e['name'] as String] = (hist[e['name']] ?? 0) + (e['amount'] as int);
        }
      }
      cur.forEach((k, v) {
        final avg = (hist[k] ?? 0) / 3;
        if (avg > 0 && v > avg * 1.5) {
          lines.add('• مصروف "$k" هذا الشهر ${formatMoney(v)} أعلى من متوسطه ${formatMoney(avg.round())}.');
        }
      });
      final diffs = await ctx.db.rawQuery('''SELECT close_date, difference FROM cash_closings
          WHERE generator_id = ? AND difference != 0 ORDER BY close_date DESC LIMIT 5''', [g]);
      for (final d in diffs) {
        lines.add('• فرق صندوق ${formatMoney(d['difference'] as int)} بتاريخ ${d['close_date']}.');
      }
    }
    final fs = await fuel.stats(g, DateRange.lastDays(ctx.now, 30));
    for (final a in fs.anomalies) {
      lines.add('• ${a['day']}: استهلاك كاز ${formatLiters(a['ml'] as int)} — ${a['reason']}.');
    }
    final st = await fuel.stock(g);
    if (st.lastDipMl != null) {
      final gap = st.bookMl - st.lastDipMl!;
      if (gap.abs() > 20000) {
        lines.add('• فرق بين المخزون الدفتري (${formatLiters(st.bookMl)}) وآخر قياس فعلي (${formatLiters(st.lastDipMl!)}).');
      }
    }
    final faults = await ops.faults(g, openOnly: true);
    if (faults.isNotEmpty) lines.add('• يوجد ${faults.length} عطل مفتوح.');
    if (lines.isEmpty) return const AssistantAnswer('anomalies', 'لم أجد مؤشرات غير طبيعية في البيانات المسجلة.');
    return AssistantAnswer('anomalies', 'ملاحظات تستحق المراجعة:\n${lines.join('\n')}');
  }
}

