import 'package:flutter/services.dart';
import 'package:generator_core/generator_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Paper sizes supported for printing.
enum PaperSize { roll58, roll80, a5, a4 }

extension PaperFormat on PaperSize {
  PdfPageFormat get format => switch (this) {
    PaperSize.roll58 => const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm),
    PaperSize.roll80 => const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm),
    PaperSize.a5 => PdfPageFormat.a5.copyWith(marginLeft: 24, marginRight: 24, marginTop: 24, marginBottom: 24),
    PaperSize.a4 => PdfPageFormat.a4.copyWith(marginLeft: 28, marginRight: 28, marginTop: 28, marginBottom: 28),
  };
  String get label => switch (this) {
    PaperSize.roll58 => 'حراري 58 مم',
    PaperSize.roll80 => 'حراري 80 مم',
    PaperSize.a5 => 'A5',
    PaperSize.a4 => 'A4',
  };
  bool get isRoll => this == PaperSize.roll58 || this == PaperSize.roll80;
}

/// Builds Arabic right-to-left PDF documents with an embedded Arabic font so
/// text shapes correctly on any printer or viewer.
class PdfService {
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> theme() async {
    if (_theme != null) return _theme!;
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
    // Naskh has no Latin glyphs (receipt codes, "Generator OS"), so Noto Sans
    // is the fallback for Latin characters and punctuation.
    final latin = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final latinBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    return _theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [latin, latinBold]);
  }

  static final _arabic = RegExp('[\u0600-\u06FF]');

  /// Latin-only values (codes, dates, times) are laid out left-to-right so
  /// they are not reordered inside the right-to-left page.
  static pw.TextDirection dirOf(String s) => _arabic.hasMatch(s) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  static final _ltrToken = RegExp(r'[A-Za-z]|^\(?\d{2,4}[-/:.]\d');

  /// Text that may mix Arabic with Latin codes/dates. The PDF engine reverses
  /// Latin letters embedded in Arabic runs, so mixed strings are split into
  /// direction runs rendered as separate widgets inside a right-to-left wrap.
  static pw.Widget txt(String s, {pw.TextStyle? style, pw.TextAlign? align}) {
    if (!_arabic.hasMatch(s)) {
      return pw.Text(s, style: style, textAlign: align, textDirection: pw.TextDirection.ltr);
    }
    final tokens = s.split(' ');
    if (!tokens.any(_ltrToken.hasMatch)) {
      return pw.Text(s, style: style, textAlign: align, textDirection: pw.TextDirection.rtl);
    }
    final runs = <(bool, String)>[];
    for (final t in tokens) {
      final ltr = _ltrToken.hasMatch(t) && !_arabic.hasMatch(t);
      if (runs.isNotEmpty && runs.last.$1 == ltr) {
        runs[runs.length - 1] = (ltr, '${runs.last.$2} $t');
      } else {
        runs.add((ltr, t));
      }
    }
    return pw.Wrap(
      spacing: 3,
      children: [
        for (final (ltr, run) in runs)
          if (run.trim().isNotEmpty)
            pw.Text(run.trim(), style: style, textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl),
      ],
    );
  }

  /// Table whose cells each get the right text direction.
  static pw.Widget _table(List<String> headers, List<List<String>> rows, double size, {PdfColor? headerColor}) {
    pw.Widget cell(String v, {bool head = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: txt(
        v,
        style: pw.TextStyle(fontSize: size, fontWeight: head ? pw.FontWeight.bold : null),
      ),
    );
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
      children: [
        pw.TableRow(
          decoration: headerColor == null ? null : pw.BoxDecoration(color: headerColor),
          children: [for (final h in headers.reversed) cell(h, head: true)],
        ),
        for (final r in rows) pw.TableRow(children: [for (final c in r.reversed) cell(c)]),
      ],
    );
  }

  static pw.Widget _kv(String k, String v, {bool bold = false, double size = 10}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(k, style: pw.TextStyle(fontSize: size)),
        ),
        txt(
          v,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      ],
    ),
  );

  static Future<List<int>> receipt(Map<String, Object?> r, PaperSize paper) async {
    final doc = pw.Document(theme: await theme(), title: 'وصل ${r['receipt_no']}');
    final size = paper == PaperSize.roll58 ? 8.5 : 10.0;
    final reversed = r['reversal_of'] != null;
    doc.addPage(
      pw.Page(
        pageFormat: paper.format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '${r['generator_name']}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: size + 4, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              reversed ? 'إشعار إلغاء دفعة' : 'وصل استلام',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: size + 1),
            ),
            pw.Divider(thickness: 0.6),
            _kv('رقم الوصل', '${r['receipt_no']}', size: size),
            _kv('التاريخ', (r['paid_at'] as String).substring(0, 16).replaceFirst('T', ' '), size: size),
            _kv('المشترك', '${r['full_name']}', size: size),
            _kv('رقم الاشتراك', '${r['account_no']}', size: size),
            _kv('الأمبيرات', '${r['amps']}', size: size),
            if (r['collector_name'] != null) _kv('الجابي', '${r['collector_name']}', size: size),
            pw.Divider(thickness: 0.6),
            _kv('المبلغ المستلم', formatMoney(r['amount'] as int), bold: true, size: size + 2),
            _kv('الرصيد المتبقي', formatMoney(r['balance_after'] as int), size: size),
            pw.Divider(thickness: 0.6),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: 'GOS-R:${r['id']}',
                width: paper.isRoll ? 60 : 80,
                height: paper.isRoll ? 60 : 80,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'شكراً لتسديدكم',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: size),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static Future<List<int>> statement({
    required Map<String, Object?> subscriber,
    required Statement st,
    required List<Map<String, Object?>> invoices,
    PaperSize paper = PaperSize.a4,
  }) async {
    final doc = pw.Document(theme: await theme(), title: 'كشف حساب ${subscriber['full_name']}');
    final roll = paper.isRoll;
    final size = roll ? 9.0 : 11.0;
    doc.addPage(
      pw.MultiPage(
        pageFormat: paper.format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Text(
            '${subscriber['generator_name']}',
            style: pw.TextStyle(fontSize: size + 5, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('كشف حساب مشترك — ${st.period}', style: pw.TextStyle(fontSize: size + 2)),
          pw.SizedBox(height: 8),
          _kv('المشترك', '${subscriber['full_name']}', size: size),
          _kv('رقم الاشتراك', '${subscriber['account_no']}', size: size),
          _kv(
            'الأمبيرات × السعر',
            '${subscriber['amps']} × ${formatMoney(subscriber['amp_price'] as int)}',
            size: size,
          ),
          pw.Divider(),
          _kv('الرصيد السابق', formatMoney(st.previousBalance), size: size),
          _kv('فاتورة الشهر', formatMoney(st.invoiced), size: size),
          _kv('الخصومات والإعفاءات', formatMoney(st.discounts), size: size),
          if (st.adjustments != 0) _kv('تسويات', formatMoney(st.adjustments), size: size),
          _kv('المدفوعات', formatMoney(st.payments), size: size),
          _kv('الرصيد المتبقي للشهر', formatMoney(st.closingBalance), bold: true, size: size),
          _kv('إجمالي الدين الحالي', formatMoney(st.totalDebt), bold: true, size: size + 1),
          pw.SizedBox(height: 10),
          if (st.movements.isNotEmpty)
            _table(
              ['التاريخ', 'البيان', 'مدين', 'دائن'],
              [
                for (final m in st.movements)
                  [
                    '${m['entry_date']}',
                    '${m['description']}',
                    (m['debit'] as int) > 0 ? formatMoney(m['debit'] as int, withCurrency: false) : '',
                    (m['credit'] as int) > 0 ? formatMoney(m['credit'] as int, withCurrency: false) : '',
                  ],
              ],
              size - 1,
            ),
          if (!roll && invoices.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'سجل الفواتير',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: size),
            ),
            _table(
              ['الشهر', 'المبلغ', 'المسدد', 'المتبقي'],
              [
                for (final i in invoices.take(24))
                  [
                    '${i['period']}',
                    formatMoney(i['current_net'] as int, withCurrency: false),
                    formatMoney(i['paid'] as int, withCurrency: false),
                    formatMoney(i['unpaid'] as int, withCurrency: false),
                  ],
              ],
              size - 1,
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static Future<List<int>> invoice(
    Map<String, Object?> inv,
    String generatorName,
    int totalDebt,
    PaperSize paper,
  ) async {
    final doc = pw.Document(theme: await theme(), title: 'فاتورة ${inv['period']}');
    final size = paper.isRoll ? 9.0 : 11.0;
    doc.addPage(
      pw.Page(
        pageFormat: paper.format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              generatorName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: size + 4, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'فاتورة اشتراك شهر ${inv['period']}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: size),
            ),
            pw.Divider(),
            _kv('المشترك', '${inv['full_name']}', size: size),
            _kv('رقم الاشتراك', '${inv['account_no']}', size: size),
            _kv('الأمبيرات', '${inv['amps']}', size: size),
            _kv('سعر الأمبير', formatMoney(inv['amp_price'] as int), size: size),
            _kv('المبلغ', formatMoney(inv['gross'] as int), size: size),
            if ((inv['discount'] as int) > 0)
              _kv(
                'خصم${inv['discount_reason'] != null ? ' (${inv['discount_reason']})' : ''}',
                formatMoney(inv['discount'] as int),
                size: size,
              ),
            if (inv['current_net'] != inv['net'])
              _kv('بعد التعديل', formatMoney(inv['current_net'] as int), size: size),
            pw.Divider(),
            _kv('صافي الفاتورة', formatMoney(inv['current_net'] as int), bold: true, size: size + 1),
            _kv('إجمالي الدين الحالي', formatMoney(totalDebt), bold: true, size: size),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Generic tabular report (landscape A4).
  static Future<List<int>> table(String title, String subtitle, List<String> headers, List<List<String>> rows) async {
    final doc = pw.Document(theme: await theme(), title: title);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape.copyWith(
          marginLeft: 24,
          marginRight: 24,
          marginTop: 24,
          marginBottom: 24,
        ),
        textDirection: pw.TextDirection.rtl,
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            txt(subtitle, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (c) =>
            txt('صفحة ${c.pageNumber} من ${c.pagesCount} — Generator OS', style: const pw.TextStyle(fontSize: 8)),
        build: (_) => [_table(headers, rows, 9, headerColor: const PdfColor.fromInt(0xFFE3EEF1))],
      ),
    );
    return doc.save();
  }
}
